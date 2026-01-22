const {onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require('firebase-functions/v2/scheduler');
const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const functions = require("firebase-functions/v2");
const admin = require('firebase-admin');
const axios = require('axios');
const cors = require('cors');
const express = require("express");
admin.initializeApp();
const db = admin.firestore();
db.settings({ ignoreUndefinedProperties: true });
const auth = admin.auth();
const app = express();
app.use(cors({origin: true}));
const {defineSecret} = require('firebase-functions/params');
const {SQSClient, SendMessageCommand, ReceiveMessageCommand, DeleteMessageBatchCommand,} = require("@aws-sdk/client-sqs");
const crypto = require('crypto');
const normInstanceId = (s) => String(s || '').trim().toUpperCase(); // evita variação de caixa/espaço
const hashInstanceId = (s) => crypto.createHash('sha256').update(normInstanceId(s), 'utf8').digest('hex');
const ZAPI_ENC_KEY = defineSecret('ZAPI_ENC_KEY');
const ENCRYPTION_KEY = defineSecret('ENCRYPTION_KEY');
const AWS_ACCESS_KEY_ID        = defineSecret('AWS_ACCESS_KEY_ID');
const AWS_SECRET_ACCESS_KEY    = defineSecret('AWS_SECRET_ACCESS_KEY');
const AWS_REGION               = defineSecret('AWS_REGION');
const AWS_SQS_COMPANY_QUEUE_URL= defineSecret('AWS_SQS_COMPANY_QUEUE_URL');
const AWS_SQS_REPORTS_QUEUE_URL = defineSecret('AWS_SQS_REPORTS_QUEUE_URL');
const ZAPI_HOSTS = ['https://api-v2.z-api.io', 'https://api.z-api.io',];


async function callZ(instanceId, token, path, payload, headers = {}, timeout = 15000) {
    let lastErr = null;

    const enc = encodeURIComponent;
    for (const host of ZAPI_HOSTS) {
        const baseUrl = `${host}/instances/${enc(instanceId)}/token/${enc(token)}`;
        const url = `${baseUrl}${path}`;

        try {
            const resp = await axios.post(
                url,
                payload ?? {},
                { headers: { 'Content-Type': 'application/json', ...headers }, timeout }
            );

            const data = resp?.data;
            // Alguns tenants retornam 200 com corpo de erro
            if (data && (data.error || /Unable to find matching target resource method/i.test(String(data.message || '')))) {
                lastErr = { host, status: 404, data };
                logger.warn('Z-API respondeu 200 com corpo de erro', { host, path, status: resp.status });
                continue; // tenta próximo host
            }

            logger.info('Z-API OK', { host, path, status: resp.status });
            return { host, resp };
        } catch (e) {
            lastErr = { host, status: e?.response?.status || 500, data: e?.response?.data || e?.message };
            logger.warn('Z-API falhou', { host, path, status: lastErr.status });
            continue; // tenta próximo host
        }
    }

    const err = new Error('Z-API request failed on all hosts');
    err.status = lastErr?.status || 500;
    err.data   = lastErr?.data;
    throw err;
}

function decryptIfNeeded(value, fieldName = '') {
    if (!value || typeof value !== 'string') return value;

    const looksV1 = value.startsWith('enc:v1:');
    // heurística simples: base64 “comprido” (evita chamar secret pra plaintext curta)
    const looksRawB64 = /^[A-Za-z0-9+/=]{40,}$/.test(value);

    // se não parece cifrado, devolve como está
    if (!looksV1 && !looksRawB64) return value;

    // só aqui tentamos obter a chave (evita WARNING quando for plaintext)
    let keyB64;
    try {
        keyB64 = ZAPI_ENC_KEY.value();
    } catch {
        keyB64 = process.env.ZAPI_ENC_KEY; // fallback opcional
    }
    if (!keyB64) throw new Error('ZAPI_ENC_KEY não configurada');

    const key = Buffer.from(keyB64, 'base64');

    const tryAesGcm = (iv, ct, tag) => {
        try {
            const dec = crypto.createDecipheriv('aes-256-gcm', key, iv);
            dec.setAuthTag(tag);
            return Buffer.concat([dec.update(ct), dec.final()]).toString('utf8');
        } catch {
            return null;
        }
    };

    if (looksV1) {
        const buf = Buffer.from(value.slice(7), 'base64');
        if (buf.length < 12 + 16 + 1) throw new Error('cipher muito curto (v1)');
        const iv  = buf.subarray(0, 12);
        const ct  = buf.subarray(12, buf.length - 16);
        const tag = buf.subarray(buf.length - 16);
        const out = tryAesGcm(iv, ct, tag);
        if (out !== null) return out;
        throw new Error(`Falha ao descriptografar (v1) ${fieldName || ''}`.trim());
    }

    // legado sem prefixo: tenta (iv|ct|tag) e (iv|tag|ct)
    try {
        const b = Buffer.from(value, 'base64');
        if (b.length >= 12 + 16 + 1) {
            const ivA  = b.subarray(0, 12);
            const ctA  = b.subarray(12, b.length - 16);
            const tagA = b.subarray(b.length - 16);
            const outA = tryAesGcm(ivA, ctA, tagA);
            if (outA !== null) return outA;

            const ivB  = b.subarray(0, 12);
            const tagB = b.subarray(12, 28);
            const ctB  = b.subarray(28);
            const outB = tryAesGcm(ivB, ctB, tagB);
            if (outB !== null) return outB;
        }
    } catch {
        // não era base64 válido → trata como plaintext
    }

    return value; // não parecia cifrado de verdade
}


// Configuração centralizada
const META_CONFIG = {
    collection: 'APIs',
    docId: 'meta',
    fields: {
        clientId: 'metaClientID',
        clientSecret: 'metaClientSecret',
        refreshToken: 'metaRefreshToken',
        baseUrl: 'metaBaseURL'
    }
};

exports.sendIncomingMessageNotification = onDocumentCreated(
    'empresas/{empresaId}/phones/{phoneId}/whatsappChats/{chatId}/messages/{msgId}',
    async (event) => {
        try {
            const { empresaId, phoneId, chatId } = event.params;
            const msg = event.data?.data() ?? {};

            // ignora mensagens enviadas pelo operador
            if (msg.fromMe) return;

            // mensagem de preview
            const isText = (msg.type ?? 'text') === 'text';
            const body = isText
                ? String(msg.content ?? '').substring(0, 40)
                : `📎 ${(msg.type ?? 'arquivo')[0].toUpperCase()}${(msg.type ?? 'arquivo').slice(1)} recebido`;

            // pega nome/foto do contato (prioriza o que veio no webhook, senão Firestore)
            const chatSnap = await db
                .doc(`empresas/${empresaId}/phones/${phoneId}/whatsappChats/${chatId}`)
                .get();
            const chatData = chatSnap.exists ? (chatSnap.data() || {}) : {};
            const chatName = msg.senderName || chatData.name || 'Contato';
            const contactPhoto = msg.senderPhoto || chatData.contactPhoto || '';

            // coleta tokens (empresa + colaboradores dessa empresa)
            const tokens = new Set();
            const empresaSnap = await db.doc(`empresas/${empresaId}`).get();
            const empTok = empresaSnap.exists ? empresaSnap.data()?.fcmToken : null;
            if (empTok) tokens.add(empTok);

            const usersSnap = await db.collection('users')
                .where('createdBy', '==', empresaId).get();
            usersSnap.forEach((d) => {
                const t = d.data()?.fcmToken;
                if (t) tokens.add(t);
            });

            const tokenArr = [...tokens].filter(Boolean);
            if (!tokenArr.length) return;

            // payload (tudo como string)
            const data = {
                empresaId: String(empresaId),
                phoneId:   String(phoneId),
                chatId:    String(chatId),
                chatName:  String(chatName),
                contactPhoto: String(contactPhoto || ''),
                openChat: 'true',
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
            };

            const notification = {
                title: chatName,
                body,
            };

            const android = { priority: 'high' };
            const apns = {
                headers: { 'apns-priority': '10' },
                payload: { aps: { 'content-available': 1 } },
            };

            // compatível com Admin SDK v12+
            const messaging = admin.messaging();
            const sendChunk = async (chunk) => {
                if (typeof messaging.sendEachForMulticast === 'function') {
                    return await messaging.sendEachForMulticast({
                        tokens: chunk, notification, data, android, apns,
                    });
                }
                if (typeof messaging.sendMulticast === 'function') {
                    return await messaging.sendMulticast({
                        tokens: chunk, notification, data, android, apns,
                    });
                }
                // fallback 1-a-1
                const res = await Promise.all(chunk.map(async (tkn) => {
                    try {
                        const id = await messaging.send({ token: tkn, notification, data, android, apns });
                        return { success: true, messageId: id };
                    } catch (e) { return { success: false, error: e }; }
                }));
                return {
                    successCount: res.filter(r => r.success).length,
                    failureCount: res.filter(r => !r.success).length,
                    responses: res,
                };
            };

            for (let i = 0; i < tokenArr.length; i += 500) {
                const part = tokenArr.slice(i, i + 500);
                const res = await sendChunk(part);
                console.log(`push chat:${chatId} – ok:${res.successCount} nok:${res.failureCount}`);
            }
        } catch (err) {
            console.error('Erro push mensagem:', err);
        }
    }
);

// Função agendada para verificar a cada minuto
exports.checkUserActivity_v2 = onSchedule('every 1 minutes', async (event) => {
    console.log('Iniciando verificação de atividade dos usuários...');

    try {
        // Parâmetros para listagem de usuários
        const maxResults = 1000; // Máximo de usuários por chamada
        let nextPageToken = undefined;
        let allUsers = [];

        // Paginação para listar todos os usuários
        do {
            const listUsersResult = await admin.auth().listUsers(maxResults, nextPageToken);
            allUsers = allUsers.concat(listUsersResult.users);
            nextPageToken = listUsersResult.pageToken;
        } while (nextPageToken);

        console.log(`Total de usuários encontrados: ${allUsers.length}`);

        const now = admin.firestore.Timestamp.now();
        const cutoffTime = now.toMillis() - (72 * 60 * 60 * 1000); // 72 horas atrás

        const promises = allUsers.map(async (userRecord) => {
            const uid = userRecord.uid;

            // Tentar obter o documento do usuário na coleção 'users'
            let userDocRef = db.collection('users').doc(uid);
            let userDoc = await userDocRef.get();

            if (!userDoc.exists) {
                // Se não encontrado em 'users', tentar em 'empresas'
                userDocRef = db.collection('empresas').doc(uid);
                userDoc = await userDocRef.get();

                if (!userDoc.exists) {
                    console.log(`Documento do usuário não encontrado para UID: ${uid}`);
                    return;
                }
            }

            const userData = userDoc.data();

            if (!userData.lastActivity) {
                console.log(`Campo 'lastActivity' ausente para UID: ${uid}`);
                return;
            }

            const lastActivity = userData.lastActivity.toMillis();

            if (lastActivity < cutoffTime) {
                console.log(`Usuário inativo encontrado: UID=${uid}`);

                // Revogar tokens para forçar logout
                await admin.auth().revokeRefreshTokens(uid);
                console.log(`Tokens revogados para UID: ${uid}`);

                // Atualizar documento do usuário removendo fcmToken e sessionId
                await userDocRef.update({
                    fcmToken: admin.firestore.FieldValue.delete(),
                    sessionId: admin.firestore.FieldValue.delete(),
                });
                console.log(`Campos 'fcmToken' e 'sessionId' removidos para UID: ${uid}`);
            }
        });

        // Executar todas as promessas em paralelo
        await Promise.all(promises);

        console.log('Verificação de atividade concluída.');
    } catch (error) {
        console.error('Erro durante a verificação de atividade dos usuários:', error);
    }

    return;
});

// Função para renovar o token (executada a cada minuto)
exports.scheduledTokenRefresh_v2 = onSchedule('every 1 minutes', async (event) => {
    try {
        const docRef = admin.firestore().collection(META_CONFIG.collection).doc(META_CONFIG.docId);
        const doc = await docRef.get();

        if (!doc.exists) throw new Error('Documento de configuração não encontrado');

        const data = doc.data();
        const expiresAt = data.expiresAt || 0;

        // Renova se expirar em menos de 5 minutos
        if (Date.now() > (expiresAt - 300000)) {
            const response = await axios.get(`${data[META_CONFIG.fields.baseUrl]}/oauth/access_token`, {
                params: {
                    grant_type: 'fb_exchange_token',
                    client_id: data[META_CONFIG.fields.clientId],
                    client_secret: data[META_CONFIG.fields.clientSecret],
                    fb_exchange_token: data[META_CONFIG.fields.refreshToken]
                }
            });

            await docRef.update({
                access_token: response.data.access_token,
                expiresAt: Date.now() + (response.data.expires_in * 1000),
                lastRefresh: admin.firestore.FieldValue.serverTimestamp()
            });

            console.log('Token renovado com sucesso!');
        }
        return;
    } catch (error) {
        console.error('Erro na renovação do token:', error);
        return;
    }
});

// Endpoint para buscar insights (equivalente ao /dynamic_insights)
exports.getInsights_v2 = functions.https.onRequest(async (req, res) => {
    // Configura os headers de CORS para permitir requisições da Web
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST');
    res.set('Access-Control-Allow-Headers', 'Content-Type');

    // Se for uma requisição OPTIONS (preflight), encerre aqui
    if (req.method === 'OPTIONS') {
        return res.status(204).send('');
    }

    // Log de informações básicas da requisição
    console.log("Request method:", req.method);
    console.log("Request headers:", req.headers);
    console.log("Raw body:", req.rawBody ? req.rawBody.toString() : "Nenhum rawBody");
    console.log("Initial parsed body:", req.body);

    // Se req.body estiver vazio mas req.rawBody existir, tenta fazer o parse manual
    if ((!req.body || Object.keys(req.body).length === 0) && req.rawBody) {
        try {
            req.body = JSON.parse(req.rawBody.toString());
            console.log("Parsed body from rawBody:", req.body);
        } catch (e) {
            console.error("Erro ao parsear rawBody:", e);
            return res.status(400).json({
                status: 'error',
                message: 'Corpo da requisição inválido'
            });
        }
    } else {
        console.log("Body já preenchido:", req.body);
    }

    try {
        console.log('Recebendo requisição para getInsights');

        // Obtém os parâmetros da requisição
        let {id, level, start_date, end_date} = req.body;
        console.log("Parâmetros recebidos:", {id, level, start_date, end_date});

        if (!id || !level || !start_date) {
            console.log('Parâmetros obrigatórios faltando:', req.body);
            return res.status(400).json({
                status: 'error',
                message: 'Parâmetros obrigatórios faltando'
            });
        }
        // Se end_date não for informado, usa start_date
        if (!end_date) {
            end_date = start_date;
            console.log("end_date não informado; usando start_date:", start_date);
        }

        if (!['account', 'campaign', 'adset'].includes(level.toLowerCase())) {
            console.log("Nível inválido:", level);
            return res.status(400).json({
                status: 'error',
                message: 'Nível inválido. Valores permitidos: account, campaign, adset'
            });
        }

        console.log("Parâmetros validados:", {start_date, end_date});

        // Busca as configurações (como base URL e access token)
        const docRef = admin.firestore().collection(META_CONFIG.collection).doc(META_CONFIG.docId);
        const doc = await docRef.get();
        if (!doc.exists) {
            console.log("Documento de configuração não encontrado");
            return res.status(500).json({
                status: 'error',
                message: 'Configuração da API não encontrada'
            });
        }
        const metaData = doc.data();
        console.log("META_CONFIG:", metaData);

        if (!metaData.access_token) {
            console.log("Access Token está ausente.");
            return res.status(400).json({
                status: 'error',
                code: 'MISSING_ACCESS_TOKEN',
                message: 'Access Token está ausente. Por favor, tente novamente mais tarde.'
            });
        }

        // Realiza a requisição para a API da Meta usando o intervalo de datas fornecido
        const response = await axios.get(
            `${metaData[META_CONFIG.fields.baseUrl]}/${id}/insights`,
            {
                params: {
                    access_token: metaData.access_token,
                    fields:
                        'reach,cpm,impressions,inline_link_clicks,cost_per_inline_link_click,clicks,cost_per_conversion,conversions,cpc,inline_post_engagement,spend,date_start,date_stop',
                    time_range: JSON.stringify({since: start_date, until: end_date}),
                    time_increment: 1,
                    level: level.toLowerCase()
                }
            }
        );

        console.log("Resposta da API da Meta:", response.data);

        // Se a API retornar insights (array com pelo menos 1 item)
        if (
            response.data &&
            response.data.data &&
            Array.isArray(response.data.data) &&
            response.data.data.length > 0
        ) {
            const insightsArray = response.data.data;

            // Agrega os dados ignorando os campos de data
            const aggregatedInsights = insightsArray.reduce((acc, insight) => {
                Object.keys(insight).forEach((key) => {
                    if (key === 'date_start' || key === 'date_stop') return;
                    const value = insight[key];
                    const numValue = parseFloat(value);
                    if (!isNaN(numValue)) {
                        acc[key] = (acc[key] || 0) + numValue;
                    } else {
                        if (!(key in acc)) {
                            acc[key] = value;
                        }
                    }
                });
                return acc;
            }, {});

            // Sobrescreve as datas com os valores recebidos na requisição
            aggregatedInsights.date_start = start_date;
            aggregatedInsights.date_stop = end_date;

            return res.json({
                status: 'success',
                data: {
                    insights: [aggregatedInsights]
                }
            });
        } else {
            // Se nenhum insight for encontrado, retorna métricas zeradas com as datas informadas
            console.log("Nenhum insight encontrado. Retornando objeto vazio com as datas selecionadas.");
            const emptyInsights = {
                reach: 0,
                cpm: 0,
                impressions: 0,
                inline_link_clicks: 0,
                cost_per_inline_link_click: 0,
                clicks: 0,
                cost_per_conversion: 0,
                conversions: 0,
                cpc: 0,
                inline_post_engagement: 0,
                spend: 0,
                date_start: start_date,
                date_stop: end_date
            };
            return res.json({
                status: 'success',
                data: {
                    insights: [emptyInsights]
                }
            });
        }
    } catch (error) {
        console.error("Erro completo:", {
            code: error.response?.status,
            data: error.response?.data,
            message: error.message
        });
        const statusCode = error.response?.status || 500;
        const errorMessage = error.response?.data?.error?.message || 'Erro interno';
        return res.status(statusCode).json({
            status: 'error',
            code: error.response?.data?.error?.code || 'UNKNOWN_ERROR',
            message: errorMessage
        });
    }
});

// Helper para sanitizar dados da Meta
const sanitizeMetaData = (data) => {
    return Object.entries(data).reduce((acc, [key, value]) => {
        // Converter tipos incompatíveis com Firestore
        if (value instanceof Object && !(value instanceof Array)) {
            acc[key] = sanitizeMetaData(value);
        } else if (value !== undefined && value !== null) {
            acc[key] = value;
        }
        return acc;
    }, {});
};
//FUNCTIONS AWS

exports.sendMeetingRequestToSQS = onRequest(async (req, res) => {
    // Configura CORS
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");

    if (req.method === "OPTIONS") {
        return res.status(204).send("");
    }

    try {
        // Apenas aceitar POST
        if (req.method !== "POST") {
            console.log("[sendMeetingRequestToSQS] Método não permitido:", req.method); // ADICIONADO
            return res.status(405).send("Método não permitido");
        }

        console.log("[sendMeetingRequestToSQS] Requisição recebida com body:", req.body); // ADICIONADO

        // Extraia os dados do corpo da requisição
        const {motivo, assunto, dataReuniao, nomeEmpresa, tipoSolicitacao, createdAt} = req.body;

        // Validação simples
        if (!motivo || !dataReuniao || !nomeEmpresa || !tipoSolicitacao) {
            console.log("[sendMeetingRequestToSQS] Campos obrigatórios ausentes no body."); // ADICIONADO
            return res.status(400).json({error: "Campos obrigatórios ausentes"});
        }

        // Constrói o payload para enviar ao SQS
        const payload = {
            motivo,
            assunto,
            dataReuniao,
            nomeEmpresa,
            tipoSolicitacao,
            createdAt: createdAt || new Date().toISOString(),
        };

        console.log("[sendMeetingRequestToSQS] Payload construído:", payload); // ADICIONADO

        // Parâmetros para enviar a mensagem para o SQS
        const params = {
            MessageBody: JSON.stringify(payload),
            QueueUrl: process.env.AWS_QUEUE_URL,
        };

        console.log("[sendMeetingRequestToSQS] Enviando mensagem à fila SQS:", params.QueueUrl); // ADICIONADO

        const sqsClient = buildSqsClient();
        const command = new SendMessageCommand(params);
        const result = await sqsClient.send(command);

        console.log("[sendMeetingRequestToSQS] Conexão com SQS bem-sucedida!"); // ADICIONADO
        console.log("[sendMeetingRequestToSQS] Mensagem enviada ao SQS. Result:", result); // ADICIONADO
        console.log("[sendMeetingRequestToSQS] Payload enviado:", payload); // ADICIONADO

        return res.status(200).json({
            message: "Dados enviados para o SQS com sucesso",
            result: result,
            payload: payload,
        });
    } catch (error) {
        console.error("[sendMeetingRequestToSQS] Erro ao enviar dados para o SQS:", error);
        return res.status(500).json({error: "Erro interno ao enviar dados para o SQS"});
    }
});

// FIM FUNCTIONS AWS

//INÍCIO FUNCTIONS Z-API / WHATSAPP

const INBOUND_TYPES = [
    "ReceivedCallback",        // padrão
    "MessageReceived",         // 1ª resposta em chat novo
    "TextReceived",            // algumas contas enviam assim
];

function normalizeDigits(s) {
    return String(s || '').replace(/\D/g, '');
}

// gera variações BR e também com/sem 55
function buildPhoneCandidates(phoneDigits) {
    const digits = normalizeDigits(phoneDigits);
    const candidates = new Set();
    if (!digits) return [];

    // bruto
    candidates.add(digits);

    // com/sem 55
    if (digits.startsWith('55')) {
        candidates.add(digits.slice(2)); // sem 55
    } else if (digits.length >= 10 && digits.length <= 11) {
        candidates.add('55' + digits);   // com 55
    }

    // aplicar regra do "9" após DDD (para qualquer versão que tenha 55+DDD...)
    const snapshot = [...candidates];
    for (const d of snapshot) {
        const dd = normalizeDigits(d);

        // tenta tanto com 55 quanto sem 55, mas a regra BR mais confiável é com 55 + DDD
        const with55 = dd.startsWith('55') ? dd : (dd.length >= 10 && dd.length <= 11 ? '55' + dd : null);
        if (!with55) continue;

        // 55 + DDD (2) + resto (8 ou 9)
        if (with55.length >= 12) {
            const base = with55.slice(0, 4); // 55 + DDD
            const rest = with55.slice(4);

            // se 9 dígitos e começa com 9 → tenta sem 9
            if (rest.length === 9 && rest[0] === '9') {
                candidates.add(base + rest.slice(1));
                candidates.add((base + rest.slice(1)).slice(2)); // também sem 55
            }

            // se 8 dígitos → tenta com 9
            if (rest.length === 8) {
                candidates.add(base + '9' + rest);
                candidates.add((base + '9' + rest).slice(2)); // também sem 55
            }
        }
    }

    return [...candidates];
}

// ───── lookup a partir do número que chega no webhook ─────
async function getPhoneCtxByNumber(phoneDigits) {
    const variants = buildPhoneCandidates(phoneDigits);

    for (const candidate of variants) {
        const snap = await db
            .collectionGroup('phones')
            .where('phoneId', '==', candidate)     // NÃO usa documentId()
            .limit(1)
            .get();

        if (!snap.empty) {
            const phoneDoc  = snap.docs[0];
            const empresaId = phoneDoc.ref.path.split('/')[1]; // empresas/{empresaId}/phones/…
            return { empresaId, phoneDoc };
        }
    }

    throw new Error(`Número ${phoneDigits} não cadastrado`);
}

// ───── resolve o chatId (reaproveita chat existente) ─────
async function resolveChatIdForNumber({ empresaId, phoneId, phoneDigits }) {
    const digits = String(phoneDigits || '').replace(/\D/g, '');
    const candidates = buildPhoneCandidates(digits);

    const base = db
        .collection('empresas').doc(empresaId)
        .collection('phones').doc(phoneId)
        .collection('whatsappChats');

    // 1) Prioriza chats já no padrão "<número>@s.whatsapp.net"
    for (const cand of candidates) {
        const jidId = `${cand}@s.whatsapp.net`;
        const snap = await base.doc(jidId).get();
        if (snap.exists) return jidId;
    }

    // 2) Depois tenta chats antigos só com dígitos ("55469910...")
    for (const cand of candidates) {
        const snap = await base.doc(cand).get();
        if (snap.exists) return cand;
    }

    // 3) Se não existe, criaremos um NOVO chatId padrão com @s.whatsapp.net
    return `${digits}@s.whatsapp.net`;
}

async function getPhoneCtxByInstance(instanceIdPlain) {
    const hashed = hashInstanceId(instanceIdPlain); // normaliza + SHA-256
    const snap = await db
        .collectionGroup('phones')
        .where('instanceIdHash', '==', hashed)
        .limit(1)
        .get();

    if (snap.empty) throw new Error(`instance ${instanceIdPlain} não cadastrado`);

    const phoneDoc  = snap.docs[0];
    const empresaId = phoneDoc.ref.path.split('/')[1];   // empresas/{empresaId}/phones/…

    return { empresaId, phoneDoc };
}

// ───── refs prontos para chat + messages ─────
function getChatRefs(empresaId, phoneId, chatId) {
    const base = db.collection('empresas')
        .doc(empresaId)
        .collection('phones')
        .doc(phoneId);

    return {
        phoneDocRef : base,
        chatDocRef  : base.collection('whatsappChats').doc(chatId),
        msgsColRef  : base.collection('whatsappChats').doc(chatId).collection('messages')
    };
}

// Função auxiliar para enviar status "Digitando..." (Composing)
async function sendZApiTyping(instanceId, token, clientToken, phone) {
    try {
        const headers = {};
        if (clientToken) headers['client-token'] = clientToken;

        // O endpoint da Z-API para presença
        await axios.post(
            `https://api.z-api.io/instances/${instanceId}/token/${token}/send-presence`,
            {
                phone: phone,
                presence: 'composing' // 'composing' = digitando, 'recording' = gravando audio
            },
            { headers }
        );
    } catch (error) {
        // Não queremos travar o fluxo se isso falhar, apenas logamos um aviso
        console.warn(`[Z-API Presence] Falha ao enviar digitando para ${phone}:`, error.message);
    }
}

const { CloudTasksClient } = require('@google-cloud/tasks');

// Inicializa o cliente do Cloud Tasks
const tasksClient = new CloudTasksClient();

// Tenta pegar o Project ID automaticamente. Se falhar, use a string fixa 'app-io-1c16f'
const PROJECT_ID = process.env.GCLOUD_PROJECT || (process.env.FIREBASE_CONFIG ? JSON.parse(process.env.FIREBASE_CONFIG).projectId : 'app-io-1c16f');

const QUEUE_LOCATION = 'us-central1';
const QUEUE_NAME = 'gpt-buffer'; // Certifique-se que esta fila existe no GCloud
const WORKER_FUNCTION_URL = `https://${QUEUE_LOCATION}-${PROJECT_ID}.cloudfunctions.net/gptQueueWorker`; 

const DEBOUNCE_SECONDS = 10; // Tempo que o bot espera o cliente parar de digitar

// =============================================================================
// WEBHOOK Z-API (Gateway de Entrada)
// =============================================================================

exports.zApiWebhook = onRequest(async (req, res) => {
    try {
        res.set('Access-Control-Allow-Origin', '*');
        res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
        res.set('Access-Control-Allow-Headers', 'Content-Type');
        if (req.method === 'OPTIONS') return res.status(204).send('');

        const data = req.body;

        // --- Sanity Checks ---
        if (!data || typeof data !== 'object') return res.status(200).send('OK');
        if (!data.phone && !data.participantPhone) return res.status(200).send('OK');

        const INBOUND_TYPES = new Set([
            'ReceivedCallback', 'ReceivedCallbackChat', 'ReceivedCallbackAudio',
            'ReceivedCallbackImage', 'ReceivedCallbackVideo', 'ReceivedCallbackSticker',
        ]);

        if (!INBOUND_TYPES.has(data.type)) return res.status(200).send('OK');

        // Normaliza números
        const remoteDigits = String(data.participantPhone || data.phone || '').replace(/\D/g, '');
        const serverDigits = String(data.connectedPhone || data.instanceId || '').replace(/\D/g, '');

        if (!remoteDigits) return res.status(200).send('OK');

        // Busca contexto do telefone (empresaId, phoneDoc)
        let empresaId, phoneDoc;
        try {
            ({ empresaId, phoneDoc } = await getPhoneCtxByInstance(String(data.instanceId || '')));
        } catch (e) {
            if (!serverDigits) throw e;
            ({ empresaId, phoneDoc } = await getPhoneCtxByNumber(serverDigits));
        }

        const phoneId = phoneDoc.id;
        const phoneData = phoneDoc.data() || {};

        // Resolve chatId
        const chatId = await resolveChatIdForNumber({
            empresaId, phoneId, phoneDigits: remoteDigits,
        });

        // Prepara dados da mensagem
        const chatName = data.chatName || data.senderName || remoteDigits;
        const incomingPhoto = String(data.senderPhoto || data.photo || '').trim();
        const photoPatch = incomingPhoto
            ? { contactPhoto: incomingPhoto, photoUpdatedAt: admin.firestore.FieldValue.serverTimestamp() }
            : {};

        let messageContent = '';
        let messageType    = 'text';
        if      (data.text?.message)       { messageContent = data.text.message;       }
        else if (data.audio?.audioUrl)     { messageContent = data.audio.audioUrl;     messageType = 'audio'; }
        else if (data.image?.imageUrl)     { messageContent = data.image.imageUrl;     messageType = 'image'; }
        else if (data.video?.videoUrl)     { messageContent = data.video.videoUrl;     messageType = 'video'; }
        else if (data.sticker?.stickerUrl) { messageContent = data.sticker.stickerUrl; messageType = 'sticker'; }

        const { chatDocRef, msgsColRef } = getChatRefs(empresaId, phoneId, chatId);

        // 1) Grava a mensagem recebida no Firestore
        await msgsColRef.doc().set({
            content    : messageContent,
            type       : messageType,
            timestamp  : admin.firestore.FieldValue.serverTimestamp(),
            fromMe     : data.fromMe === true,
            sender     : data.participantPhone || data.phone,
            senderName : data.senderName || '',
            senderPhoto: data.senderPhoto || data.photo || '',
            zapiId     : data.id || null,
            read       : false,
            status     : 'novo',
            saleValue  : null,
        });

        // 2) Atualiza o chat
        await admin.firestore().runTransaction(async (tx) => {
            const snap = await tx.get(chatDocRef);
            const cur  = snap.exists ? snap.data() : {};
            const curStatus = cur?.status ?? 'novo';
            const preserve = ['atendendo'];
            const newStatus = preserve.includes(curStatus) ? curStatus : 'novo';

            if (['concluido_com_venda', 'recusado'].includes(curStatus)) {
                await chatDocRef.collection('history').add({
                    status    : curStatus,
                    saleValue : cur.saleValue ?? null,
                    changedAt : admin.firestore.FieldValue.serverTimestamp(),
                    updatedBy : 'system',
                });
            }

            tx.set(chatDocRef, {
                chatId,
                arrivalAt : cur.arrivalAt ?? admin.firestore.FieldValue.serverTimestamp(),
                name      : chatName,
                ...photoPatch,
                lastMessage     : messageContent,
                lastMessageTime : new Date().toLocaleTimeString('pt-BR', { hour:'2-digit', minute:'2-digit' }),
                type      : messageType,
                timestamp : admin.firestore.FieldValue.serverTimestamp(),
                status    : newStatus,
                saleValue : newStatus === 'novo' ? null : (cur.saleValue ?? null),
                ...(data.fromMe ? {} : { unreadCount: admin.firestore.FieldValue.increment(1) }),
            }, { merge: true });
        });

        // =========================================================================
        // INTEGRAÇÃO GPT MAKER (DINÂMICA)
        // =========================================================================
        const isFromMe = data.fromMe === true;
        const incomingMsgId = data.id || data.messageId || ('fallback_' + Date.now() + Math.random());

        // A. Verifica Configurações no Documento do Telefone
        const aiConfig = phoneData.ai_agent || {};         
        const gptCreds = phoneData.gpt_integration || {};  

        const isAiEnabled = aiConfig.enabled === true && 
                            !!aiConfig.agentId && 
                            !!gptCreds.api_token;

        // B. Condição de Disparo: IA Ativa + Texto + Não sou eu
        if (isAiEnabled && messageType === 'text' && !isFromMe) {

            // --- NOVO: Envia "Digitando..." IMEDIATAMENTE ---
            // Como vamos esperar DEBOUNCE_SECONDS, é vital avisar o usuário que estamos "vivos"
            const zInst = (typeof decryptIfNeeded === 'function') ? decryptIfNeeded(phoneData.instanceId) : (phoneData.instanceId);
            const zTok  = (typeof decryptIfNeeded === 'function') ? decryptIfNeeded(phoneData.token) : (phoneData.token);
            const zCTok = (typeof decryptIfNeeded === 'function') ? decryptIfNeeded(phoneData.clientToken) : (phoneData.clientToken);

            if (zInst && zTok) {
                 // Dispara sem await para não atrasar o fluxo, ou com await se preferir garantir
                 sendZApiTyping(zInst, zTok, zCTok, remoteDigits);
            }
            // -----------------------------------------------

            const executionToken = `token_${Date.now()}_${Math.random().toString(36).substring(7)}`;
            const bufferColRef = chatDocRef.collection('gpt_buffer');

            try {
                // 1. Salva no Buffer e Atualiza Token de Execução
                await admin.firestore().runTransaction(async (t) => {
                    const doc = await t.get(chatDocRef);
                    const d = doc.data() || {};
                    
                    if ((d.status || 'novo') !== 'novo') return;

                    const bufferDoc = bufferColRef.doc(String(incomingMsgId));
                    t.set(bufferDoc, {
                        content: messageContent,
                        timestamp: admin.firestore.FieldValue.serverTimestamp()
                    }, { merge: true });

                    t.update(chatDocRef, { gptDebounceToken: executionToken });
                });

                // 2. Cria a Task no Cloud Tasks
                const parent = tasksClient.queuePath(PROJECT_ID, QUEUE_LOCATION, QUEUE_NAME);
                
                const task = {
                    httpRequest: {
                        httpMethod: 'POST',
                        url: WORKER_FUNCTION_URL, 
                        headers: { 'Content-Type': 'application/json' },
                        body: Buffer.from(JSON.stringify({
                            empresaId,
                            phoneId,
                            chatId,
                            executionToken,
                            senderNumber: remoteDigits,
                            agentId: aiConfig.agentId,
                            gptToken: gptCreds.api_token
                        })).toString('base64'),
                    },
                    scheduleTime: {
                        seconds: Date.now() / 1000 + DEBOUNCE_SECONDS,
                    },
                };

                await tasksClient.createTask({ parent, task });
                logger.info(`[GPT] Agendado para ${remoteDigits} (Agent: ${aiConfig.agentId})`);
                
                return res.status(200).send('Buffered & Scheduled');

            } catch (e) {
                logger.error('[GPT Webhook] Erro ao agendar:', e);
            }
        }
        // =========================================================================

        // 3) Robô Legado
        try {
            logger.info('[zApiWebhook] Fallback para bot legado', { empresaId, phoneId });
            await maybeHandleByBot({ empresaId, phoneDoc, chatId, messageContent });
        } catch (e) {
            logger.error('Bot handler falhou', e);
        }

        return res.status(200).send('OK');
    } catch (error) {
        logger.error('Erro no webhook Z-API:', error);
        return res.status(200).send('Erro interno, mas ACK enviado');
    }
});

// =============================================================================
// 2. O WORKER (CONSUMIDOR) - FUNÇÃO QUE O CLOUD TASKS CHAMA
// =============================================================================
exports.gptQueueWorker = onRequest(async (req, res) => {
    const { empresaId, phoneId, chatId, executionToken, senderNumber, agentId, gptToken } = req.body;

    logger.info(`[GPT Worker] Acordou para processar token: ${executionToken} (Agent: ${agentId})`);

    if (!agentId || !gptToken) {
        logger.error('[GPT Worker] Abortado: agentId ou gptToken ausentes no payload.');
        return res.status(400).send('Missing GPT Credentials');
    }

    const { chatDocRef, msgsColRef, phoneDocRef } = getChatRefs(empresaId, phoneId, chatId);
    const bufferColRef = chatDocRef.collection('gpt_buffer');
    
    let textsToProcess = [];

    // 2. VERIFICAÇÃO E CONSUMO ATÔMICO
    try {
        await admin.firestore().runTransaction(async (t) => {
            const chatSnap = await t.get(chatDocRef);
            const chatData = chatSnap.data() || {};

            if (chatData.gptDebounceToken !== executionToken) {
                return; 
            }

            const bufferSnaps = await t.get(bufferColRef.orderBy('timestamp', 'asc'));
            
            bufferSnaps.docs.forEach(d => {
                const val = d.data().content;
                if (val) textsToProcess.push(val);
                t.delete(d.ref); 
            });
        });
    } catch (e) {
        logger.error('[GPT Worker] Erro Transação:', e);
        return res.status(500).send('Transaction Error');
    }

    if (textsToProcess.length === 0) {
        logger.info('[GPT Worker] Cancelado (Token antigo ou Buffer vazio).');
        return res.status(200).send('Skipped');
    }

    // 3. PREPARA PROMPT
    const uniqueTexts = [...new Set(textsToProcess)];
    const fullPrompt = uniqueTexts.join(" ");

    logger.info(`[GPT Worker] Enviando Prompt Agrupado: "${fullPrompt}"`);

    // 4. CHAMA GPT E RESPONDE
    try {
        const pData = (await phoneDocRef.get()).data() || {};
        
        const zInstance = (typeof decryptIfNeeded === 'function') ? decryptIfNeeded(pData.instanceId) : (pData.instanceId || process.env.ZAPI_ID);
        const zToken = (typeof decryptIfNeeded === 'function') ? decryptIfNeeded(pData.token) : (pData.token || process.env.ZAPI_TOKEN);
        const zClientToken = (typeof decryptIfNeeded === 'function') ? decryptIfNeeded(pData.clientToken) : (pData.clientToken || process.env.ZAPI_CLIENT_TOKEN);

        if (zInstance && zToken) {
            
            // --- NOVO: Envia "Digitando..." DE NOVO ---
            // Como pode ter passado 10 segundos, o status anterior pode ter sumido.
            // Renovamos agora enquanto a IA "pensa".
            await sendZApiTyping(zInstance, zToken, zClientToken, senderNumber);
            // ------------------------------------------

            // CHAMADA AO GPT MAKER
            const gptResponse = await axios.post(
                `https://api.gptmaker.ai/v2/agent/${agentId}/conversation`, 
                { contextId: senderNumber, prompt: fullPrompt },
                { headers: { 'Authorization': `Bearer ${gptToken}` } }      
            );

            let rawResponse = gptResponse.data.response || gptResponse.data.message;
            let aiMessage = rawResponse;
            let isHandoff = false;

            try {
                const cleanJson = rawResponse.replace(/```json/g, '').replace(/```/g, '').trim();
                if (cleanJson.startsWith('{')) {
                    const parsed = JSON.parse(cleanJson);
                    if (parsed.action === 'handoff') {
                        isHandoff = true;
                        aiMessage = parsed.message;
                    }
                }
            } catch (e) { }

            if (aiMessage) {
                // Envia via Z-API
                const zHeaders = {};
                if (zClientToken) zHeaders['client-token'] = zClientToken;

                await axios.post(`https://api.z-api.io/instances/${zInstance}/token/${zToken}/send-text`, {
                    phone: senderNumber, message: aiMessage
                }, { headers: zHeaders });

                // Salva resposta no histórico
                await msgsColRef.add({
                    content: aiMessage, type: 'text', timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    fromMe: true, sender: senderNumber, status: 'sent', read: true, zapiId: 'gpt_' + Date.now() 
                });

                if (isHandoff) {
                    await chatDocRef.set({
                        lastMessage: aiMessage, 
                        lastMessageTime: new Date().toLocaleTimeString('pt-BR', { hour:'2-digit', minute:'2-digit' }),
                        timestamp: admin.firestore.FieldValue.serverTimestamp(), 
                        status: 'atendendo' 
                    }, { merge: true });
                    
                    if (typeof persistSystemEventMessage === 'function') {
                        await persistSystemEventMessage({ 
                            empresaId, phoneId, chatId, 
                            event: 'handoff', 
                            label: 'IA Handoff', 
                            extra: { agentId: agentId } 
                        });
                    }
                } else {
                    await chatDocRef.set({
                        lastMessage: aiMessage, 
                        lastMessageTime: new Date().toLocaleTimeString('pt-BR', { hour:'2-digit', minute:'2-digit' }),
                        timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    }, { merge: true });
                }

                return res.status(200).send('GPT Worker Done');
            }
        } else {
             logger.error('[GPT Worker] Z-API Credenciais não encontradas no DB.');
             return res.status(400).send('Z-API config missing');
        }
    } catch (err) {
        logger.error('[GPT Worker] Erro final:', err.message);
        return res.status(500).send(err.message);
    }

    return res.status(200).send('Worker Finished');
});




// Função Callable que busca o Workspace ID dinamicamente e depois os agentes
exports.getGptAgents = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Login necessário.');

    // Recebe empresaId E phoneId
    const { empresaId, phoneId } = request.data; 
    
    if (!empresaId || !phoneId) {
        throw new HttpsError('invalid-argument', 'Empresa ID e Phone ID são obrigatórios.');
    }

    try {
        // 1. Busca configurações DENTRO DO TELEFONE
        const phoneDoc = await admin.firestore()
            .collection('empresas')
            .doc(empresaId)
            .collection('phones')
            .doc(phoneId)
            .get();

        if (!phoneDoc.exists) throw new HttpsError('not-found', 'Telefone não encontrado.');

        const data = phoneDoc.data();
        // Acessa o mapa gpt_integration que criamos
        const config = data.gpt_integration;

        if (!config || !config.api_token || !config.workspace_id) {
            // Retorna array vazio se não estiver configurado (sem estourar erro fatal na tela)
            return []; 
        }

        const companyToken = config.api_token;
        const companyWorkspace = config.workspace_id;

        // 2. Chama API do GPT Maker
        const response = await axios.get(
            `https://api.gptmaker.ai/v2/workspace/${companyWorkspace}/agents`, 
            { 
                headers: { 
                    'Authorization': `Bearer ${companyToken}`,
                    'Content-Type': 'application/json'
                } 
            }
        );

        const agents = Array.isArray(response.data) ? response.data : (response.data.data || []);
        
        return agents.map(agent => ({
            id: agent.id,
            name: agent.name,
            description: agent.description || '',
            model: agent.model || 'gpt-4',
            status: agent.status
        }));

    } catch (error) {
        // Loga o erro mas tenta ser resiliente
        logger.error(`Erro GPT [Empresa ${empresaId} / Phone ${phoneId}]:`, error.message);
        throw new HttpsError('internal', `Erro ao buscar agentes: ${error.message}`);
    }
});

exports.listWorkspacesForSetup = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Sem permissão.');

    const { apiToken } = request.data;
    if (!apiToken) throw new HttpsError('invalid-argument', 'Token é obrigatório.');

    try {
        // Chama a API usando o token fornecido na hora (não o global)
        const response = await axios.get(
            `https://api.gptmaker.ai/v2/workspaces`, 
            { 
                headers: { 
                    'Authorization': `Bearer ${apiToken}`,
                    'Content-Type': 'application/json'
                } 
            }
        );

        const list = Array.isArray(response.data) ? response.data : (response.data.data || []);
        
        return list.map(ws => ({
            id: ws.id,
            name: ws.name
        }));

    } catch (error) {
        logger.error("Erro setup GPT:", error.message);
        throw new HttpsError('internal', 'Token inválido ou erro na API.');
    }
});


exports.sendMessage = onRequest({ secrets: [ZAPI_ENC_KEY] }, async (req, res) => {
    // CORS
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");
    if (req.method === "OPTIONS") return res.status(204).send("");

    logger.info("sendMessage function called");

    // Ignora callbacks da Z-API (payloads com "type")
    if (req.body?.type) return res.status(200).send("Callback ignorado");
    if (req.method !== "POST") return res.status(405).send("Method Not Allowed");

    try {
        const { empresaId, phoneId, chatId, message, caption, fileType, fileData, clientMessageId } = req.body;

        const finalCaption = (typeof caption === 'string' ? caption : (typeof message === 'string' ? message : '')).trim();

        const viewOnce = req.body.viewOnce === true;


        const { phoneDocRef, chatDocRef, msgsColRef } = getChatRefs(empresaId, phoneId, chatId);

        // Validacão mínima
        if (!chatId || (!message && !fileData && fileType !== "read")) {
            logger.warn("Parâmetros ausentes", { chatId, hasMessage: !!message, hasFile: !!fileData, fileType });
            return res.status(400).send("Faltam parâmetros");
        }

        // Idempotência (se cliente não mandar, geramos um)
        const uniqueId = clientMessageId || `${chatId}_${Date.now()}`;

        // Credenciais (descriptografa ou cai nas envs)
        const phoneData = (await phoneDocRef.get()).data() || {};
        const instanceId  = decryptIfNeeded(phoneData.instanceId)  || process.env.ZAPI_ID;
        const token       = decryptIfNeeded(phoneData.token)       || process.env.ZAPI_TOKEN;
        const clientToken = decryptIfNeeded(phoneData.clientToken) || process.env.ZAPI_CLIENT_TOKEN;

        if (!instanceId || !token || !clientToken) {
            logger.error("Credenciais Z-API ausentes (verifique doc phones ou variáveis de ambiente)");
            return res.status(500).send("Configuração do backend incorreta");
        }

        logger.info("Credenciais Z-API obtidas", {
            instanceId: instanceId?.slice?.(0, 6) + '…',
            token: '***',
            clientToken: '***'
        });

        // Sempre enviar phone apenas com dígitos
        const phoneDigits = (chatId || '').toString().replace(/\D/g, '');

        // Headers exigidos pela Z-API (use 'client-token' em minúsculas)
        const headers = { 'client-token': clientToken };

        /* ─────────────────────────────
         *  SUPORTE A fileType === "read"
         * ───────────────────────────── */
        if (fileType === "read") {
            const modifyPayload = { phone: phoneDigits, action: "read" };
            logger.info("Marcando chat como lido via Z-API");

            // chama via callZ (fallback de host)
            await callZ(instanceId, token, '/modify-chat', modifyPayload, headers, 15000);

            // zera contador + marca mensagens como lidas no Firestore
            const unreadSnap = await msgsColRef.where("read","==",false).get();
            const batch = admin.firestore().batch();
            unreadSnap.docs.forEach(d => batch.set(d.ref, { read: true }, { merge: true }));
            batch.set(chatDocRef, { unreadCount: 0 }, { merge: true });
            await batch.commit();

            return res.status(200).send({ value: true });
        }

        // Escolhe endpoint + payload conforme fileType (sempre phone: phoneDigits)
        let endpoint = "";
        let payload = {};
        let kind = "text";

        if (fileType === "image") {
            endpoint = "/send-image";
            kind = "image";
            let imageData = fileData || "";
            if (imageData && !/^data:image\//i.test(imageData)) {
                imageData = "data:image/jpeg;base64," + imageData;
            }
            payload = {
                phone: phoneDigits,
                image: imageData,
                caption: finalCaption,     // ✅ Z-API
                viewOnce: viewOnce,        // ✅ opcional
            };

        } else if (fileType === "audio") {
            endpoint = "/send-audio";
            kind = "audio";
            let audioData = fileData || "";
            if (audioData && !/^data:audio\//i.test(audioData)) {
                audioData = "data:audio/mp4;base64," + audioData;
            }
            payload = { phone: phoneDigits, audio: audioData, message: message || "" };

        } else if (fileType === "video") {
            endpoint = "/send-video";
            kind = "video";

            let videoData = fileData || "";
            // ✅ padroniza base64 no formato que a Z-API costuma aceitar melhor
            if (videoData && !/^data:video\//i.test(videoData)) {
                videoData = "data:video/mp4;base64," + videoData;
            }

            payload = {
                phone: phoneDigits,
                video: videoData,
                caption: finalCaption,     // ✅ Z-API
                viewOnce: viewOnce,        // ✅ opcional
            };

        } else if (fileType === "file" || fileType === "document") {
            endpoint = "/send-document";
            kind = "file";

            const fileName = req.body.fileName || "arquivo";
            let docData = fileData || "";

            // data uri genérico (serve pra pdf/docx/xlsx etc)
            if (docData && !/^data:/i.test(docData)) {
                docData = "data:application/octet-stream;base64," + docData;
            }

            payload = { phone: phoneDigits, document: docData, fileName, caption: finalCaption };

        } else {
            endpoint = "/send-text";
            kind = "text";
            payload = { phone: phoneDigits, message: message || "" };
        }

        logger.info("Enviando mensagem via Z-API", { kind, chatId });

        // Envia via callZ (tenta api-v2 depois api)
        const { host: usedHost, resp: zResp } =
            await callZ(instanceId, token, endpoint, payload, headers, 15000);

        const zData = zResp?.data || {};

        // De-dup (se cliente mandou um id)
        if (clientMessageId) {
            const dup = await msgsColRef.where("clientMessageId","==", uniqueId).limit(1).get();
            if (!dup.empty) {
                logger.warn("Mensagem duplicada detectada", { clientMessageId: uniqueId });
                return res.status(200).send(zData);
            }
        }

        // ID da mensagem retornado
        const zMsgId =
            zData.messageId || zData.msgId || zData.id || zData.zaapId || null;

        let contentToStore = (kind === 'text') ? (message || '') : '';
        let mediaMeta = null;

        if (kind !== 'text') {
            // Para vídeo/áudio/documento: SEMPRE Storage
            // Para imagem você pode decidir por tamanho, mas pode padronizar também
            const upload = await uploadBase64ToStorage({
                empresaId,
                phoneId,
                chatId,
                uniqueId,
                kind,
                data: fileType === 'video'
                    ? (payload.video)         // já está "data:video/mp4;base64,..."
                    : fileType === 'audio'
                        ? (payload.audio)
                        : (fileType === 'file' || fileType === 'document')
                            ? (payload.document)
                            : (payload.image),
                fileName: req.body.fileName || null,
                defaultMime:
                    fileType === 'video' ? 'video/mp4' :
                        fileType === 'audio' ? 'audio/mp4' :
                            (fileType === 'file' || fileType === 'document') ? 'application/octet-stream' :
                                'image/jpeg'
            });

            contentToStore = upload.url;

            let thumbUrl = null;
            let thumbMeta = null;

            if (req.body.thumbData) {
                let t = String(req.body.thumbData || '');
                // se vier só base64, prefixa data-uri
                if (t && !/^data:image\//i.test(t)) {
                    const mime = String(req.body.thumbMime || 'image/jpeg');
                    t = `data:${mime};base64,${t}`;
                }

                const thumbUp = await uploadBase64ToStorage({
                    empresaId,
                    phoneId,
                    chatId,
                    uniqueId,
                    kind: 'video_thumb',
                    data: t,
                    fileName: 'thumb.jpg',
                    defaultMime: String(req.body.thumbMime || 'image/jpeg'),
                });

                thumbUrl = thumbUp.url;
                thumbMeta = {
                    thumbUrl: thumbUp.url,
                    thumbMime: thumbUp.contentType,
                    thumbSizeBytes: thumbUp.sizeBytes,
                    thumbStoragePath: thumbUp.path,
                };
            }

            mediaMeta = {
                url: upload.url,
                mime: upload.contentType,
                sizeBytes: upload.sizeBytes,
                fileName: upload.fileName,
                storagePath: upload.path,
                ...(thumbMeta ? thumbMeta : {}),
            };
        }

        // Monta doc Firestore
        const firestoreData = {
            timestamp       : admin.firestore.FieldValue.serverTimestamp(),
            fromMe          : true,
            sender          : zData.sender || null,
            clientMessageId : uniqueId,
            zapiId          : zMsgId,
            status          : 'sent',
            read            : false,
            type            : kind,
            content         : contentToStore, // URL (mídia) ou texto
        };

        if (kind !== 'text') {
            firestoreData.caption = finalCaption;
            firestoreData.media   = mediaMeta;
        }

        await msgsColRef.add(firestoreData);

        await chatDocRef.set({
            chatId,
            lastMessage: kind === 'text'
                ? (message || '')
                : (finalCaption ? finalCaption : (kind === 'video' ? '📹 Vídeo' : kind === 'audio' ? '🎤 Áudio' : '📎 Arquivo')),
            lastMessageTime: admin.firestore.FieldValue.serverTimestamp(),
            type: kind,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        return res.status(200).send(zData);
    } catch (error) {
        const status = error?.status || error?.response?.status || 500;
        const data = error?.data || error?.response?.data;

        logger.error("sendMessage failed", {
            status,
            message: String(error?.message || error),
            code: error?.code || null,
            dataPreview: typeof data === 'string'
                ? data.slice(0, 500)
                : (data ? JSON.stringify(data).slice(0, 500) : null),
        });

        return res.status(status).send(data || String(error));
    }
});

// =============================================================================
// ENVIAR STATUS "DIGITANDO..." (Para uso do Front-end Humano)
// =============================================================================
exports.sendTypingStatus = onRequest(async (req, res) => {
    // CORS
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");
    if (req.method === "OPTIONS") return res.status(204).send("");

    try {
        const { empresaId, phoneId, chatId, status } = req.body; // status: 'composing' ou 'recording'

        if (!empresaId || !phoneId || !chatId) {
            return res.status(400).send("Faltam parâmetros.");
        }

        // Recupera credenciais do banco
        const { phoneDocRef } = getChatRefs(empresaId, phoneId, chatId);
        const phoneData = (await phoneDocRef.get()).data() || {};

        const instanceId = decryptIfNeeded(phoneData.instanceId) || process.env.ZAPI_ID;
        const token = decryptIfNeeded(phoneData.token) || process.env.ZAPI_TOKEN;
        const clientToken = decryptIfNeeded(phoneData.clientToken) || process.env.ZAPI_CLIENT_TOKEN;

        if (!instanceId || !token) {
            return res.status(400).send("Credenciais Z-API não encontradas.");
        }

        const phoneDigits = chatId.replace(/\D/g, ''); // Garante só números
        const presenceType = status === 'recording' ? 'recording' : 'composing';

        // Usa a nossa função auxiliar (que você já tem ou eu passei antes)
        // Se não tiver, chama o axios direto aqui
        const headers = {};
        if (clientToken) headers['client-token'] = clientToken;

        await axios.post(
            `https://api.z-api.io/instances/${instanceId}/token/${token}/send-presence`,
            {
                phone: phoneDigits,
                presence: presenceType
            },
            { headers }
        );

        return res.status(200).send({ success: true });

    } catch (error) {
        logger.warn(`[sendTypingStatus] Erro: ${error.message}`);
        // Retorna 200 para não quebrar o front, já que é um recurso visual opcional
        return res.status(200).send({ success: false, error: error.message });
    }
});



exports.deleteMessage = functions.https.onRequest(async (req, res) => {
    // Configura CORS
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");

    if (req.method === "OPTIONS") {
        return res.status(204).send("");
    }

    functions.logger.info("deleteMessage function called", {
        method: req.method,
        body: req.body,
    });

    if (req.method !== "POST") {
        functions.logger.warn("Método não permitido", {method: req.method});
        return res.status(405).send("Method Not Allowed");
    }

    try {
        // Aqui, basta termos chatId e docId (ID do documento no Firestore)
        const {empresaId, phoneId, chatId, docId} = req.body;

        if (!empresaId || !phoneId || !docId) {
            functions.logger.warn("Parâmetros ausentes", {empresaId, phoneId, docId});
            return res.status(400).send("Faltam parâmetros para deletar a mensagem {empresaId, phoneId, docId}");
        }

        // Remove o documento do Firestore
        const { msgsColRef } = getChatRefs(empresaId, phoneId, chatId);
        await msgsColRef.doc(docId).delete();

        functions.logger.info("Mensagem excluída localmente com sucesso", {empresaId, phoneId, docId});
        return res.status(200).send({success: true});
    } catch (error) {
        functions.logger.error("Erro ao deletar mensagem:", error);
        return res.status(500).send(error.toString());
    }
});

exports.createChat_v2 = onRequest(
    { cors: true, invoker: 'public', secrets: [ZAPI_ENC_KEY] },
    async (req, res) => {

        /* 1) Extrai tudo de uma vez */
        const {
            empresaId,
            phoneId,
            phone: rawPhone           // renomeamos para não conflitar
        } = req.body || {};

        /* 2) Valida presença */
        if (!rawPhone) {
            return res.status(400).json({ error: "Parâmetro phone ausente" });
        }

        /* 3) Sanitiza (só dígitos) */
        const phoneDigits = String(rawPhone).replace(/\D/g, '');
        if (!/^\d{10,15}$/.test(phoneDigits)) {
            return res.status(400).json({ error: "Parâmetro 'phone' inválido" });
        }

        /* 4) Busca credenciais do número da empresa */
        const { phoneDocRef } = getChatRefs(empresaId, phoneId, phoneId);
        const phoneData = (await phoneDocRef.get()).data() || {};
        const ZAPI_ID           = decryptIfNeeded(phoneData.instanceId)  || process.env.ZAPI_ID;
        const ZAPI_TOKEN        = decryptIfNeeded(phoneData.token)       || process.env.ZAPI_TOKEN;
        const ZAPI_CLIENT_TOKEN = decryptIfNeeded(phoneData.clientToken) || process.env.ZAPI_CLIENT_TOKEN;

        if (!ZAPI_ID || !ZAPI_TOKEN || !ZAPI_CLIENT_TOKEN) {
            return res.status(500).json({ status:'error', message:'Credenciais Z-API ausentes' });
        }

        try {
            // ✅ 0) resolve o chatId correto (reaproveita chat existente com/sem 9)
            const resolvedChatId = await resolveChatIdForNumber({
                empresaId,
                phoneId,
                phoneDigits, // número digitado (pode vir com 9 extra)
            });

            // dígitos canônicos que vamos usar na Z-API (sem @ e sem variações)
            const canonicalDigits = String(resolvedChatId)
                .replace('@s.whatsapp.net', '')
                .replace(/\D/g, '');

            // ✅ 1) se já existe chat no Firestore, NÃO cria outro — só devolve ele pro app abrir histórico
            const { chatDocRef } = getChatRefs(empresaId, phoneId, resolvedChatId);
            const existingSnap = await chatDocRef.get();

            if (existingSnap.exists) {
                const existing = existingSnap.data() || {};
                return res.status(200).json({
                    status: 'success',
                    existing: true,
                    phoneDigits: canonicalDigits,
                    contactName: existing.name || existing.chatName || canonicalDigits,
                    contactPhoto: existing.contactPhoto || '',
                    chatId: resolvedChatId, // ✅ o doc que já existe
                });
            }

            // daqui pra baixo: chat não existe ainda → pode chamar Z-API pra buscar nome/foto
            const baseUrl = 'https://api.z-api.io/instances';
            const headers = {
                'Content-Type': 'application/json',
                'Client-Token': ZAPI_CLIENT_TOKEN,
            };

            // 2) cria o chat na Z-API (use o canonicalDigits)
            const createUrl = `${baseUrl}/${encodeURIComponent(ZAPI_ID)}/token/${encodeURIComponent(ZAPI_TOKEN)}/createChat`;
            const zRes = await axios.post(createUrl, { phone: canonicalDigits }, { headers });
            logger.info('Status Z-API /createChat:', zRes.status, zRes.data);

            const zData = zRes.data || {};

            // 3) tenta buscar foto do contato (use canonicalDigits)
            let contactPhoto = '';
            try {
                const photoUrl = `${baseUrl}/${encodeURIComponent(ZAPI_ID)}/token/${encodeURIComponent(ZAPI_TOKEN)}/contacts/profile-picture/${canonicalDigits}`;
                const photoRes = await axios.get(photoUrl, { headers, timeout: 15000 });

                contactPhoto = String(
                    photoRes?.data?.profilePic ??
                    photoRes?.data?.profilePicture ??
                    photoRes?.data?.profile_picture ??
                    ''
                ).trim();
            } catch (errPhoto) {
                logger.warn('createChat_v2: falha ao buscar foto do contato', {
                    status: errPhoto?.response?.status,
                    data: errPhoto?.response?.data || errPhoto?.message,
                });
            }

            // 4) nome (fallback)
            let contactName = canonicalDigits;
            const rawName =
                zData.contactName ||
                zData.pushname    ||
                zData.chatName    ||
                zData.name        ||
                null;

            if (rawName && typeof rawName === 'string' && rawName.trim()) {
                contactName = rawName.trim();
            }

            // ✅ 5) chatId FINAL deve ser o resolvedChatId (não o phoneDigits digitado)
            return res.status(200).json({
                status: 'success',
                existing: false,
                data: zData,
                phoneDigits: canonicalDigits,
                contactName,
                contactPhoto,
                chatId: resolvedChatId,
            });
        } catch (err) {
            logger.error('Z-API erro em createChat_v2', err.response?.status, err.response?.data);
            return res.status(err.response?.status || 500).json({
                status: 'error',
                message: err.response?.data || err.message,
            });
        }
    }
);

exports.whatsappWebhook = onRequest(
    {secrets: ['WHATSAPP_VERIFY_TOKEN']},
    async (req, res) => {

        const VERIFY_TOKEN = process.env.WHATSAPP_VERIFY_TOKEN;
        if (req.method === 'GET') {
            const mode = req.query['hub.mode'];
            const token = req.query['hub.verify_token'];
            const chall = req.query['hub.challenge'];

            if (mode === 'subscribe' && token === VERIFY_TOKEN) {
                return res.status(200).send(chall);  // ✓ Verified
            }
            return res.sendStatus(403);             // ✗ Wrong token
        }

        // 2) Notificações (POST)
        if (req.method === 'POST') {
            try {
                const change = req.body.entry?.[0].changes?.[0].value;
                const msg = change?.messages?.[0];

                if (msg?.referral) {
                    const conv = change.conversation;
                    await admin.firestore().collection('conversations').add({
                        waConversationId: conv.id,
                        adId: msg.referral.source_id,
                        adUrl: msg.referral.source_url,
                        originType: conv.origin.type,      // referral_conversion
                        firstMessage: msg.text?.body ?? ''
                    });
                }
                return res.sendStatus(200);
            } catch (err) {
                console.error('Webhook error', err);
                return res.sendStatus(500);
            }
        }

        res.sendStatus(405); // Método não permitido
    });

exports.enableReadReceipts = onRequest(
  {
    region: "us-central1",
    cpu: 0.25,
    memory: "256MiB",
    maxInstances: 1,
    minInstances: 0,
    timeoutSeconds: 60
  },
  async (req, res) => {
    // CORS pre-flight
    if (req.method === "OPTIONS") {
      return res.status(204).send("");
    }

    const { ZAPI_ID, ZAPI_TOKEN, ZAPI_CLIENT_TOKEN } = process.env;

    if (!ZAPI_ID || !ZAPI_TOKEN || !ZAPI_CLIENT_TOKEN) {
      return res.status(500).send("Variáveis de ambiente faltando");
    }

    try {
      const url =
        `https://api.z-api.io/instances/${ZAPI_ID}/token/${ZAPI_TOKEN}` +
        `/privacy/read-receipts?value=enable`;

      const r = await axios.post(
        url,
        {},
        { headers: { "Client-Token": ZAPI_CLIENT_TOKEN } }
      );

      return res.status(200).json(r.data);
    } catch (err) {
      console.error(
        "Z-API read-receipts error",
        err.response?.data || err
      );
      return res
        .status(err.response?.status || 500)
        .send(err.toString());
    }
  }
);


/* util: carrega credenciais salvas em /phones/{phoneId} */
/* SUBSTITUA este helper */
async function getCred(empresaId, phoneId){
    const snap = await db.doc(`empresas/${empresaId}/phones/${phoneId}`).get();
    if (!snap.exists) throw new Error('phone not found');
    const d = snap.data() || {};
    return {
        instanceId : (d.instanceId),
        token      : (d.token),
        clientToken: (d.clientToken),
    };
}

/* ========== 1. QR-Code (base64) ========== */
exports.getQr = onRequest({ secrets: [ZAPI_ENC_KEY] }, async (req,res)=>{
    try{
        const {empresaId, phoneId} = req.query;
        const {instanceId, token, clientToken} = await getCred(empresaId,phoneId);

        const url = `https://api.z-api.io/instances/${instanceId}/token/${token}/qr-code/image`;
        const z = await axios.get(url,{
            headers:{'Client-Token':clientToken}
        });
        res.json({image:z.data});
    }catch(e){ console.error(e); res.status(500).json({error:e.message});}
});

/* ========== 2. Código por telefone ========== */
exports.getPhoneCode = onRequest({ secrets: [ZAPI_ENC_KEY] }, async (req,res)=>{
    try{
        const {empresaId, phoneId, phone} = req.body;
        const {instanceId, token, clientToken} = await getCred(empresaId,phoneId);

        const url=`https://api.z-api.io/instances/${instanceId}/token/${token}/phone-code/${phone}`;
        const z = await axios.get(url,{ headers:{'Client-Token':clientToken} });

        res.json({code:z.data.code});
    }catch(e){ console.error(e); res.status(500).json({error:e.message});}
});

/* ========== 3. Status de conexão ========== */
exports.getConnectionStatus = onRequest({ secrets: [ZAPI_ENC_KEY] }, async (req,res)=>{
    try{
        const {empresaId, phoneId} = req.query;
        const {instanceId, token, clientToken} = await getCred(empresaId,phoneId);

        const url=`https://api.z-api.io/instances/${instanceId}/token/${token}/me`;
        const z = await axios.get(url,{ headers:{'Client-Token':clientToken} });

        // quando conectar pela primeira vez gravamos em Firestore
        if(z.data.connected){
            await db.doc(`empresas/${empresaId}/phones/${phoneId}`)
                .set({connected:true, connectedAt: admin.firestore.FieldValue.serverTimestamp()},
                    {merge:true});
        }
        res.json({connected:z.data.connected});
    }catch(e){ console.error(e); res.status(500).json({error:e.message});}
});

const MAX_PHOTO_AGE_HOURS = 4;                      // ↺ a cada 4 h
const MAX_PHOTO_AGE_MS    = MAX_PHOTO_AGE_HOURS * 3600 * 1_000;

exports.updateContactPhotos = onRequest({ secrets: [ZAPI_ENC_KEY] }, async (req, res) => {
    /* ──────────────────────────── 1. CORS ───────────────────────────── */
    res.set('Access-Control-Allow-Origin',  '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type');
    if (req.method === 'OPTIONS') return res.status(204).send('');

    /* ──────────────────────────── 2. Entrada ─────────────────────────── */
    const { empresaId, phoneId } = req.body || {};
    if (!empresaId || !phoneId) {
        return res.status(400).json({ error: 'empresaId e phoneId são obrigatórios' });
    }

    try {
        /* ────────── 3. Credenciais do número ────────── */
        const phoneSnap = await db.doc(`empresas/${empresaId}/phones/${phoneId}`).get();
        if (!phoneSnap.exists) throw new Error('Documento do phone não encontrado');

        const { instanceId, token, clientToken } = phoneSnap.data() || {};

        // Se no seu Firestore estiver em plaintext, decryptIfNeeded devolve como está.
        const plain = {
            instanceId: decryptIfNeeded(instanceId, 'instanceId'),
            token: decryptIfNeeded(token, 'token'),
            clientToken: decryptIfNeeded(clientToken, 'clientToken'),
        };

        if (!plain.instanceId || !plain.token || !plain.clientToken) {
            throw new Error('Credenciais Z-API ausentes no documento phone');
        }

        /* ────────── 4. Todos os chats do número ─────── */
        const chatsSnap = await db
            .collection(`empresas/${empresaId}/phones/${phoneId}/whatsappChats`)
            .get();

        const enc = encodeURIComponent;
        const toUpdate = [];

        for (const chatDoc of chatsSnap.docs) {
            const chatData = chatDoc.data() || {};
            const phoneDigits = String(chatDoc.id || '').replace(/\D/g, ''); // 55...

            if (!phoneDigits) continue;

            /* ---- 4.1 checa “idade” do avatar ---- */
            const lastMillis = chatData.photoUpdatedAt?.toMillis?.() || 0;
            if (Date.now() - lastMillis < MAX_PHOTO_AGE_MS) continue; // ainda fresco

            /* ---- 4.2 consulta Z-API (com fallback de host) ---- */
            let newPhoto = '';
            let gotAnswer = false;

            for (const host of ZAPI_HOSTS) {
                const zUrl = `${host}/instances/${enc(plain.instanceId)}/token/${enc(plain.token)}/contacts/profile-picture/${phoneDigits}`;

                try {
                    const zRes = await axios.get(zUrl, {
                        headers: { 'Client-Token': plain.clientToken },
                        timeout: 15000,
                    });

                    newPhoto = String(
                        zRes?.data?.profilePic ??
                        zRes?.data?.profilePicture ??
                        zRes?.data?.profile_picture ??
                        ''
                    ).trim();

                    gotAnswer = true;
                    break;
                } catch (zErr) {
                    // 404 = contato sem foto (ou sem permissão/sem imagem). NÃO apague a foto já salva.
                    if (zErr?.response?.status === 404) {
                        gotAnswer = true;
                        newPhoto = '';
                        break;
                    }
                    continue; // tenta próximo host
                }
            }

            if (!gotAnswer) {
                console.error(`updateContactPhotos · falhou em todos hosts p/ nº ${phoneDigits}`);
                continue;
            }

            /* ---- 4.3 persistência (NÃO deletar contactPhoto quando vier vazio) ---- */
            const payload = {
                photoUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };

            // Só atualiza o campo se veio foto nova (evita “sumir” quando a Z-API responde vazio)
            if (newPhoto) payload.contactPhoto = newPhoto;

            toUpdate.push(chatDoc.ref.set(payload, { merge: true }));
        }

        await Promise.all(toUpdate);
        return res.json({ updated: toUpdate.length });
    } catch (err) {
        console.error('updateContactPhotos', err);
        return res.status(500).json({ error: err.message });
    }
});

//FIM FUNCTIONS Z-API / WHATSAPP

//FUNCTION PARA ATUALIZAR TEMPO DE ATENDIMENTO

exports.onChatStatusChange = onDocumentUpdated(
    'empresas/{empresaId}/phones/{phoneId}/whatsappChats/{chatId}',
    async (event) => {
        const before = event.data.before.data();
        const after  = event.data.after.data();
        if (!before || !after) return;
        if (before.status === after.status) return;         // status não mudou

        const chatRef = event.data.after.ref;
        const now     = admin.firestore.Timestamp.now();
        const updates = {};                 // vamos popular abaixo

        /* ---------- grava historico --------- */
        await chatRef.collection('history').add({
            status   : after.status,
            changedAt: now,
            updatedBy: after.updatedBy ?? 'system',
        });

        /* ---------- Novo  →  Atendendo ------- */
        if (before.status === 'novo' && after.status === 'atendendo') {
            updates.attendingAt  = now;
            updates.waitTimeSec  = Math.max(
                1,
                now.seconds - (before.arrivalAt?.seconds || now.seconds)
            );
        }

        /* ---------- Atendendo  →  Final ------ */
        const finals = ['concluido_com_venda', 'recusado'];
        if (finals.includes(after.status)) {
            updates.concludedAt       = now;
            updates.attendingTimeSec  = Math.max(
                1,
                now.seconds - (after.attendingAt?.seconds || now.seconds)
            );
            updates.totalTimeSec = Math.max(
                1,
                now.seconds - (before.arrivalAt?.seconds || now.seconds)
            );
        }

        if (Object.keys(updates).length) await chatRef.set(updates, {merge:true});
    }
);

exports.backfillInstanceIdHash = onRequest({ secrets: [ZAPI_ENC_KEY] }, async (req, res) => {
    try {
        const batchSize = 300;
        const snap = await db.collectionGroup('phones').get();
        let batch = db.batch();
        let count = 0, wrote = 0;

        for (const doc of snap.docs) {
            count++;
            const d = doc.data() || {};
            const plain = decryptIfNeeded(d.instanceId);
            const hash  = plain ? hashInstanceId(plain) : null;

            // só escreve se estiver faltando ou estiver errado
            if ((hash && d.instanceIdHash !== hash) || (hash === null && d.instanceIdHash !== null)) {
                batch.set(doc.ref, { instanceIdHash: hash }, { merge: true });
                wrote++;
            }

            if (wrote && wrote % batchSize === 0) {
                await batch.commit();
                batch = db.batch();
            }
        }

        if (wrote % batchSize !== 0) await batch.commit();

        res.json({ scanned: count, updated: wrote });
    } catch (e) {
        console.error('backfillInstanceIdHash', e);
        res.status(500).json({ error: e.message });
    }
});

// FUNCTIONS CHATBOTS

const BOT = {
    sessionDoc: (chatDocRef) => chatDocRef.collection('bot').doc('session'),
    queueCol:   (chatDocRef) => chatDocRef.collection('botQueue'),
    // quantidade máxima de tarefas processadas por tick
    TICK_LIMIT: 40,
};

// ----------------------------------------------------------------
// ENVIO VIA Z-API (ajuste se já existir um sender na sua base)
async function sendTextWithZapi({ phoneDoc, chatId, text }) {
    const phonePath = phoneDoc?.ref?.path || '(unknown)';
    const { instanceId, token, clientToken, apiUrl, where } =
        readZapiCredsFromPhoneDoc(phoneDoc);

    logger.info('[ZAPI:cfg-check]', {
        phonePath,
        where,                      // 'chatbot' | 'root' | 'none'
        hasInstanceId: !!instanceId,
        hasToken: !!token,
        hasClientToken: !!clientToken,
        apiBase: apiUrl
    });

    if (!instanceId || !token) {
        throw new Error('Z-API: credenciais ausentes (instanceId/token) nem no root nem em .chatbot');
    }

    const digits = String(chatId || '')
        .replace('@s.whatsapp.net', '')
        .replace(/\D/g, '');

    const url = `${apiUrl}/instances/${instanceId}/token/${token}/send-text`;
    const headers = {};
    if (clientToken) headers['client-token'] = clientToken;  // <— essencial!

    logger.info('[ZAPI:send-text]', { to: digits, preview: String(text || '').slice(0, 80) });
    await axios.post(url, { phone: digits, message: text }, { headers });
}

// ----------------------------------------------------------------
// UTILITÁRIOS
// ----------------------------------------------------------------
const nowTs = () => admin.firestore.Timestamp.now();
const inMs = (ms) => admin.firestore.Timestamp.fromMillis(Date.now() + Math.max(0, ms));
const minutesToMs = (m) => (Math.max(0, Number(m||0)) * 60 * 1000) | 0;

function normalizeDigits(s) { return String(s || '').replace(/\D/g, ''); }

function formatMenu(step, vars) {
    const base = renderTemplate(step.text || 'Escolha uma opção:', vars);
    const lines = (step.options || []).map(o => {
        const label = renderTemplate(o.label || '', vars);
        return `*${o.key}* - ${label}`;
    });
    return [base, ...lines].join('\n');
}

function findStep(steps, id) {
    return steps.find(s => s.id === id) || { id: 'end', type: 'end' };
}

function resolveActiveChatbotId({ phoneDoc, chatDocData }) {
    const d = (phoneDoc?.data() || {});
    const m = d.chatbot || {};

    const enabled = (m.enabled === true) || (d.enabled === true);
    const botId   = m.botId || d.botId || d.chatbotId; // tolera root/chat

    if (enabled && botId) return botId;
    if (chatDocData?.chatbotId) return chatDocData.chatbotId;
    return null;
}

// ----------------------------------------------------------------
// ENFILEIRAMENTO (novo)
// ----------------------------------------------------------------
async function enqueue({ empresaId, phoneId, chatId, stepId, type, runAt, reason, inline = false }) {
    const { chatDocRef } = getChatRefs(empresaId, phoneId, chatId);
    const q = chatDocRef.collection('botQueue');
    const docRef = q.doc();

    const payload = {
        type,
        stepId,
        status: 'pending',
        runAt: runAt || nowTs(),
        reason: reason || null,
        createdAt: nowTs(),
        attempts: 0,
    };

    await docRef.set(payload);
    logger.info('[BOT] enqueued', {
        chatPath: chatDocRef.path, type, stepId, reason,
        runAt: (payload.runAt.toDate ? payload.runAt.toDate() : new Date())
    });

    // Processamento inline é OPCIONAL. Recomendado manter false
    // quando você tem o gatilho onDocumentCreated habilitado.
    if (inline) {
        try {
            await processQueueDoc(docRef);
        } catch (e) {
            logger.error('[BOT] inline process failed (fallback ficará a cargo do trigger/cron)', e);
        }
    }

    return docRef.id;
}

async function cancelTimeoutTasksForStep({ empresaId, phoneId, chatId, stepId }) {
    const { chatDocRef } = getChatRefs(empresaId, phoneId, chatId);
    const snap = await BOT.queueCol(chatDocRef)
        .where('type', '==', 'timeout_step')
        .where('stepId', '==', stepId)
        .where('status', '==', 'pending')
        .get();

    const batch = admin.firestore().batch();
    snap.docs.forEach(d => batch.update(d.ref, { status: 'canceled', canceledAt: nowTs() }));
    if (!snap.empty) await batch.commit();
}

// ----------------------------------------------------------------
// SESSÃO
// ----------------------------------------------------------------
async function loadOrInitSession({ empresaId, phoneId, chatId, chatbotDoc }) {
    const { chatDocRef } = getChatRefs(empresaId, phoneId, chatId);
    const sessRef = BOT.sessionDoc(chatDocRef);
    let sessSnap = await sessRef.get();

    if (!sessSnap.exists) {
        const base = {
            chatbotId: chatbotDoc.id,
            currentStepId: null,
            awaitingReply: false,
            waitUntil: null,
            retries: 0,
            status: 'idle', // idle | running | ended | handoff
            vars: {},       // <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
            createdAt: nowTs(),
            updatedAt: nowTs(),
        };
        await sessRef.set(base);
        sessSnap = await sessRef.get();
    } else {
        // garante vars
        const cur = sessSnap.data() || {};
        if (!cur.vars || typeof cur.vars !== 'object') {
            await sessRef.set({ vars: {} }, { merge: true });
            sessSnap = await sessRef.get();
        }
    }
    return { sessRef, session: sessSnap.data() };
}

// ----------------------------------------------------------------
// EXECUÇÃO DE UM PASSO (envio e agendamentos) — com variáveis e handoff
// ----------------------------------------------------------------
async function executeSendStepTask({ empresaId, phoneId, chatId, phoneDoc, chatbot, step, defaultSpacingMs }) {
    logger.info('[BOT] send-step', { stepId: step.id, type: step.type, next: step.next });

    const { chatDocRef } = getChatRefs(empresaId, phoneId, chatId);
    const sessRef = BOT.sessionDoc(chatDocRef);

    // carrega sessão p/ templates e estado
    const sessSnap = await sessRef.get();
    const session = (sessSnap.exists ? sessSnap.data() : {}) || {};
    const vars = session.vars || {};

    await applyStepActionsToChat({ empresaId, phoneId, chatId, step });

    // ---------- DEDUPE (anti envio duplicado por 20s) ----------
    // Agora o preview usa o CONTEÚDO RENDERIZADO, para deduplicar corretamente.
    const renderedMessage = step.type === 'message' ? renderTemplate(step.text || '', vars) : '';
    const renderedMenu = step.type === 'menu' ? formatMenu(step, vars) : '';
    const preview =
        step.type === 'menu'     ? renderedMenu :
            step.type === 'capture'  ? (step.ask || '') :
                step.type === 'message'  ? renderedMessage :
                    ''; // 'end' e 'handoff' não têm preview textual

    const GUARD_WINDOW_MS = 20_000; // 20s
    if (preview) {
        const hashPart = Buffer.from(String(preview)).toString('base64').slice(0, 64);
        const dedupeKey = `send:${step.id}:${hashPart}`;
        const guardRef = chatDocRef.collection('botSendGuards').doc(dedupeKey);
        const guardSnap = await guardRef.get();
        const now = Date.now();
        const createdAtMs = guardSnap.exists
            ? (guardSnap.data()?.createdAt?.toMillis?.() || 0)
            : 0;

        if (guardSnap.exists && (now - createdAtMs) < GUARD_WINDOW_MS) {
            logger.warn('[BOT] dedupe-hit — pulando envio duplicado', { stepId: step.id });
        } else {
            await guardRef.set({ createdAt: nowTs(), stepId: step.id });

            // 1) enviar mensagem conforme tipo (RENDERIZADO)
            if (step.type === 'message') {
                if (renderedMessage) {
                    const r = await sendTextWithZapi({ phoneDoc, chatId, text: renderedMessage });
                    await persistBotTextMessage({ empresaId, phoneId, chatId, text: renderedMessage, zapiId: r?.zapiId });
                }
            } else if (step.type === 'capture') {
                const ask = step.ask || '';
                if (ask) {
                    const r = await sendTextWithZapi({ phoneDoc, chatId, text: ask });
                    await persistBotTextMessage({ empresaId, phoneId, chatId, text: ask, zapiId: r?.zapiId });
                }
            } else if (step.type === 'menu') {
                const r = await sendTextWithZapi({ phoneDoc, chatId, text: renderedMenu });
                await persistBotTextMessage({ empresaId, phoneId, chatId, text: renderedMenu, zapiId: r?.zapiId });
            }
        }
    }

    // Tipos sem envio direto, mas com efeito na sessão:
    if (step.type === 'end') {
        await persistSystemEventMessage({
            empresaId, phoneId, chatId,
            event: 'bot_end',
            label: 'Atendimento encerrado automaticamente',
            extra: { stepId: step.id }
        });
        await sessRef.set({ status: 'ended', awaitingReply: false, currentStepId: step.id, updatedAt: nowTs() }, { merge: true });
        return;
    }

    if (step.type === 'handoff') {
        // Marca estado e PARA a automação. A mensagem de "aguarde" já foi enviada
        // pelo passo 'message' anterior (ex.: ${id}_msg), se existir.
        await sessRef.set({
            status: 'handoff',
            awaitingReply: false,
            currentStepId: step.id,
            updatedAt: nowTs(),
        }, { merge: true });


        await persistSystemEventMessage({
            empresaId, phoneId, chatId,
            event: 'handoff',
            label: 'Atendimento transferido para um atendente',
            extra: { stepId: step.id }
        });

        // se quiser, pode notificar operador aqui
        // e opcionalmente avançar para step.next se existir
        if (step.next && step.next !== 'end') {
            await enqueue({
                empresaId, phoneId, chatId,
                stepId: step.next,
                type: 'send_step',
                runAt: nowTs(),                // << instantâneo
                reason: 'post-handoff-next',
                inline: false,
            });
        }
        return;
    }

    // 2) decidir: aguarda resposta ou segue em frente
    const meta = step.meta || {};
    const waitMin = Number(meta.timeoutMinutes || 0);
    const wantsCapture = (step.type === 'message' && step.var) || (step.type === 'capture'); // message com var capta

    if (step.type === 'message' && !wantsCapture) {
        // Mensagem "simples": se não tem timeout → segue automático
        if (!waitMin || waitMin <= 0) {
            if (step.next && step.next !== 'end') {
                await enqueue({
                    empresaId, phoneId, chatId,
                    stepId: step.next,
                    type: 'send_step',
                    runAt: nowTs(),                // << instantâneo
                    reason: 'auto-next',
                    inline: false,
                });
            } else {
                await sessRef.set({ status: 'ended', awaitingReply: false, currentStepId: step.id, updatedAt: nowTs() }, { merge: true });
            }
            return;
        }
    }

    // Se chegou aqui, ou o step é menu/capture, ou é message com var, ou message com timeout
    const waitUntil = waitMin ? inMs(minutesToMs(waitMin)) : null;
    await sessRef.set({
        currentStepId: step.id,
        awaitingReply: true,
        waitUntil,
        status: 'running',
        updatedAt: nowTs(),
    }, { merge: true });

    if (waitMin && meta.timeoutNext) {
        await enqueue({
            empresaId, phoneId, chatId,
            stepId: step.id,
            type: 'timeout_step',
            runAt: waitUntil,
            reason: 'awaiting-timeout',
            inline: false,
        });
    }
}

// ----------------------------------------------------------------
// DECISÃO POR RESPOSTA (onReply / menu / capture)
// ----------------------------------------------------------------
function decodeDigits(s) { return String(s || '').trim().toLowerCase().replace(/\s+/g, ' ').replace(/[^\d\-a-zá-ú ]/gi, ''); }

function resolveMenuNext(step, userText) {
    const d = String(userText || '').replace(/\D/g, '');
    const exact = (step.options || []).find(o => String(o.key) === d);
    return exact?.next || null;
}

async function handleReply({
                               empresaId, phoneId, chatId, phoneDoc,
                               chatbot, session, userText, defaultSpacingMs
                           }) {
    const step = findStep(chatbot.steps, session.currentStepId);
    const { chatDocRef } = getChatRefs(empresaId, phoneId, chatId);
    const sessRef = BOT.sessionDoc(chatDocRef);

    // carrega snapshot fresco (vamos gravar vars)
    const sessSnap = await sessRef.get();
    const cur = (sessSnap.exists ? sessSnap.data() : {}) || {};
    const vars = cur.vars && typeof cur.vars === 'object' ? cur.vars : {};

    let nextId = null;

    if (step.type === 'menu') {
        const chosenDigits = String(userText || '').replace(/\D/g, '');
        nextId = resolveMenuNext(step, userText);

        if (!nextId) {
            // Fallback de menu
            const fb = chatbot.fallback || { message: 'Não entendi. Responda com um número.', maxRetries: 2, onFail: 'handoff' };
            const retries = (session.retries || 0) + 1;

            if (retries > (fb.maxRetries || 2)) {
                await sendTextWithZapi({ phoneDoc, chatId, text: fb.message || 'Encaminhando para atendimento…' });
                await sessRef.set({
                    awaitingReply: false,
                    currentStepId: step.id,
                    status: fb.onFail === 'handoff' ? 'handoff' : 'ended',
                    retries: 0,
                    updatedAt: nowTs(),
                }, { merge: true });

                await persistSystemEventMessage({
                    empresaId, phoneId, chatId,
                    event: fb.onFail === 'handoff' ? 'handoff' : 'bot_end',
                    label: fb.onFail === 'handoff'
                        ? 'Atendimento transferido para um atendente'
                        : 'Atendimento encerrado automaticamente',
                    extra: { stepId: step.id, reason: 'menu-fallback-max-retries' },
                });

                return;
            }

            const fbText = fb.message || 'Não entendi. Responda com um número.';
            const r = await sendTextWithZapi({ phoneDoc, chatId, text: fbText });
            await persistBotTextMessage({ empresaId, phoneId, chatId, text: fbText, zapiId: r?.zapiId });
            await sessRef.set({
                retries,
                awaitingReply: true,
                currentStepId: step.id,
                updatedAt: nowTs(),
            }, { merge: true });
            return;
        }

        // Se o menu define var, gravamos a tecla escolhida
        if (step.var) {
            vars[step.var] = chosenDigits;
            await sessRef.set({ vars, updatedAt: nowTs() }, { merge: true });
        }

    } else {
        // message/capture: qualquer texto conta como "reply" → next
        // Se message tinha var, captura a resposta do usuário
        if (step.type === 'message' && step.var) {
            vars[step.var] = String(userText || '').trim();
            await sessRef.set({ vars, updatedAt: nowTs() }, { merge: true });
        }
        // capture tradicional (se ainda existir em fluxos antigos)
        if (step.type === 'capture' && step.var) {
            vars[step.var] = String(userText || '').trim();
            await sessRef.set({ vars, updatedAt: nowTs() }, { merge: true });
        }

        nextId = step.next || null;
    }

    await cancelTimeoutTasksForStep({ empresaId, phoneId, chatId, stepId: step.id });
    logger.info('[BOT] reply-routing', { from: step.id, type: step.type, userText, nextId });

    // Escolher próximo
    if (nextId && nextId !== 'end') {
        await sessRef.set({
            currentStepId: nextId,
            awaitingReply: false,
            retries: 0,
            updatedAt: nowTs(),
        }, { merge: true });

        if (nextId === step.id) {
            logger.warn('[BOT] nextId equals current stepId — loop avoided', { stepId: step.id });
            await sessRef.set({ status: 'ended', awaitingReply: false, updatedAt: nowTs() }, { merge: true });
            return;
        }

        await enqueue({
            empresaId, phoneId, chatId,
            stepId: nextId,
            type: 'send_step',
            runAt: nowTs(),                // << instantâneo
            reason: 'on-reply-next',
        });
    } else {
        const endStep = findStep(chatbot.steps, nextId || 'end');
        await applyStepActionsToChat({ empresaId, phoneId, chatId, step: endStep });

        await sessRef.set({
            status: 'ended',
            currentStepId: step.id,
            awaitingReply: false,
            updatedAt: nowTs(),
        }, { merge: true });
    }
}

// ----------------------------------------------------------------
// TIMEOUT (onTimeout)
// ----------------------------------------------------------------
async function handleTimeout({
                                 empresaId, phoneId, chatId, phoneDoc, chatbot, task, defaultSpacingMs
                             }) {
    const { chatDocRef } = getChatRefs(empresaId, phoneId, chatId);
    const sessSnap = await BOT.sessionDoc(chatDocRef).get();
    const session = (sessSnap.exists ? sessSnap.data() : {}) || {};

    // Só processa se ainda estamos esperando resposta desse MESMO step
    if (!session.awaitingReply || session.currentStepId !== task.stepId) return;

    const step = findStep(chatbot.steps, task.stepId);
    const to = (step.meta || {}).timeoutNext || null;

    await BOT.sessionDoc(chatDocRef).set({
        awaitingReply: false,
        updatedAt: nowTs()
    }, { merge: true });

    if (to && to !== 'end') {
        await enqueue({
            empresaId, phoneId, chatId,
            stepId: to,
            type: 'send_step',
            runAt: nowTs(),                // << instantâneo (o atraso já foi o timeout)
            reason: 'on-timeout-next',
        });
    } else {
        const endStep = findStep(chatbot.steps, to || 'end');
        await applyStepActionsToChat({ empresaId, phoneId, chatId, step: endStep });
        await BOT.sessionDoc(chatDocRef).set({ status: 'ended', currentStepId: step.id, updatedAt: nowTs() }, { merge: true });
        await BOT.sessionDoc(chatDocRef).set({
            status: 'ended',
            currentStepId: step.id,
            updatedAt: nowTs()
        }, { merge: true });
    }
}

// ----------------------------------------------------------------
// PROCESSAMENTO DE UMA TAREFA DA FILA (novo, com lock)
// ----------------------------------------------------------------
async function processQueueDoc(refOrSnap) {
    // normaliza para DocumentReference
    const ref = refOrSnap?.ref ? refOrSnap.ref : refOrSnap;
    if (!ref) { logger.error('[BOT] processQueueDoc: ref vazio'); return; }

    // Apenas log informativo; a decisão acontece dentro do lock
    logger.info('[BOT] processing-check', { id: ref.id });

    // ---- LOCK via transaction: só UM executor troca para "processing"
    let acquired = false;
    await admin.firestore().runTransaction(async (tx) => {
        const fresh = await tx.get(ref);
        if (!fresh.exists) return;

        const cur = fresh.data();
        // tolera até 5s no futuro para o onCreate pegar imediatamente
        const runAtMs = cur.runAt.toMillis();
        const earlySlackMs = 5000; // 5s
        const isSend = cur.type === 'send_step';
        const canStart = runAtMs <= Date.now() || (isSend && (runAtMs - Date.now()) <= earlySlackMs);
        if (cur.status !== 'pending' || !canStart) return;

        tx.update(ref, {
            status: 'processing',
            startedAt: nowTs(),
            attempts: (cur.attempts || 0) + 1,
        });
        acquired = true;
    });

    if (!acquired) {
        logger.info('[BOT] skip — já processado, ainda pendente futuro, ou outro worker adquiriu', { id: ref.id });
        return;
    }

    // Agora este worker é o DONO do task
    try {
        // caminho: empresas/{empresaId}/phones/{phoneId}/whatsappChats/{chatId}/botQueue/{taskId}
        const path = ref.path.split('/');
        const empresaId = path[1];
        const phoneId   = path[3];
        const chatId    = path[5];

        let phoneDoc;
        try {
            const ctx = await getPhoneCtxByNumber(phoneId);
            phoneDoc  = ctx.phoneDoc;
        } catch (e) {
            logger.error('processQueueDoc:getPhoneCtxByNumber', e);
            // rebaixa para pending dali a pouco para tentar de novo
            await ref.update({ status: 'pending', error: String(e?.message || e), runAt: inMs(2000) });
            return;
        }

        const snap = await ref.get(); // re-lê após lock para obter o payload atual
        const data = snap.data() || {};
        logger.info('[BOT] processing-task', { id: ref.id, type: data.type, stepId: data.stepId });

        const { chatDocRef } = getChatRefs(empresaId, phoneId, chatId);

        // carregar chatbotId (chat → phone.chatbot.botId ou chat.chatbotId)
        const chatSnap  = await chatDocRef.get();
        const chatData  = chatSnap.data() || {};
        const chatbotId = chatData.chatbotId
            || (phoneDoc.data()?.chatbot?.enabled ? phoneDoc.data().chatbot.botId : null);

        if (!chatbotId) throw new Error('Nenhum chatbot ativo: defina phones/{phoneId}.chatbot.enabled=true e .botId');

        const botSnap = await admin.firestore()
            .collection('empresas').doc(empresaId)
            .collection('chatbots').doc(chatbotId).get();
        if (!botSnap.exists) throw new Error('Chatbot não encontrado');

        const chatbot          = botSnap.data();
        const defaultSpacingMs = Number(chatbot.defaultSpacingMs || 1200);
        const step             = findStep(chatbot.steps || [], data.stepId);

        if (data.type === 'send_step') {
            await executeSendStepTask({ empresaId, phoneId, chatId, phoneDoc, chatbot, step, defaultSpacingMs });
        } else if (data.type === 'timeout_step') {
            await handleTimeout({ empresaId, phoneId, chatId, phoneDoc, chatbot, task: data, defaultSpacingMs });
        }

        await ref.update({ status: 'done', finishedAt: nowTs(), error: admin.firestore.FieldValue.delete() });
    } catch (err) {
        logger.error('processQueueDoc error', err);
        await ref.update({
            status: 'pending',
            error: String(err?.message || err),
            runAt: inMs(2000)
        });
    }
}

// ----------------------------------------------------------------
// PONTO DE ENTRADA (chamado pelo seu zApiWebhook)
// ----------------------------------------------------------------
// TROQUE o maybeHandleByBot pelo abaixo (mesma assinatura que seu webhook já usa)
async function maybeHandleByBot({ empresaId, phoneDoc, chatId, messageContent }) {
    try {
        const phoneId = phoneDoc.id;
        logger.info('[BOT] maybeHandleByBot/in', { empresaId, phoneId, chatId });

        const { chatDocRef } = getChatRefs(empresaId, phoneId, chatId);
        const chatSnap = await chatDocRef.get();
        const chatData = chatSnap.data() || {};

        const chatbotId = resolveActiveChatbotId({ phoneDoc, chatDocData: chatData });
        if (!chatbotId) {
            const cfg = (phoneDoc.data()?.chatbot) || {};
            logger.info('[BOT] no-chatbot-configured-or-disabled → skipping', {
                phoneId,
                cfgEnabled: cfg.enabled === true,
                cfgBotId: cfg.botId || null
            });
            return;
        }

        const botSnap = await admin.firestore()
            .collection('empresas').doc(empresaId)
            .collection('chatbots').doc(chatbotId).get();

        if (!botSnap.exists) { logger.warn('[BOT] chatbot-not-found', { empresaId, chatbotId }); return; }

        const chatbot = botSnap.data();
        logger.info('[BOT] chatbot-loaded', {
            chatbotId, startStepId: chatbot.startStepId, stepsCount: (chatbot.steps || []).length
        });

        const defaultSpacingMs = Number(chatbot.defaultSpacingMs || 1200);

        // marca no chat qual bot está sendo usado (opcional)
        if (chatData.chatbotId !== chatbotId) await chatDocRef.set({ chatbotId }, { merge: true });

        // cria/carrega sessão
        const { sessRef, session } = await loadOrInitSession({ empresaId, phoneId, chatId, chatbotDoc: botSnap });
        logger.info('[BOT] session-state', session);

        // se ainda não começou, começa pelo startStepId
        if (!session.currentStepId && session.status !== 'running') {
            const first = chatbot.startStepId || (chatbot.steps?.[0]?.id) || 'end';
            logger.info('[BOT] starting-flow', { first });
            await sessRef.set({ status: 'running', updatedAt: nowTs() }, { merge: true });
            await enqueue({ empresaId, phoneId, chatId, stepId: first, type: 'send_step', runAt: nowTs(), reason: 'start' });
            return;
        }

        // se está aguardando e o usuário respondeu → segue pelo onReply
        if (messageContent && session.awaitingReply && session.currentStepId) {
            logger.info('[BOT] got-reply', { stepId: session.currentStepId, preview: String(messageContent).slice(0,60) });
            await handleReply({ empresaId, phoneId, chatId, phoneDoc, chatbot, session, userText: messageContent, defaultSpacingMs });
            return;
        }

        // se não está aguardando e temos currentStepId → garante continuidade
        if (!session.awaitingReply && session.currentStepId) {
            logger.info('[BOT] resume-step', { stepId: session.currentStepId });
            await enqueue({
                empresaId, phoneId, chatId,
                stepId: session.currentStepId,
                type: 'send_step',
                runAt: nowTs(),                // << instantâneo
                reason: 'resume'
            });
        }
    } catch (e) {
        logger.error('maybeHandleByBot failed', e);
    }
}
exports.maybeHandleByBot = maybeHandleByBot;

// ----------------------------------------------------------------
// PROCESSADORES DE FILA
// ----------------------------------------------------------------

// 2) cron a cada minuto para pegar pendentes vencidas (collectionGroup)
exports.processBotQueue = onSchedule(
    { schedule: 'every 1 minutes', timeZone: 'America/Sao_Paulo', region: 'us-central1' },
    async () => {
        const now = admin.firestore.Timestamp.now();
        const snap = await admin.firestore()
            .collectionGroup('botQueue')
            .where('status', '==', 'pending')
            .where('runAt', '<=', now)
            .orderBy('runAt', 'asc')
            .limit(BOT.TICK_LIMIT)
            .get();

        logger.info('[BOT] scheduler tick', { pending: snap.size });
        for (const d of snap.docs) {
            try { await processQueueDoc(d.ref); }
            catch (e) { logger.error('processBotQueue item error', e); }
        }
    }
);

exports.onQueueCreatedWhatsapp = onDocumentCreated(
    {
        document: 'empresas/{empresaId}/phones/{phoneId}/whatsappChats/{chatId}/botQueue/{taskId}',
        region: 'us-central1',
    },
    async (event) => {
        logger.info('[BOT] onQueueCreatedWhatsapp fired', { path: event.data?.ref?.path });
        try { await processQueueDoc(event.data.ref); }
        catch (e) { logger.error('onQueueCreatedWhatsapp error', e); }
    }
);

// (opcional) legado: se você tiver chats/ em algum ambiente
exports.onQueueCreatedChats = onDocumentCreated(
    {
        document: 'empresas/{empresaId}/phones/{phoneId}/chats/{chatId}/botQueue/{taskId}',
        region: 'us-central1',
    },
    async (event) => {
        try { await processQueueDoc(event.data.ref); }
        catch (e) { logger.error('onQueueCreatedChats error', e); }
    }
);

function readZapiCredsFromPhoneDoc(phoneDoc) {
    const d = (phoneDoc.data() || {});
    const m = d.chatbot || {};

    const instanceId =
        m.instanceId || d.instanceId ||
        m.instanceID || d.instanceID ||
        m.instance   || d.instance   || null;

    const token =
        m.token || d.token ||
        m.apiToken || d.apiToken || null;

    const clientToken =
        m.clientToken || d.clientToken || null;

    const apiUrl = m.apiUrl || d.apiUrl || 'https://api.z-api.io';

    const where =
        (m.instanceId || m.token || m.clientToken || m.apiUrl) ? 'chatbot' :
            (d.instanceId || d.token || d.clientToken || d.apiUrl) ? 'root' : 'none';

    return { instanceId, token, clientToken, apiUrl, where };
}

// ----------------------------------------------------------------
// TEMPLATES E MENUS (com variáveis)
// ----------------------------------------------------------------
function renderTemplate(str, vars) {
    try {
        if (!str) return str;
        const v = vars || {};
        return String(str).replace(/\{\{\s*([a-zA-Z0-9_\.]+)\s*\}\}/g, (_m, k) => {
            if (v && Object.prototype.hasOwnProperty.call(v, k)) {
                const val = v[k];
                return val === undefined || val === null ? '' : String(val);
            }
            return '';
        });
    } catch (e) {
        // nunca deixe template quebrar envio
        return String(str || '');
    }
}

// ---------- TAGS (etiquetas) ----------
async function applyStepActionsToChat({ empresaId, phoneId, chatId, step }) {
    try {
        const tagId = step?.actions?.addTagId;
        if (!tagId) return;

        // empresas/{empresaId}/phones/{phoneId}/whatsappChats/{chatId}
        const { chatDocRef } = getChatRefs(empresaId, phoneId, chatId);

        await chatDocRef.set(
            { tags: admin.firestore.FieldValue.arrayUnion(tagId) },
            { merge: true }
        );

        // (Opcional) registrar também em subcoleção:
        // await chatDocRef.collection('tags').doc(tagId).set({ createdAt: nowTs() }, { merge: true });

        logger.info('[BOT] tag-applied', { chatPath: chatDocRef.path, stepId: step.id, tagId });
    } catch (e) {
        logger.error('[BOT] tag-apply-failed', e);
    }
}

async function persistBotTextMessage({ empresaId, phoneId, chatId, text, zapiId = null }) {
    if (!text) return null;
    const { chatDocRef } = getChatRefs(empresaId, phoneId, chatId);

    const msg = {
        content: text,
        type: 'text',            // o app renderiza como texto
        fromMe: true,            // “nosso lado” (direita + ✓✓)
        read: false,             // app só pinta ✓✓ quando receber confirmação
        sender: 'chatbot',
        senderName: 'Chatbot',
        senderPhoto: null,
        status: 'enviado',
        zapiId: zapiId,
        timestamp: nowTs(),
    };

    const msgRef = await chatDocRef.collection('messages').add(msg);

    // Atualiza resumo do chat (lista)
    const dt = new Date();
    const hh = String(dt.getHours()).padStart(2, '0');
    const mm = String(dt.getMinutes()).padStart(2, '0');
    await chatDocRef.set({
        lastMessage: text,
        lastMessageTime: `${hh}:${mm}`,
        timestamp: nowTs(),
    }, { merge: true });

    return msgRef.id;
}

// Mensagem de sistema (não atualiza lastMessage da lista)
async function persistSystemEventMessage({
                                             empresaId, phoneId, chatId,
                                             event,                  // 'handoff' | 'bot_end' | 'timeout_end' | etc
                                             label,                  // texto humanizado que aparecerá no chat
                                             extra = {},             // metadados opcionais
                                         }) {
    if (!label) return;

    const { chatDocRef } = getChatRefs(empresaId, phoneId, chatId);

    // leve proteção contra duplicidade por step/evento
    const guardId = `sys:${event}:${(extra.stepId || 'na')}`;
    const guardRef = chatDocRef.collection('botSendGuards').doc(guardId);
    const guard = await guardRef.get();
    if (guard.exists) return; // já registrado

    await guardRef.set({ createdAt: nowTs(), event });

    const msg = {
        type: 'system',
        content: label,         // o que o app mostra no chip
        systemEvent: event,     // chave para iconografia/cores, se quiser
        fromMe: false,          // centralizado, não é “de mim”
        read: true,             // não precisa ✓✓
        status: 'system',
        timestamp: nowTs(),
        meta: extra || null
    };

    await chatDocRef.collection('messages').add(msg);
}


// FIM FUNCTIONS CHATBOTS

/* ---- helpers de leitura de secret/env ---- */
function val(secretParam, envName, def = undefined) {
    try {
        const v = secretParam?.value?.();
        if (v) return v;
    } catch {}
    const env = process.env[envName];
    return (env !== undefined && env !== null && env !== '') ? env : def;
}

function buildSqsClient() {
    const region = val(AWS_REGION, 'AWS_REGION', 'us-east-2');
    const key    = val(AWS_ACCESS_KEY_ID, 'AWS_ACCESS_KEY_ID', null);
    const secret = val(AWS_SECRET_ACCESS_KEY, 'AWS_SECRET_ACCESS_KEY', null);
    const cfg = { region };
    if (key && secret) cfg.credentials = { accessKeyId: key, secretAccessKey: secret };
    return new SQSClient(cfg);
}

function resolveCompanyQueueUrl() {
    return val(AWS_SQS_COMPANY_QUEUE_URL, 'AWS_SQS_COMPANY_QUEUE_URL') || null;
}

function isFifoQueue(url = '') {
    return /\.fifo(\?|$)/i.test(String(url));
}

function safeSerialize(obj) {
    try { return JSON.parse(JSON.stringify(obj ?? {})); }
    catch { return {}; }
}

/* >>> Ajuste aqui: mapeia o nome a partir de "NomeEmpresa" <<< */
function sanitizeCompanyData(raw) {
    const d = safeSerialize(raw);
    const out = {
        // pega "NomeEmpresa" (c/ fallback nos outros campos que você já usava)
        name: d.NomeEmpresa ?? d.name ?? d.razaoSocial ?? null,
        tradeName: d.fantasia ?? null,
        cnpj: d.cnpj ?? null,
        email: d.email ?? null,
        phone: d.phone ?? d.whatsapp ?? null,
        createdAt: d.createdAt?._seconds ? new Date(d.createdAt._seconds * 1000).toISOString() : null,
        updatedAt: d.updatedAt?._seconds ? new Date(d.updatedAt._seconds * 1000).toISOString() : null,
    };
    Object.keys(out).forEach(k => (out[k] == null) && delete out[k]);
    return out;
}

function diffChangedFields(before = {}, after = {}) {
    const a = safeSerialize(after);
    const b = safeSerialize(before);
    const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
    const changed = [];
    for (const k of keys) {
        const va = JSON.stringify(a[k]);
        const vb = JSON.stringify(b[k]);
        if (va !== vb) changed.push(k);
    }
    return changed;
}

async function publishCompanyChangeToSqs(payload) {
    const QUEUE_URL = resolveCompanyQueueUrl();
    if (!QUEUE_URL) throw new Error('AWS_SQS_COMPANY_QUEUE_URL não configurada');

    const sqs = buildSqsClient();
    const params = {
        QueueUrl: QUEUE_URL,
        MessageBody: JSON.stringify(payload),
    };

    if (isFifoQueue(QUEUE_URL)) {
        // dedupe simples por (empresa, evento, minuto)
        const dedupe = `${payload.companyId}:${payload.event}:${Math.floor(payload.ts / 60000)}`;
        params.MessageGroupId = 'companies';
        params.MessageDeduplicationId = dedupe;
    }

    const cmd = new SendMessageCommand(params);
    return await sqs.send(cmd);
}

async function handleCompanyWrite({ beforeSnap, afterSnap, companyId, event }) {
    const after  = afterSnap?.exists ? afterSnap.data() : null;
    const before = beforeSnap?.exists ? beforeSnap.data() : null;

    const payload = {
        source: 'firebase',
        entity: 'company',
        event,                                // 'create' | 'update' | 'delete' | 'snapshot'
        companyId,
        ts: Date.now(),
        data: sanitizeCompanyData(after || before || {}),
        changedFields: event === 'update' ? diffChangedFields(before, after) : [],
    };

    // margem contra 256KB do SQS
    const bodySize = Buffer.byteLength(JSON.stringify(payload), 'utf8');
    if (bodySize > 240 * 1024) {
        payload.data = sanitizeCompanyData(after || before || {});
    }

    const result = await publishCompanyChangeToSqs(payload);
    logger.info('[SQS:companies] published', { companyId, event, messageId: result?.MessageId });
    return result;
}

/* =================== TRIGGERS (create/update/delete) =================== */
exports.onCompanyCreated = onDocumentCreated(
    {
        document: 'empresas/{companyId}',
        secrets: [AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, AWS_SQS_COMPANY_QUEUE_URL],
    },
    async (event) => {
        try {
            await handleCompanyWrite({
                beforeSnap: null,
                afterSnap: event.data,
                companyId: event.params.companyId,
                event: 'create',
            });
        } catch (e) {
            logger.error('onCompanyCreated → SQS publish failed', e);
        }
    }
);

exports.onCompanyUpdated = onDocumentUpdated(
    {
        document: 'empresas/{companyId}',
        secrets: [AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, AWS_SQS_COMPANY_QUEUE_URL],
    },
    async (event) => {
        try {
            await handleCompanyWrite({
                beforeSnap: event.data.before,
                afterSnap: event.data.after,
                companyId: event.params.companyId,
                event: 'update',
            });
        } catch (e) {
            logger.error('onCompanyUpdated → SQS publish failed', e);
        }
    }
);

exports.onCompanyDeleted = onDocumentDeleted(
    {
        document: 'empresas/{companyId}',
        secrets: [AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, AWS_SQS_COMPANY_QUEUE_URL],
    },
    async (event) => {
        try {
            await handleCompanyWrite({
                beforeSnap: event.data,
                afterSnap: null,
                companyId: event.params.companyId,
                event: 'delete',
            });
        } catch (e) {
            logger.error('onCompanyDeleted → SQS publish failed', e);
        }
    }
);

/* =================== REPLAY ON-DEMAND (opcional) =================== */
exports.replayAllCompaniesToSqs = onRequest(
    { secrets: [AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, AWS_SQS_COMPANY_QUEUE_URL] },
    async (req, res) => {
        res.set('Access-Control-Allow-Origin', '*');
        if (req.method === 'OPTIONS') return res.status(204).send('');
        if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');

        const expected = val(REPLAY_SECRET, 'REPLAY_SECRET'); // se existir, exigir
        if (expected && req.query.secret !== expected) {
            return res.status(403).json({ error: 'Forbidden' });
        }

        try {
            const pageSize = Math.min(Number(req.query.pageSize || 400), 1000);
            let last = null;
            let sent = 0;
            let pages = 0;

            while (true) {
                let q = db.collection('empresas').orderBy(admin.firestore.FieldPath.documentId()).limit(pageSize);
                if (last) q = q.startAfter(last);
                const snap = await q.get();
                if (snap.empty) break;

                pages++;
                last = snap.docs[snap.docs.length - 1];

                await Promise.all(
                    snap.docs.map(doc =>
                        handleCompanyWrite({
                            beforeSnap: null,
                            afterSnap: doc,      // trata como upsert no worker
                            companyId: doc.id,
                            event: 'create',
                        }).catch(e => {
                            logger.error('[SQS:replay] item failed', { id: doc.id, err: e?.message });
                            return null;
                        })
                    )
                );

                sent += snap.size;
            }

            return res.json({ status: 'ok', pages, sent });
        } catch (e) {
            logger.error('[SQS:replay] failed', e);
            return res.status(500).json({ error: e?.message || 'internal' });
        }
    }
);

exports.seedCompaniesOnce = onSchedule(
    {
        schedule: 'every 15 minutes',
        timeZone: 'America/Sao_Paulo',
        secrets: [AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, AWS_SQS_COMPANY_QUEUE_URL],
    },
    async () => {
        const flagRef = db.collection('meta').doc('sqsCompaniesSeed');
        const flag = await flagRef.get();
        if (flag.exists && flag.data()?.seededAt) {
            logger.info('[SQS:seed] já realizado — skipping');
            return;
        }

        logger.info('[SQS:seed] iniciando envio completo de empresas (1x)…');

        try {
            const pageSize = 800;
            let last = null;

            while (true) {
                let q = db.collection('empresas').orderBy(admin.firestore.FieldPath.documentId()).limit(pageSize);
                if (last) q = q.startAfter(last);
                const snap = await q.get();
                if (snap.empty) break;

                last = snap.docs[snap.docs.length - 1];

                await Promise.all(
                    snap.docs.map(doc =>
                        handleCompanyWrite({
                            beforeSnap: null,
                            afterSnap: doc,
                            companyId: doc.id,
                            event: 'create',     // seu worker faz upsert
                        }).catch(e => {
                            logger.error('[SQS:seed] item failed', { id: doc.id, err: e?.message });
                            return null;
                        })
                    )
                );
            }

            await flagRef.set({ seededAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
            logger.info('[SQS:seed] concluído e marcado como executado.');
        } catch (e) {
            logger.error('[SQS:seed] erro', e);
        }
    }
);

// === helpers: reaproveitando buildSqsClient/isFifoQueue/safeSerialize que você já tem ===
function resolveReportsQueueUrl() {
    // tenta Secret param e cai para process.env
    return (()=>{
        try { return AWS_SQS_REPORTS_QUEUE_URL.value(); } catch {}
        return process.env.AWS_SQS_REPORTS_QUEUE_URL || null;
    })();
}

async function publishReportUrlToSqs(payload) {
    const QUEUE_URL = resolveReportsQueueUrl();
    if (!QUEUE_URL) throw new Error('AWS_SQS_REPORTS_QUEUE_URL não configurada');

    const sqs = buildSqsClient();
    const params = {
        QueueUrl: QUEUE_URL,
        MessageBody: JSON.stringify(payload),
    };

    if (isFifoQueue(QUEUE_URL)) {
        // agrupa por empresa e cliente; dedupe por (empresa,cliente,mes)
        const key = `${payload.empresaAppId}:${payload.clienteId}:${payload.mesReferenciaSql}`;
        params.MessageGroupId = `reports-${payload.empresaAppId || 'na'}`;
        params.MessageDeduplicationId = key;
    }

    const cmd = new SendMessageCommand(params);
    return await sqs.send(cmd);
}

// === NOVO ENDPOINT HTTP: publica na fila exclusiva de relatórios, SEM criptografia ===
exports.sendReportUrlToSqs = onRequest({invoker: 'public', secrets: [AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, AWS_SQS_REPORTS_QUEUE_URL],
}, async (req, res) => {
    // CORS básico
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type');
    if (req.method === 'OPTIONS') return res.status(204).send('');
    if (req.method !== 'POST')   return res.status(405).send('Method Not Allowed');

    try {
        const body = req.body || {};
        const {
            empresaAppId,     // string
            clienteId,        // number | string numérica
            mesReferenciaSql, // "YYYY-MM-DD" (1º dia do mês)
            arquivoUrl,       // "/assets/clientes/<Cliente>/relatorios/10-2025.pdf"
            arquivoNome       // opcional ("10-2025.pdf")
        } = body;

        // validações mínimas
        if (!empresaAppId || !clienteId || !mesReferenciaSql || !arquivoUrl) {
            return res.status(400).json({ error: 'Campos obrigatórios: empresaAppId, clienteId, mesReferenciaSql, arquivoUrl' });
        }

        const payload = {
            source: 'crm',
            entity: 'report_url',
            event:  'create',
            ts: Date.now(),
            empresaAppId: String(empresaAppId),
            clienteId: Number(clienteId),
            mesReferenciaSql: String(mesReferenciaSql),
            arquivoUrl: String(arquivoUrl),
            arquivoNome: arquivoNome ? String(arquivoNome) : null,
        };

        const result = await publishReportUrlToSqs(payload);
        console.log('[SQS:reports] published', { messageId: result?.MessageId, empresaAppId, clienteId });

        return res.status(200).json({ status: 'ok', messageId: result?.MessageId });
    } catch (e) {
        console.error('[SQS:reports] fail', e);
        return res.status(500).json({ error: e?.message || 'internal' });
    }
});

// === PROCESSAR FILA DE RELATÓRIOS (SQS → Firestore) ===
exports.processReportsQueue = onSchedule(
    {
        schedule: 'every 1 minutes',
        timeZone: 'America/Sao_Paulo',
        secrets: [AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, AWS_SQS_REPORTS_QUEUE_URL],
        region: 'us-central1',
    },
    async () => {
        const region = val(AWS_REGION, 'AWS_REGION', 'us-east-2');
        const queueUrl = val(AWS_SQS_REPORTS_QUEUE_URL, 'AWS_SQS_REPORTS_QUEUE_URL', null);
        if (!queueUrl) {
            logger.error('[SQS:reports] AWS_SQS_REPORTS_QUEUE_URL ausente');
            return;
        }

        const sqs = buildSqsClient();
        const batchSize = 10;
        const waitSeconds = 10;
        let processed = 0, deleted = 0, failed = 0;

        const receive = async () => {
            const cmd = new ReceiveMessageCommand({
                QueueUrl: queueUrl,
                MaxNumberOfMessages: batchSize,
                WaitTimeSeconds: waitSeconds,
                VisibilityTimeout: 60,
            });
            return await sqs.send(cmd);
        };

        // helper para YYYY-MM a partir de "YYYY-MM-DD"
        const toYm = (sqlDate) => {
            const d = new Date(sqlDate);
            if (isNaN(d.getTime())) return null;
            const y = d.getUTCFullYear();
            const m = String(d.getUTCMonth() + 1).padStart(2, '0');
            return `${y}-${m}`;
        };

        while (true) {
            const resp = await receive();
            const msgs = resp.Messages || [];
            if (!msgs.length) break;

            const toDelete = [];
            for (const m of msgs) {
                const receipt = m.ReceiptHandle;
                try {
                    const body = JSON.parse(m.Body || '{}');

                    // payload esperado (o mesmo que você publicou)
                    const empresaAppId     = String(body.empresaAppId || '').trim();
                    const clienteId        = Number(body.clienteId || 0) || 0;
                    const mesReferenciaSql = String(body.mesReferenciaSql || '').trim(); // "YYYY-MM-DD"
                    const arquivoUrl       = String(body.arquivoUrl || '').trim();
                    const arquivoNome      = body.arquivoNome ? String(body.arquivoNome) : null;

                    if (!empresaAppId || !clienteId || !mesReferenciaSql || !arquivoUrl) {
                        throw new Error('Mensagem inválida: campos obrigatórios ausentes');
                    }

                    const ym = toYm(mesReferenciaSql); // "YYYY-MM"
                    if (!ym) throw new Error('mesReferenciaSql inválido');

                    // caminho: empresas/{empresaAppId}/relatorios/{YYYY-MM}
                    const docRef = db
                        .collection('empresas').doc(empresaAppId)
                        .collection('relatorios').doc(ym);

                    await docRef.set({
                        arquivoUrl,
                        arquivoNome: arquivoNome || null,
                        mesReferencia: mesReferenciaSql,        // manter compatível com a outra function
                        clienteId,
                        origem: 'crm-sqs',
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    }, { merge: true });

                    processed++;
                    if (receipt) {
                        toDelete.push({ Id: m.MessageId?.slice(0, 80) || String(Date.now()), ReceiptHandle: receipt });
                    }
                } catch (e) {
                    failed++;
                    logger.error('[SQS:reports] falha processando mensagem', { err: e?.message, body: m.Body });
                    // não deleta: mensagem volta após VisibilityTimeout
                }
            }

            if (toDelete.length) {
                const chunks = [];
                for (let i = 0; i < toDelete.length; i += 10) chunks.push(toDelete.slice(i, i + 10));
                for (const part of chunks) {
                    try {
                        const del = new DeleteMessageBatchCommand({ QueueUrl: queueUrl, Entries: part });
                        const resDel = await sqs.send(del);
                        deleted += (resDel.Successful || []).length;
                    } catch (e) {
                        logger.error('[SQS:reports] deleteMessageBatch falhou', { err: e?.message });
                    }
                }
            }
        }

        logger.info('[SQS:reports] tick concluído', { processed, deleted, failed, region, queueUrl });
    }
);

exports.drainReportsQueue = onRequest({
    secrets: [AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, AWS_SQS_REPORTS_QUEUE_URL],
}, async (req, res) => {
    try {
        // Reaproveita a lógica da processReportsQueue, mas rodando uma única passada
        // para facilitar testes manuais (POST no navegador/Postman).
        const region = val(AWS_REGION, 'AWS_REGION', 'us-east-2');
        const queueUrl = val(AWS_SQS_REPORTS_QUEUE_URL, 'AWS_SQS_REPORTS_QUEUE_URL', null);
        if (!queueUrl) return res.status(500).json({ error: 'AWS_SQS_REPORTS_QUEUE_URL ausente' });

        const sqs = buildSqsClient();
        const cmd = new ReceiveMessageCommand({
            QueueUrl: queueUrl,
            MaxNumberOfMessages: 10,
            WaitTimeSeconds: 5,
            VisibilityTimeout: 60,
        });
        const resp = await sqs.send(cmd);
        const msgs = resp.Messages || [];
        if (!msgs.length) return res.json({ status: 'ok', processed: 0 });

        const toDelete = [];
        let processed = 0, failed = 0;

        const toYm = (sqlDate) => {
            const d = new Date(sqlDate);
            if (isNaN(d.getTime())) return null;
            const y = d.getUTCFullYear();
            const m = String(d.getUTCMonth() + 1).padStart(2, '0');
            return `${y}-${m}`;
        };

        for (const m of msgs) {
            try {
                const body = JSON.parse(m.Body || '{}');
                const empresaAppId     = String(body.empresaAppId || '').trim();
                const clienteId        = Number(body.clienteId || 0) || 0;
                const mesReferenciaSql = String(body.mesReferenciaSql || '').trim();
                const arquivoUrl       = String(body.arquivoUrl || '').trim();
                const arquivoNome      = body.arquivoNome ? String(body.arquivoNome) : null;
                const ym = toYm(mesReferenciaSql);

                if (!empresaAppId || !clienteId || !mesReferenciaSql || !arquivoUrl || !ym) {
                    throw new Error('Mensagem inválida');
                }

                const docRef = db
                    .collection('empresas').doc(empresaAppId)
                    .collection('relatorios').doc(ym);

                await docRef.set({
                    arquivoUrl,
                    arquivoNome: arquivoNome || null,
                    mesReferencia: mesReferenciaSql,
                    clienteId,
                    origem: 'crm-sqs',
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });

                processed++;
                if (m.ReceiptHandle) toDelete.push({ Id: m.MessageId?.slice(0,80) || String(Date.now()), ReceiptHandle: m.ReceiptHandle });
            } catch (e) {
                failed++;
                logger.error('[SQS:reports] drain error', { err: e?.message, body: m.Body });
            }
        }

        if (toDelete.length) {
            const del = new DeleteMessageBatchCommand({ QueueUrl: queueUrl, Entries: toDelete });
            await sqs.send(del);
        }

        return res.json({ status: 'ok', processed, failed });
    } catch (e) {
        logger.error('[SQS:reports] drain fatal', e);
        return res.status(500).json({ error: e?.message || 'internal' });
    }
});

// Proxy de capas do Storage → retorna bytes com CORS liberado
exports.proxyReportCover = onRequest(
    { invoker: 'public', region: 'us-central1' }, // ajuste a região se necessário
    async (req, res) => {
        // CORS básico
        res.set('Access-Control-Allow-Origin', '*');
        res.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
        res.set('Access-Control-Allow-Headers', 'Content-Type');
        if (req.method === 'OPTIONS') return res.status(204).send('');

        try {
            const url = (req.query.url || '').toString();
            if (!url) {
                return res.status(400).json({ error: 'Parâmetro ?url= obrigatório' });
            }

            // Baixa do Storage no servidor (evita CORS do navegador)
            const resp = await axios.get(url, { responseType: 'arraybuffer', timeout: 15000 });

            // Encaminha os bytes com headers corretos
            const ct = resp.headers['content-type'] || 'image/png';
            res.set('Content-Type', ct);
            res.set('Cache-Control', 'public, max-age=31536000, immutable');
            // (opcional) ETag → navegador reaproveita cache condicional
            if (resp.headers.etag) res.set('ETag', resp.headers.etag);

            return res.status(200).send(Buffer.from(resp.data));
        } catch (e) {
            // Se a URL expirou/invalidou, responda 404 (ou 502 se preferir)
            const status = e?.response?.status || 502;
            return res.status(status).json({
                error: 'proxy_fetch_failed',
                status,
                detail: e?.message || 'fetch error',
            });
        }
    }
);

function digitsFromChatIdOrPhone(chatIdOrPhone) {
    return String(chatIdOrPhone || '')
        .replace('@s.whatsapp.net', '')
        .replace(/\D/g, '');
}

// true se distância de edição <= 1
function editDistanceAtMost1(a, b) {
    a = normalizeDigits(a);
    b = normalizeDigits(b);
    if (a === b) return true;

    const la = a.length, lb = b.length;
    if (Math.abs(la - lb) > 1) return false;

    // mesmo tamanho: no máx 1 substituição
    if (la === lb) {
        let mism = 0;
        for (let i = 0; i < la; i++) {
            if (a[i] !== b[i] && ++mism > 1) return false;
        }
        return true;
    }

    // tamanhos diferentes em 1: no máx 1 inserção/remoção
    const s = la < lb ? a : b; // menor
    const t = la < lb ? b : a; // maior
    let i = 0, j = 0, used = false;

    while (i < s.length && j < t.length) {
        if (s[i] === t[j]) { i++; j++; continue; }
        if (used) return false;
        used = true;
        j++; // pula 1 no maior (inserção/remoção)
    }
    return true;
}

// score aproximado (p/ debug/seleção)
function similarityScore(a, b) {
    a = normalizeDigits(a);
    b = normalizeDigits(b);
    if (!a || !b) return 0;
    if (a === b) return 1;

    // para nosso caso, se distância <=1, é “quase igual”
    if (editDistanceAtMost1(a, b)) {
        return 1 - (1 / Math.max(a.length, b.length));
    }
    return 0;
}

async function resolveChatIdForNumber({ empresaId, phoneId, phoneDigits }) {
    const digits = normalizeDigits(phoneDigits);
    const candidates = buildPhoneCandidates(digits);

    const baseCol = db
        .collection('empresas').doc(empresaId)
        .collection('phones').doc(phoneId)
        .collection('whatsappChats');

    // 1) tenta chats no padrão "<número>@s.whatsapp.net"
    for (const cand of candidates) {
        const jidId = `${cand}@s.whatsapp.net`;
        const snap = await baseCol.doc(jidId).get();
        if (snap.exists) return jidId;
    }

    // 2) tenta chats antigos só com dígitos
    for (const cand of candidates) {
        const snap = await baseCol.doc(cand).get();
        if (snap.exists) return cand;
    }

    // 3) fuzzy: olha os últimos N chats (evita varrer tudo)
    //    (se você não tem timestamp em todos, pode cair pra .limit(N) sem orderBy)
    let recentSnap;
    try {
        recentSnap = await baseCol.orderBy('timestamp', 'desc').limit(250).get();
    } catch {
        recentSnap = await baseCol.limit(250).get();
    }

    let bestChatId = null;
    let bestScore = 0;

    for (const d of recentSnap.docs) {
        const docDigits = digitsFromChatIdOrPhone(d.id);
        // compara doc com todas as variações geradas
        for (const cand of candidates) {
            const sc = similarityScore(cand, docDigits);
            if (sc > bestScore) {
                bestScore = sc;
                bestChatId = d.id;
            }
        }
    }

    // "99%" → para 12~13 dígitos, isso equivale a “<=1 diferença”
    // como nosso score é 1 - 1/maxLen quando dist<=1, o corte abaixo bate ~0.92+.
    // então usamos a REGRA REAL: editDistanceAtMost1.
    if (bestChatId) {
        const bestDigits = digitsFromChatIdOrPhone(bestChatId);
        for (const cand of candidates) {
            if (editDistanceAtMost1(cand, bestDigits)) {
                logger.info('[resolveChatIdForNumber] fuzzy matched', {
                    digits, bestChatId, bestDigits, candidatesCount: candidates.length
                });
                return bestChatId;
            }
        }
    }

    // 4) não existe: cria novo padrão
    return `${digits}@s.whatsapp.net`;
}

function parseDataUri(input) {
    const s = String(input || '');
    const m = /^data:([^;]+);base64,(.*)$/i.exec(s);
    if (m) return { mime: m[1], b64: m[2] };
    return { mime: null, b64: s };
}

function getBucketName() {
    // 1) se você configurar no initializeApp({storageBucket}), pega daqui
    const fromApp = admin.app().options.storageBucket;
    if (fromApp) return fromApp;

    // 2) tenta FIREBASE_CONFIG (Cloud Functions geralmente tem)
    try {
        const cfg = JSON.parse(process.env.FIREBASE_CONFIG || '{}');
        if (cfg.storageBucket) return cfg.storageBucket;
    } catch (_) {}

    // 3) fallback (caso você defina via env)
    return process.env.FIREBASE_STORAGE_BUCKET || process.env.GCLOUD_STORAGE_BUCKET || null;
}

async function uploadBase64ToStorage({ empresaId, phoneId, chatId, uniqueId, kind, data, fileName, defaultMime }) {
    const { mime, b64 } = parseDataUri(data);

    const buf = Buffer.from(b64, 'base64');
    const contentType = mime || defaultMime || 'application/octet-stream';

    const safeName = (fileName || `${kind}_${uniqueId}`).replace(/[^\w.\-]+/g, '_');
    const ext = (contentType.split('/')[1] || 'bin').split(';')[0];
    const finalName = safeName.includes('.') ? safeName : `${safeName}.${ext}`;

    const storagePath = `whatsapp/${empresaId}/${phoneId}/${chatId}/outgoing/${uniqueId}/${finalName}`;

    const bucketName = getBucketName();
    if (!bucketName) {
        throw new Error('STORAGE_BUCKET_NOT_FOUND: configure storageBucket no initializeApp ou FIREBASE_CONFIG');
    }

    const bucket = admin.storage().bucket(bucketName);
    const file = bucket.file(storagePath);

    // token compatível com Firebase Storage download URL
    const token = crypto.randomUUID();

    await file.save(buf, {
        resumable: false,
        metadata: {
            contentType,
            metadata: {
                firebaseStorageDownloadTokens: token,
            },
        },
    });

    // download URL público (com token) - não precisa signed url
    const encodedPath = encodeURIComponent(storagePath);
    const url = `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodedPath}?alt=media&token=${token}`;

    return { url, contentType, sizeBytes: buf.length, path: storagePath, fileName: finalName };
}

exports.proxyMedia = onRequest(
    { invoker: 'public', region: 'us-central1' },
    async (req, res) => {
        res.set('Access-Control-Allow-Origin', '*');
        res.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
        res.set('Access-Control-Allow-Headers', 'Content-Type');
        if (req.method === 'OPTIONS') return res.status(204).send('');

        try {
            const url = String(req.query.url || '').trim();
            if (!url) return res.status(400).json({ error: 'missing_url' });

            const resp = await axios.get(url, {
                responseType: 'arraybuffer',
                timeout: 30000,
            });

            const ct = resp.headers['content-type'] || 'application/octet-stream';
            res.set('Content-Type', ct);

            // cache leve (você pode aumentar depois)
            res.set('Cache-Control', 'public, max-age=3600');

            return res.status(200).send(Buffer.from(resp.data));
        } catch (e) {
            const status = e?.response?.status || 502;
            return res.status(status).json({
                error: 'proxy_fetch_failed',
                status,
                detail: e?.message || 'fetch error',
            });
        }
    }
);

async function callZGet(instanceId, token, path, headers = {}, timeout = 15000) {
    let lastErr = null;
    const enc = encodeURIComponent;

    for (const host of ZAPI_HOSTS) {
        const baseUrl = `${host}/instances/${enc(instanceId)}/token/${enc(token)}`;
        const url = `${baseUrl}${path}`;

        try {
            const resp = await axios.get(url, {
                headers: { ...headers },
                timeout,
            });

            const data = resp?.data;
            if (data && (data.error || /Unable to find matching target resource method/i.test(String(data.message || '')))) {
                lastErr = { host, status: 404, data };
                continue;
            }
            return { host, resp };
        } catch (e) {
            lastErr = { host, status: e?.response?.status || 500, data: e?.response?.data || e?.message };
            continue;
        }
    }

    const err = new Error('Z-API GET failed on all hosts');
    err.status = lastErr?.status || 500;
    err.data = lastErr?.data;
    throw err;
}

const PHOTO_TTL_HOURS = 36;
const PHOTO_TTL_MS = PHOTO_TTL_HOURS * 3600 * 1000;

async function refreshOnePhone(empresaId, phoneId) {
    const phoneSnap = await db.doc(`empresas/${empresaId}/phones/${phoneId}`).get();
    if (!phoneSnap.exists) return;

    const phoneData = phoneSnap.data() || {};
    const instanceId  = decryptIfNeeded(phoneData.instanceId, 'instanceId');
    const token       = decryptIfNeeded(phoneData.token, 'token');
    const clientToken = decryptIfNeeded(phoneData.clientToken, 'clientToken');
    if (!instanceId || !token || !clientToken) return;

    const headers = { 'Client-Token': clientToken };

    const chatsSnap = await db
        .collection(`empresas/${empresaId}/phones/${phoneId}/whatsappChats`)
        .get();

    let batch = db.batch();
    let writes = 0;

    const commitBatch = async () => {
        if (writes === 0) return;
        await batch.commit();
        batch = db.batch();     // ✅ reseta
        writes = 0;
    };

    for (const chatDoc of chatsSnap.docs) {
        const chat = chatDoc.data() || {};
        const lastMillis = chat.photoUpdatedAt?.toMillis?.() || 0;

        // ainda está “fresco”
        if (lastMillis && (Date.now() - lastMillis) < PHOTO_TTL_MS) continue;

        const phoneDigits = String(chatDoc.id).replace(/\D/g, '');
        if (!phoneDigits) continue;

        try {
            const { resp } = await callZGet(
                instanceId,
                token,
                `/profile-picture?phone=${encodeURIComponent(phoneDigits)}`,
                headers,
                15000
            );

            const arr = resp.data;
            const link = Array.isArray(arr) ? (arr[0]?.link || '') : (arr?.link || '');
            const newPhoto = String(link || '').trim();

            // ✅ só grava se veio link
            if (newPhoto) {
                batch.set(chatDoc.ref, {
                    contactPhoto: newPhoto,
                    photoUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });
                writes++;
            } else {
                // se veio resposta mas sem link, NÃO marca como atualizado
                // (pra tentar de novo no próximo cron)
                continue;
            }

            if (writes >= 450) await commitBatch(); // ✅ commit em blocos
        } catch (e) {
            // erro/transiente: não marca, tenta de novo no próximo cron
            logger.warn('refreshOnePhone: falha profile-picture', {
                empresaId, phoneId, chatId: chatDoc.id, err: e?.message
            });
            continue;
        }
    }

    await commitBatch();
}


exports.refreshContactPhotosScheduled = onSchedule(
    { schedule: 'every 6 hours', timeZone: 'America/Sao_Paulo', region: 'us-central1', secrets: [ZAPI_ENC_KEY] },
    async () => {
        const snap = await db.collectionGroup('phones').get();

        // Limite de concorrência simples
        const limit = 5;
        const queue = [];

        for (const doc of snap.docs) {
            const parts = doc.ref.path.split('/');
            const empresaId = parts[1];
            const phoneId = doc.id;

            queue.push(() => refreshOnePhone(empresaId, phoneId));

            if (queue.length >= limit) {
                const chunk = queue.splice(0, limit).map(fn => fn());
                await Promise.allSettled(chunk);
            }
        }

        if (queue.length) {
            await Promise.allSettled(queue.map(fn => fn()));
        }
    }
);

exports.refreshContactPhotosNow = onRequest(
    { secrets: [ZAPI_ENC_KEY], cors: true },
    async (req, res) => {
        res.set('Access-Control-Allow-Origin', '*');
        res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
        res.set('Access-Control-Allow-Headers', 'Content-Type');
        if (req.method === 'OPTIONS') return res.status(204).send('');

        try {
            const { empresaId, phoneId, force = false } = req.body || {};
            if (!empresaId || !phoneId) {
                return res.status(400).json({ error: 'empresaId e phoneId são obrigatórios' });
            }

            if (force) {
                // força recálculo zerando photoUpdatedAt para todos os chats do phone
                const snap = await db
                    .collection(`empresas/${empresaId}/phones/${phoneId}/whatsappChats`)
                    .get();

                const batch = db.batch();
                let n = 0;
                snap.docs.forEach((d) => {
                    batch.set(d.ref, { photoUpdatedAt: admin.firestore.FieldValue.delete() }, { merge: true });
                    n++;
                });
                if (n) await batch.commit();
            }

            await refreshOnePhone(empresaId, phoneId);
            return res.json({ ok: true, empresaId, phoneId, forced: !!force });
        } catch (e) {
            logger.error('refreshContactPhotosNow error', e);
            return res.status(500).json({ error: e?.message || String(e) });
        }
    }
);