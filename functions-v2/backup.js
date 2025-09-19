const {onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onDocumentCreated, onDocumentUpdated} = require('firebase-functions/v2/firestore');
const logger = require("firebase-functions/logger");
const functions = require("firebase-functions/v2");
const admin = require('firebase-admin');
const axios = require('axios');
const cors = require('cors');
const express = require("express");
admin.initializeApp();
const db = admin.firestore();
const auth = admin.auth();
const app = express();
app.use(cors({origin: true}));
const {defineSecret} = require('firebase-functions/params');
const {SQSClient, SendMessageCommand} = require("@aws-sdk/client-sqs");
const crypto = require('crypto');
const normInstanceId = (s) => String(s || '').trim().toUpperCase(); // evita variação de caixa/espaço
const hashInstanceId = (s) =>
    crypto.createHash('sha256').update(normInstanceId(s), 'utf8').digest('hex');
const ZAPI_ENC_KEY = defineSecret('ZAPI_ENC_KEY'); // chave AES-256 (base64, 32 bytes)
const ENCRYPTION_KEY = defineSecret('ENCRYPTION_KEY');

function buildSqsClient() {
    return new SQSClient({
        region: process.env.AWS_REGION || "us-east-2",
        credentials: {
            accessKeyId: process.env.AWS_ACCESS_KEY_ID,
            secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
        },
    });
}

// ===== Z-API host fallback + invocador único (ESPAÇO GLOBAL) =====
const ZAPI_HOSTS = [
    'https://api-v2.z-api.io',
    'https://api.z-api.io',
];

// Use "function" (declaração) para evitar problemas de TDZ/escopo
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

// ───── lookup a partir do número que chega no webhook ─────
async function getPhoneCtxByNumber(phoneDigits) {
    const snap = await db
        .collectionGroup('phones')
        .where('phoneId', '==', phoneDigits)     // ✅  NÃO usa documentId()
        .limit(1)
        .get();

    if (snap.empty) throw new Error(`Número ${phoneDigits} não cadastrado`);

    const phoneDoc  = snap.docs[0];
    const empresaId = phoneDoc.ref.path.split('/')[1]; // empresas/{empresaId}/phones/…

    return { empresaId, phoneDoc };
}

// SUBSTITUA a função atual
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

exports.zApiWebhook = onRequest(async (req, res) => {
    try {
        logger.info("Recebido webhook da Z-API:", req.body);
        const data = req.body;

        /** ───────────────────────────────────────────────────────────
         *  0. Helpers locais
         *  ────────────────────────────────────────────────────────── */
        const digits = (n) => (n || '').toString().replace(/\D/g, '');

        /** ═════════ 1. ACK de leitura ══════════════════════════════ */
        if (data?.ack === 'read' && data.id) {
            const digits = (n) => (n || '').toString().replace(/\D/g, '');
            const clientDigits    = digits(data.phone);            // número do cliente
            const serverDigits    = digits(data.connectedPhone);   // seu número-empresa
            const zapiId          = data.id;

            let empresaId, phoneDoc;
            try {
                if (serverDigits) {
                    ({ empresaId, phoneDoc } = await getPhoneCtxByNumber(serverDigits));
                } else {
                    ({ empresaId, phoneDoc } = await getPhoneCtxByInstance(data.instanceId));
                }
            } catch (e) {
                logger.error('ACK read: não foi possível identificar phoneDoc', e);
                return res.status(200).send('ACK ignorado (sem contexto)');
            }

            const phoneId = phoneDoc.id; // ex.: 554691395827 (SEU número)
            const { chatDocRef, msgsColRef } = getChatRefs(
                empresaId,
                phoneId,
                clientDigits + '@s.whatsapp.net',
            );

            const snap  = await msgsColRef.where('zapiId','==', zapiId).get();
            const batch = admin.firestore().batch();
            snap.docs.forEach(d => batch.set(d.ref, { read: true, status: 'read' }, { merge: true }));
            await batch.commit();

            return res.status(200).send('ACK de leitura processado');
        }

        /* ───── 2. Callback de mensagem recebida ───── */
        if (INBOUND_TYPES.includes(String(data?.type))) {
            const digits = (n) => (n || '').toString().replace(/\D/g, '');
            const remoteDigits = digits(data.phone);
            const serverDigits = digits(data.connectedPhone);
            const chatId       = remoteDigits + '@s.whatsapp.net';

            let empresaId, phoneDoc;
            try {
                ({ empresaId, phoneDoc } = await getPhoneCtxByInstance(data.instanceId));
            } catch (e) {
                if (!serverDigits) throw e;
                ({ empresaId, phoneDoc } = await getPhoneCtxByNumber(serverDigits));
            }

            const phoneId  = phoneDoc.id;
            const chatName = data.chatName || data.senderName || remoteDigits;

            // tipo + conteúdo
            let messageContent = '';
            let messageType    = 'text';
            if      (data.text?.message)       { messageContent = data.text.message;       }
            else if (data.audio?.audioUrl)     { messageContent = data.audio.audioUrl;     messageType = 'audio'; }
            else if (data.image?.imageUrl)     { messageContent = data.image.imageUrl;     messageType = 'image'; }
            else if (data.video?.videoUrl)     { messageContent = data.video.videoUrl;     messageType = 'video'; }
            else if (data.sticker?.stickerUrl) { messageContent = data.sticker.stickerUrl; messageType = 'sticker'; }

            const { chatDocRef, msgsColRef } = getChatRefs(empresaId, phoneId, chatId);

            // 1) grava a mensagem recebida
            await msgsColRef.doc().set({
                content   : messageContent,
                type      : messageType,
                timestamp : admin.firestore.FieldValue.serverTimestamp(),
                fromMe    : data.fromMe === true,
                sender    : data.participantPhone || data.phone,
                senderName: data.senderName || '',
                senderPhoto: data.senderPhoto || data.photo || '',
                zapiId    : data.id || null,
                read      : false,
                status    : 'novo',
                saleValue : null,
            });

            // 2) atualiza o chat (em transação MINIMAL)
            await admin.firestore().runTransaction(async (tx) => {
                const snap = await tx.get(chatDocRef);
                const cur  = snap.exists ? snap.data() : {};
                const curStatus = cur?.status ?? 'novo';
                const preserve = ['atendendo'];
                const newStatus = preserve.includes(curStatus) ? curStatus : 'novo';

                // histórico se estava finalizado
                if (['concluido_com_venda', 'recusado'].includes(curStatus)) {
                    await chatDocRef.collection('history').add({
                        status   : curStatus,
                        saleValue: cur.saleValue ?? null,
                        changedAt: admin.firestore.FieldValue.serverTimestamp(),
                        updatedBy: 'system',
                    });
                }

                tx.set(chatDocRef, {
                    chatId,
                    arrivalAt : cur.arrivalAt ?? admin.firestore.FieldValue.serverTimestamp(),
                    name         : chatName,
                    contactPhoto : data.senderPhoto || data.photo || '',
                    lastMessage  : messageContent,
                    lastMessageTime : new Date().toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'}),
                    type       : messageType,
                    timestamp  : admin.firestore.FieldValue.serverTimestamp(),
                    status     : newStatus,
                    saleValue  : newStatus === 'novo' ? null : cur.saleValue ?? null,
                    ...(data.fromMe ? {} : { unreadCount: admin.firestore.FieldValue.increment(1) }),
                }, { merge: true });
            });

            // 3) *** roda o bot FORA da transação ***
            try {
                logger.info('[zApiWebhook] chamando maybeHandleByBot', {
                    empresaId, phoneId, chatId, messageType, contentPreview: String(messageContent||'').slice(0,120)
                });
                await maybeHandleByBot({ empresaId, phoneDoc, chatId, messageContent });
            } catch (e) {
                logger.error('Bot handler falhou', e);
            }
        }

        return res.status(200).send('OK');
    } catch (error) {
        logger.error('Erro no webhook Z-API:', error);
        /** devolvemos 200 mesmo em erro para não bloquear a Z-API */
        return res.status(200).send('Erro interno, mas ACK enviado');
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
        const { empresaId, phoneId, chatId, message, fileType, fileData, clientMessageId } = req.body;

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
            payload = { phone: phoneDigits, image: imageData, message: message || "" };

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
            payload = { phone: phoneDigits, video: fileData || "", message: message || "" };

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

        // Monta doc Firestore
        const firestoreData = {
            timestamp       : admin.firestore.FieldValue.serverTimestamp(),
            fromMe          : true,
            sender          : zData.sender || null,
            clientMessageId : uniqueId,
            zapiId          : zMsgId,
            status          : 'sent',         // delivered/read virão via webhook
            read            : false,
            type            : kind,
            content         : (kind === 'text') ? (message || '') : (fileData || ''),
            ...(kind !== 'text' ? { caption: message || '' } : {})
        };

        await msgsColRef.add(firestoreData);

        await chatDocRef.set({
            chatId,
            lastMessage: (kind !== "text" && message) ? message : firestoreData.content,
            lastMessageTime: admin.firestore.FieldValue.serverTimestamp(),
            type: kind,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        return res.status(200).send(zData);
    } catch (error) {
        logger.error("Erro ao enviar mensagem", {
            status: error?.status || error?.response?.status,
            body: error?.data || error?.response?.data || error?.message
        });
        return res.status(error?.status || error?.response?.status || 500)
            .send(error?.data || error?.response?.data || error.toString());
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
        if (!rawPhone)
            return res.status(400).json({ error: "Parâmetro phone ausente" });

        /* 3) Sanitiza */
        const phone = rawPhone.replace(/\D/g, '');
        if (!/^\d{10,15}$/.test(phone))
            return res.status(400).json({ error: "Parâmetro 'phone' inválido" });

        /* 4) Busca credenciais do número da empresa */
        const { phoneDocRef } = getChatRefs(empresaId, phoneId, phoneId); // ← ADICIONE ESTA LINHA
        const phoneData = (await phoneDocRef.get()).data() || {};
        const ZAPI_ID           = decryptIfNeeded(phoneData.instanceId)  || process.env.ZAPI_ID;
        const ZAPI_TOKEN        = decryptIfNeeded(phoneData.token)       || process.env.ZAPI_TOKEN;
        const ZAPI_CLIENT_TOKEN = decryptIfNeeded(phoneData.clientToken) || process.env.ZAPI_CLIENT_TOKEN;

        if (!ZAPI_ID || !ZAPI_TOKEN || !ZAPI_CLIENT_TOKEN) {
            return res.status(500).json({ status:'error', message:'Credenciais Z-API ausentes' });
        }

        try {
            const url = `https://api.z-api.io/instances/${ZAPI_ID}/token/${ZAPI_TOKEN}/createChat`;
            const headers = { 'Content-Type': 'application/json', 'Client-Token': ZAPI_CLIENT_TOKEN };

            const zRes = await axios.post(url, { phone }, { headers });
            logger.info('Status Z-API:', zRes.status, zRes.data);

            return res.status(200).json({ status: 'success', data: zRes.data });
        } catch (err) {
            logger.error('Z-API erro', err.response?.status, err.response?.data);
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

exports.enableReadReceipts = onRequest(async (req, res) => {
    // CORS pre-flight
    if (req.method === 'OPTIONS') return res.status(204).send('');

    const {ZAPI_ID, ZAPI_TOKEN, ZAPI_CLIENT_TOKEN} = process.env;
    if (!ZAPI_ID || !ZAPI_TOKEN || !ZAPI_CLIENT_TOKEN)
        return res.status(500).send('Variáveis de ambiente faltando');

    try {
        const url =
            `https://api.z-api.io/instances/${ZAPI_ID}/token/${ZAPI_TOKEN}` +
            `/privacy/read-receipts?value=enable`;

        const r = await axios.post(
            url,
            {},
            {headers: {'Client-Token': ZAPI_CLIENT_TOKEN}},
        );

        return res.status(200).json(r.data);      // { success:true }
    } catch (err) {
        console.error('Z-API read-receipts error', err.response?.data || err);
        return res.status(err.response?.status || 500).send(err.toString());
    }
});

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

exports.updateContactPhotos = onRequest({ secrets: [ZAPI_ENC_KEY] }, async (req,res)=>{
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
        const plain = {
            instanceId : (instanceId),
            token      : (token),
            clientToken: (clientToken),
        };
        if (!plain.instanceId || !plain.token || !plain.clientToken) {
            throw new Error('Credenciais Z-API ausentes no documento phone');
        }

        /* ────────── 4. Todos os chats do número ─────── */
        const chatsSnap = await db
            .collection(`empresas/${empresaId}/phones/${phoneId}/whatsappChats`)
            .get();

        const toUpdate = [];

        for (const chatDoc of chatsSnap.docs) {
            const chatData    = chatDoc.data() || {};
            const phoneDigits = chatDoc.id.replace(/\D/g, '');   // 55…

            /* ---- 4.1 checa “idade” do avatar ---- */
            const lastMillis = chatData.photoUpdatedAt?.toMillis?.() || 0;
            if (Date.now() - lastMillis < MAX_PHOTO_AGE_MS) continue;   // ainda fresco

            /* ---- 4.2 consulta Z‑API ---- */
            const zUrl = `https://api.z-api.io/instances/${plain.instanceId}/token/${plain.token}/contacts/profile-picture/${phoneDigits}`;

            try {
                const zRes = await axios.get(zUrl, { headers: { 'Client-Token': plain.clientToken } });
                const newPhoto = zRes.data.profilePic || '';   // ajuste se response diferente

                // Sempre grava photoUpdatedAt – mesmo que o link seja o mesmo
                const payload = newPhoto
                    ? { contactPhoto: newPhoto, photoUpdatedAt: admin.firestore.FieldValue.serverTimestamp() }
                    : { contactPhoto: admin.firestore.FieldValue.delete(), photoUpdatedAt: admin.firestore.FieldValue.serverTimestamp() };

                toUpdate.push(chatDoc.ref.set(payload, { merge: true }));
            } catch (zErr) {
                if (zErr.response?.status === 404) {
                    // contato sem foto: remove campo e marca timestamp
                    toUpdate.push(
                        chatDoc.ref.set(
                            { contactPhoto: admin.firestore.FieldValue.delete(),
                                photoUpdatedAt: admin.firestore.FieldValue.serverTimestamp() },
                            { merge: true }
                        )
                    );
                } else {
                    console.error(`updateContactPhotos · erro no nº ${phoneDigits}`, zErr.response?.data || zErr);
                }
            }
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

// === Dispara job recém-criado imediatamente (com "espera curta" até runAt) ===
exports.onBotJobCreated = onDocumentCreated(
    { document: 'empresas/{empresaId}/phones/{phoneId}/whatsappChats/{chatId}/botQueue/{jobId}', secrets: [ZAPI_ENC_KEY] },
    async (event) => {
        const d = event.data?.data() || {};
        const { empresaId, phoneId, chatId } = event.params;

        try {
            const now = Date.now();
            const due = d.runAt?.toMillis?.() || 0;
            if (d.status !== 'pending') return;

            const NEAR_FUTURE_MS = 15_000;
            if (due > now + NEAR_FUTURE_MS) return;

            const waitMs = Math.max(0, Math.min(due - now, NEAR_FUTURE_MS));
            if (waitMs > 0) await new Promise(r => setTimeout(r, waitMs));

            const claimed = await db.runTransaction(async (tx) => {
                const fresh = await tx.get(event.data.ref);
                const cur = fresh.data() || {};
                const curDue = cur.runAt?.toMillis?.() || 0;
                if (cur.status !== 'pending' || curDue > Date.now()) return false;
                tx.update(event.data.ref, { status: 'processing', processingAt: admin.firestore.FieldValue.serverTimestamp() });
                return true;
            });
            if (!claimed) return;

            const { phoneDocRef, chatDocRef, msgsColRef } = getChatRefs(empresaId, phoneId, chatId);
            const { instanceId, token, clientToken } = await getZCredPlain(empresaId, phoneDocRef);
            if (!instanceId || !token || !clientToken) {
                await event.data.ref.set({ status: 'error', error: 'missing-credentials' }, { merge: true });
                return;
            }

            if (d.type === 'burst') {
                const seq = Array.isArray(d.items) ? d.items : [];
                const gap = Number(d.defaultSpacingMs || 600);
                logger.info('[burst:start]', { chatId, count: seq.length, gap });

                for (let i = 0; i < seq.length; i++) {
                    const it = seq[i];
                    const wait = i === 0 ? 0 : (Number(it.delayMs) || gap);
                    if (wait > 0) await new Promise(r => setTimeout(r, wait));
                    logger.info('[burst:send]', { chatId, i, waitMs: wait, preview: String(it.text || '').slice(0, 80) });
                    await sendBotText(instanceId, token, clientToken, chatId, String(it.text || ''));
                    await logOut(msgsColRef, String(it.text || ''));
                }

                logger.info('[burst:done]', { chatId, count: seq.length });
                await event.data.ref.set({ status: 'done', doneAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
                return;
            }

            if (d.type === 'timeout') {
                const sessionRef = chatDocRef.collection('runtime').doc('bot');
                const sSnap = await sessionRef.get();
                const session = sSnap.data() || {};
                if (!session.active)  { await event.data.ref.set({ status: 'skipped', reason: 'inactive' }, { merge: true }); return; }
                if (session.stepId !== d.stepId) { await event.data.ref.set({ status: 'skipped', reason: 'moved-step' }, { merge: true }); return; }
                if ((session.lastUserAt || 0) > (d.runAt?.toMillis?.() || 0)) {
                    await event.data.ref.set({ status: 'skipped', reason: 'user-replied' }, { merge: true }); return;
                }

                const botSnap = await db.doc(`empresas/${empresaId}/chatbots/${session.botId}`).get();
                if (!botSnap.exists) { await event.data.ref.set({ status: 'error', error: 'bot-not-found' }, { merge: true }); return; }

                const bot = botSnap.data() || {};
                const stepsArr = Array.isArray(bot.steps) ? bot.steps : [];
                const steps    = indexById(stepsArr);
                const startId  = d.nextId || steps[session.stepId]?.meta?.timeoutNext || 'end';
                const walked   = walkUntilInteractive(steps, startId, session.vars, stepsArr);

                await enqueueBurst({
                    empresaId, phoneId, chatId,
                    items: walked.outMsgs,
                    originStepId: walked.interactiveStep ? walked.interactiveStep.id : walked.finalStepId,
                    defaultSpacingMs: Number(bot.defaultSpacingMs || 1200)
                });

                const nextStep = walked.interactiveStep || steps[walked.finalStepId];
                await sessionRef.set({
                    stepId: (nextStep && nextStep.id) || walked.finalStepId,
                    lastBotAt: Date.now(),
                }, { merge: true });

                const tmMin = Number(nextStep?.meta?.timeoutMinutes || 0);
                const tmNext = nextStep?.meta?.timeoutNext || null;
                if (tmMin > 0) {
                    await enqueueTimeout({ empresaId, phoneId, chatId, stepId: nextStep.id, nextId: tmNext, timeoutMinutes: tmMin });
                }

                await event.data.ref.set({ status: 'done', doneAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
                return;
            }

            await event.data.ref.set({ status: 'error', error: 'unknown-type' }, { merge: true });
        } catch (err) {
            await event.data.ref.set({ status: 'error', error: String(err?.message || err) }, { merge: true });
        }
    }
);

function mask(s) { return s ? String(s).slice(0, 6) + '…' : null; }

// leitura aninhada segura: getPath(emp, "zapi.instanceId")
function getPath(obj, path) {
    try {
        return String(path).split('.').reduce((o,k)=> (o && (k in o)) ? o[k] : undefined, obj);
    } catch { return undefined; }
}

function firstNonEmpty(list) {
    for (const v of list) { if (v !== undefined && v !== null && String(v).trim() !== '') return String(v); }
    return null;
}

async function getZCredPlain(empresaId, phoneDocRef) {
    const [phoneSnap, empSnap] = await Promise.all([phoneDocRef.get(), db.doc(`empresas/${empresaId}`).get()]);
    const phone = phoneSnap.exists ? (phoneSnap.data() || {}) : {};
    const emp   = empSnap.exists   ? (empSnap.data()   || {}) : {};

    const pick = (...cands) => {
        for (const v of cands) {
            const s = (v === undefined || v === null) ? '' : String(v);
            if (!s.trim()) continue;
            try { return decryptIfNeeded(s); } catch { return s; }
        }
        return null;
    };

    const instanceId  = pick(phone.instanceId, phone?.zapi?.instanceId, emp.instanceId, emp?.zapi?.instanceId, process.env.ZAPI_ID);
    const token       = pick(phone.token,      phone?.zapi?.token,      emp.token,      emp?.zapi?.token,      process.env.ZAPI_TOKEN);
    const clientToken = pick(phone.clientToken,phone?.zapi?.clientToken,emp.clientToken,emp?.zapi?.clientToken,process.env.ZAPI_CLIENT_TOKEN);

    logger.info('[botCreds]', {
        empresaId,
        phonePath: phoneDocRef.path,
        instanceIdPreview: instanceId ? String(instanceId).slice(0,6) + '…' : null,
        hasToken: !!token, hasClientToken: !!clientToken
    });

    return { instanceId, token, clientToken };
}

exports.processBotQueue = onSchedule(
    { schedule: 'every 1 minutes', secrets: [ZAPI_ENC_KEY] },
    async () => {
        logger.info('[processBotQueue] start');
        const nowTs = admin.firestore.Timestamp.now();

        let snap;
        try {
            snap = await db.collectionGroup('botQueue')
                .where('status', '==', 'pending')
                .where('runAt', '<=', nowTs)
                .orderBy('runAt', 'asc')
                .limit(100)
                .get();
        } catch (err) {
            const msg = String(err?.message || '');
            const idxUrl = msg.match(/https?:\/\/console\.firebase\.google\.com\/[^\s)]+/i)?.[0] || null;
            logger.error('[processBotQueue] query falhou — índice (status, runAt) necessário.', {
                code: err?.code, message: msg, indexUrl: idxUrl
            });
            return;
        }

        if (snap.empty) return;

        for (const doc of snap.docs) {
            const claimed = await db.runTransaction(async (tx) => {
                const fresh = await tx.get(doc.ref);
                const d = fresh.data() || {};
                const due = d.runAt?.toMillis?.() || 0;
                if (d.status !== 'pending' || due > Date.now()) return false;
                tx.update(doc.ref, {
                    status: 'processing',
                    processingAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                return true;
            }).catch(() => false);

            if (!claimed) continue;

            try {
                const parts = doc.ref.path.split('/');
                const empresaId = parts[1], phoneId = parts[3], chatId = parts[5];

                const { phoneDocRef, chatDocRef, msgsColRef } = getChatRefs(empresaId, phoneId, chatId);
                const { instanceId, token, clientToken } = await getZCredPlain(empresaId, phoneDocRef);
                if (!instanceId || !token || !clientToken) {
                    await doc.ref.set({ status: 'error', error: 'missing-credentials' }, { merge: true });
                    continue;
                }

                const job = doc.data() || {};
                if (job.type === 'burst') {
                    const seq = Array.isArray(job.items) ? job.items : [];
                    const gap = Number(job.defaultSpacingMs || 600);
                    for (let i = 0; i < seq.length; i++) {
                        const it = seq[i];
                        const wait = i === 0 ? 0 : (Number(it.delayMs) || gap);
                        if (wait > 0) await new Promise(r => setTimeout(r, wait));
                        await sendBotText(instanceId, token, clientToken, chatId, String(it.text || ''));
                        await logOut(msgsColRef, String(it.text || ''));
                    }
                    await doc.ref.set({ status: 'done', doneAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
                    continue;
                }

                if (job.type === 'timeout') {
                    const sessionRef = chatDocRef.collection('runtime').doc('bot');
                    const sSnap = await sessionRef.get();
                    const session = sSnap.data() || {};
                    if (!session.active) { await doc.ref.set({ status: 'skipped', reason: 'inactive' }, { merge: true }); continue; }
                    if (session.stepId !== job.stepId) { await doc.ref.set({ status: 'skipped', reason: 'moved-step' }, { merge: true }); continue; }
                    if ((session.lastUserAt || 0) > (job.runAt?.toMillis?.() || 0)) { await doc.ref.set({ status: 'skipped', reason: 'user-replied' }, { merge: true }); continue; }

                    const botSnap = await db.doc(`empresas/${empresaId}/chatbots/${session.botId}`).get();
                    if (!botSnap.exists) { await doc.ref.set({ status: 'error', error: 'bot-not-found' }, { merge: true }); continue; }

                    const bot = botSnap.data() || {};
                    const stepsArr = Array.isArray(bot.steps) ? bot.steps : [];
                    const steps    = indexById(stepsArr);
                    const startId  = job.nextId || steps[session.stepId]?.meta?.timeoutNext || 'end';
                    const walked   = walkUntilInteractive(steps, startId, session.vars, stepsArr);

                    await enqueueBurst({
                        empresaId, phoneId, chatId,
                        items: walked.outMsgs,
                        originStepId: walked.interactiveStep ? walked.interactiveStep.id : walked.finalStepId,
                        defaultSpacingMs: Number(bot.defaultSpacingMs || 1200)
                    });

                    const nextStep = walked.interactiveStep || steps[walked.finalStepId];
                    await sessionRef.set({
                        stepId: (nextStep && nextStep.id) || walked.finalStepId,
                        lastBotAt: Date.now(),
                    }, { merge: true });

                    const tmMin = Number(nextStep?.meta?.timeoutMinutes || 0);
                    const tmNext = nextStep?.meta?.timeoutNext || null;
                    if (tmMin > 0) {
                        await enqueueTimeout({ empresaId, phoneId, chatId, stepId: nextStep.id, nextId: tmNext, timeoutMinutes: tmMin });
                    }

                    await doc.ref.set({ status: 'done', doneAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
                    continue;
                }

                await doc.ref.set({ status: 'error', error: 'unknown-type' }, { merge: true });
            } catch (err) {
                await doc.ref.set({ status: 'error', error: String(err?.message || err) }, { merge: true });
            }
        }
    });


// Caminho de fila por chat
function botQueueCol(empresaId, phoneId, chatId) {
    return db.collection('empresas').doc(empresaId)
        .collection('phones').doc(phoneId)
        .collection('whatsappChats').doc(chatId)
        .collection('botQueue');
}

function asBurstItem(x) {
    if (!x) return null;
    if (typeof x === 'string') return { text: x, delayMs: 0 };
    if (typeof x.text === 'string') return { text: String(x.text), delayMs: Number(x.delayMs || 0) };
    return null;
}

// === ENFILERADOR DE UM ÚNICO ENVIO (com log por item) ===
async function enqueueSend({ empresaId, phoneId, chatId, text, delayMs = 0, originStepId = null }) {
    const runAt = admin.firestore.Timestamp.fromMillis(Date.now() + Math.max(0, delayMs));
    const payload = {
        type: 'send',
        text: String(text || ''),
        originStepId: originStepId || null,
        runAt,
        status: 'pending',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const ref = await botQueueCol(empresaId, phoneId, chatId).add(payload);
    logger.info('[enqueueSend]', {
        empresaId, phoneId, chatId, jobId: ref.id, originStepId,
        runAtIso: new Date(runAt.toMillis()).toISOString(),
        textPreview: String(text || '').slice(0, 120)
    });
}

async function enqueueBurst({ empresaId, phoneId, chatId, items, originStepId = null, defaultSpacingMs = 600 }) {
    const valid = (items || []).map(asBurstItem).filter(Boolean);

    if (valid.length === 0) {
        logger.info('[enqueueBurst] nada a enfileirar', { empresaId, phoneId, chatId, originStepId });
        return;
    }

    const runAt = admin.firestore.Timestamp.fromMillis(Date.now());
    const payload = {
        type: 'burst',
        items: valid,                                   // ✅ era seq
        originStepId: originStepId || null,
        defaultSpacingMs: Number(defaultSpacingMs || 600),
        runAt,
        status: 'pending',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const ref = await botQueueCol(empresaId, phoneId, chatId).add(payload);

    logger.info('[enqueueBurst] enfileirado', {
        empresaId, phoneId, chatId,
        jobId: ref.id,
        count: valid.length,                            // ✅ era seq.length
        originStepId,
        defaultSpacingMs: Number(defaultSpacingMs || 600),
    });
}

async function enqueueTimeout({ empresaId, phoneId, chatId, stepId, nextId, timeoutMinutes }) {
    const ms = Math.max(1, Number(timeoutMinutes || 0)) * 60 * 1000;
    const runAt = admin.firestore.Timestamp.fromMillis(Date.now() + ms);
    const payload = {
        type: 'timeout',
        stepId,
        nextId: nextId || null,
        runAt,
        status: 'pending',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await botQueueCol(empresaId, phoneId, chatId).add(payload);
    logger.info('[enqueueTimeout]', {
        empresaId, phoneId, chatId, stepId, nextId, timeoutMinutes,
        runAtIso: new Date(runAt.toMillis()).toISOString()
    });
}

function isQuestionText(t) {
    const s = String(t || '').trim();
    // considera "pergunta" se contém "?" em qualquer lugar (inclui pt-BR)
    return s.includes('?');
}

function truncateAtFirstQuestion(items) {
    const out = [];
    for (const it of items || []) {
        out.push(it);
        if (isQuestionText(it?.text)) break;
    }
    return out.length ? out : items;
}

async function maybeHandleByBot({ empresaId, phoneDoc, chatId, messageContent }) {
    logger.info('[maybeHandleByBot] start', { empresaId, phoneId: phoneDoc.id, chatId });

    const phoneId  = phoneDoc.id;
    const phoneData = phoneDoc.data() || {};
    const botCfg   = phoneData.chatbot || {};
    logger.info('[bot:cfg]', { chatId, enabled: !!botCfg.enabled, botId: botCfg.botId || null });

    if (!botCfg.enabled || !botCfg.botId) {
        logger.info('[bot:skip:cfg]', { chatId });
        return;
    }

    const empSnap  = await db.doc(`empresas/${empresaId}`).get();
    const empData  = empSnap.exists ? (empSnap.data() || {}) : {};
    const instanceId  = phoneData.instanceId  || empData.instanceId  || process.env.ZAPI_ID;
    const token       = phoneData.token       || empData.token       || process.env.ZAPI_TOKEN;
    const clientToken = phoneData.clientToken || empData.clientToken || process.env.ZAPI_CLIENT_TOKEN;

    logger.info('[bot:creds]', { chatId, hasInstance: !!instanceId, hasToken: !!token, hasClientToken: !!clientToken });
    if (!instanceId || !token || !clientToken) {
        logger.warn('[bot:skip:creds-missing]', { chatId });
        return;
    }

    const { chatDocRef } = getChatRefs(empresaId, phoneId, chatId);
    const sessionRef = chatDocRef.collection('runtime').doc('bot');

    // status do chat
    const chatSnap = await chatDocRef.get();
    const chatStatus = (chatSnap.data() || {}).status;
    logger.info('[bot:chat-status]', { chatId, status: chatStatus || 'undefined' });
    if (chatStatus === 'atendendo') {
        logger.info('[bot:skip:handoff]', { chatId });
        return;
    }

    // opt-out
    const optout = (botCfg.optOutKeywords || []).some(k =>
        (messageContent || '').toLowerCase().includes(String(k).toLowerCase())
    );
    logger.info('[bot:optout-check]', { chatId, matched: optout, keywords: botCfg.optOutKeywords || [] });
    if (optout) {
        await sessionRef.set({ active: false }, { merge: true });
        await chatDocRef.set({ status: 'atendendo' }, { merge: true });
        logger.info('[bot:optout:handoff]', { chatId });
        return;
    }

    // carrega BOT
    const botSnap = await db.doc(`empresas/${empresaId}/chatbots/${botCfg.botId}`).get();
    if (!botSnap.exists) {
        logger.warn('[bot:skip:bot-not-found]', { chatId, botId: botCfg.botId });
        return;
    }
    const bot = botSnap.data() || {};
    const stepsArr = Array.isArray(bot.steps) ? bot.steps : [];
    const steps    = indexById(stepsArr);

    // sessão
    const sessionSnap = await sessionRef.get();
    let session = sessionSnap.exists ? (sessionSnap.data() || {}) : {
        active: true,
        botId: botCfg.botId,
        stepId: bot.startStepId || 'start',
        vars: {},
        fallbackCount: 0,
    };
    logger.info('[bot:session]', {
        chatId,
        exists: sessionSnap.exists,
        active: !!session.active,
        stepId: session.stepId
    });

    // marca msg do usuário
    await sessionRef.set({ lastUserAt: Date.now() }, { merge: true });

    // horário comercial
    const closed = isClosed(bot.officeHours);
    logger.info('[bot:office-hours]', { chatId, configured: !!bot.officeHours?.enabled, closed });
    if (closed && bot.officeHours?.enabled) {
        const msg = bot.officeHours.closedMessage || 'Em breve responderemos.';
        logger.info('[bot:closed:send]', { chatId, preview: msg.slice(0,80) });
        await enqueueBurst({
            empresaId, phoneId, chatId,
            items: [{ text: msg }],
            originStepId: session.stepId,
            defaultSpacingMs: Number(bot.defaultSpacingMs || 1200),
        });
        return;
    }

    // ---------- PRIMEIRO TURNO ----------
    // ---------- PRIMEIRO TURNO ----------
    if (!sessionSnap.exists) {
        const walked = walkUntilInteractive(steps, session.stepId, session.vars, stepsArr);
        const intro  = normalizeBurst(bot.intro || bot.introBurst || bot.startBurst);

        const firstOutText  = (walked.outMsgs?.[0]?.text || '').trim();
        const greetingText  = (bot.greeting || '').trim();

        // Evita duplicar a saudação quando o 1º step já é uma mensagem interativa
        // ou quando a saudação é exatamente igual ao 1º texto do fluxo.
        const useGreeting =
            greetingText &&
            greetingText !== firstOutText &&
            !(walked.interactiveStep?.type === 'message');

        const itemsBeforeTrim = [
            ...(useGreeting ? [{ text: greetingText }] : []),
            ...intro,
            ...walked.outMsgs,
        ];

        const trimmed = truncateAtFirstQuestion(itemsBeforeTrim);

        await enqueueBurst({
            empresaId, phoneId, chatId,
            items: trimmed,
            originStepId: walked.interactiveStep ? walked.interactiveStep.id : walked.finalStepId,
            defaultSpacingMs: Number(bot.defaultSpacingMs || 1200),
        });

        const interactive = walked.interactiveStep || steps[walked.finalStepId];

        await sessionRef.set({
            ...session,
            stepId: interactive?.id || walked.finalStepId,
            startedAt: admin.firestore.FieldValue.serverTimestamp(),
            lastBotAt: Date.now(),
        }, { merge: true });

        const tmMin  = Number(interactive?.meta?.timeoutMinutes || 0);
        const tmNext = interactive?.meta?.timeoutNext || null;
        if (tmMin > 0) {
            await enqueueTimeout({ empresaId, phoneId, chatId, stepId: interactive.id, nextId: tmNext, timeoutMinutes: tmMin });
        }
        return;
    }

    // sessão existente mas inativa
    if (!session.active) {
        logger.info('[bot:skip:inactive-session]', { chatId });
        return;
    }

    // ---------- TURNOS SEGUINTES ----------
    const decision = computeNextStep(bot, session, messageContent, stepsArr);
    const items = (decision.outMessages || []).map(x => (typeof x === 'string' ? { text: x } : x));

    logger.info('[bot:turn]', {
        chatId,
        prevStepId: session.stepId,
        newStepId: decision.session.stepId,
        emitted: items.length,
        preview: items.map(i => i.text).slice(0,3)
    });

    await enqueueBurst({
        empresaId, phoneId, chatId,
        items,
        originStepId: decision.session.stepId,
        defaultSpacingMs: Number(bot.defaultSpacingMs || 1200)
    });

    await sessionRef.set(decision.session, { merge: true });

    const newStep = steps[decision.session.stepId];
    const tmMin = Number(newStep?.meta?.timeoutMinutes || 0);
    const tmNext = newStep?.meta?.timeoutNext || null;
    if (tmMin > 0) await enqueueTimeout({ empresaId, phoneId, chatId, stepId: newStep.id, nextId: tmNext, timeoutMinutes: tmMin });

    if (decision.handoff) {
        logger.info('[bot:handoff]', { chatId, to: 'atendendo' });
        await chatDocRef.set({ status: 'atendendo' }, { merge: true });
    }
}

function buildIntroBurst(bot, startId, vars) {
    const steps = indexById(bot.steps || []);
    const stepsOrder = bot.steps || [];
    const out = [];

    if (bot.greeting) out.push(bot.greeting);
    const intro = normalizeBurst(bot.intro || bot.introBurst || bot.startBurst);
    intro.forEach(m => out.push(m.text));

    const { outMsgs, finalStepId } = walkUntilInteractive(
        steps,
        startId || bot.startStepId || 'start',
        vars,
        stepsOrder
    );
    out.push(...outMsgs);

    if (out.length === 0 && !bot.greeting) out.push('Olá! 👋');
    return { outMsgs: out, finalStepId };
}

// ---------- helpers ----------
function isClosed(office) {
    if (!office?.enabled) return false;
    try {
        const tz = office.tz || 'America/Sao_Paulo';
        const now = new Date();
        const day = ['sun','mon','tue','wed','thu','fri','sat'][now.getDay()];
        const rule = office[day];
        if (!rule) return true;
        const [hs, ms] = rule.start.split(':').map(Number);
        const [he, me] = rule.end.split(':').map(Number);
        const start = new Date(now); start.setHours(hs, ms, 0, 0);
        const end   = new Date(now); end.setHours(he, me, 0, 0);
        return !(now >= start && now <= end);
    } catch { return false; }
}

function render(txt, vars) {
    return String(txt || '').replace(/\{\{\s*([\w.]+)\s*\}\}/g, (_, k) => vars?.[k] ?? '');
}
function nextIdByOrder(stepsOrder, currentId) {
    const arr = Array.isArray(stepsOrder) ? stepsOrder : [];
    const idx = arr.findIndex(s => s && s.id === currentId);
    if (idx === -1) return arr[0]?.id || null;           // se não achar, volta ao primeiro
    return arr[idx + 1]?.id || null;                     // próximo da lista (ex.: 0 → 1)
}

function emitSingleStep(stepsById, stepId, vars) {
    if (!stepId) return [];
    const step = stepsById[stepId];
    if (!step) return [];
    const t = String(step.type || '').toLowerCase();
    const out = [];

    // pre/preamble (se você usa)
    normalizeBurst(step.pre || step.preamble || step.preMessages).forEach(m => out.push(m));

    if (t === 'menu') {
        const ask = getMenuAsk(step); if (ask) out.push({ text: render(ask, vars) });
        return out;
    }
    if (t === 'form') {
        const ask = getFormAsk(step, vars); if (ask) out.push({ text: render(ask, vars) });
        return out;
    }
    if (t === 'capture') {
        const ask = getCaptureAsk(step); if (ask) out.push({ text: render(ask, vars) });
        return out;
    }
    if (t === 'message') {
        const txt = (step.text || '').toString().trim();
        if (txt) out.push({ text: render(txt, vars) });
        return out;
    }
    return out;
}

// Decide a próxima etapa (menu, form, capture, message, end)
function computeNextStep(bot, session, userText, stepsArr) {
    const steps = indexById(stepsArr);
    const cur   = steps[session.stepId] || { id: 'end', type: 'end' };
    const outMessages = [];
    let handoff = false;

    const clean = String(userText || '').trim();
    const fallbackNext = cur.next || nextIdByOrder(stepsArr, cur.id) || 'end';

    let nextId = 'end';
    let nextSession = session;

    if (cur.type === 'menu') {
        const opts = Array.isArray(cur.options) ? cur.options : [];
        const chosen = opts.find(o => String(o.key).toLowerCase() === clean.toLowerCase());
        if (!chosen) {
            const fb = bot?.fallback?.message || 'Não entendi. Responda com uma das opções.';
            outMessages.push({ text: fb });
            logger.info('[computeNextStep:menu:no-match]', { stepId: cur.id, user: clean, options: opts.map(o=>o.key) });
            return { outMessages, handoff: false, session: { ...session, fallbackCount: (session.fallbackCount || 0) + 1 } };
        }
        nextId = chosen.next || fallbackNext;

    } else if (cur.type === 'capture') {
        const targetVar = cur.var || cur.name || cur.field || 'lastInput';
        const vars = { ...(session.vars || {}), [targetVar]: clean };
        nextSession = { ...session, vars };
        nextId = fallbackNext;

    } else if (cur.type === 'form') {
        const fields = Array.isArray(cur.fields) ? cur.fields : [];
        // acha o próximo campo pendente
        const pending = fields.find(f => !(session.vars || {})[f.name]);
        if (pending) {
            // grava a resposta do usuário no campo pendente atual
            const vars = { ...(session.vars || {}), [pending.name]: clean };
            nextSession = { ...session, vars };
            // vê se ainda resta algum campo
            const still = fields.find(f => !(vars)[f.name]);
            if (still) {
                // fica no mesmo step e pergunta o próximo campo (walkUntilInteractive vai emitir o ask do form)
                nextId = cur.id;
            } else {
                // formulário concluído
                nextId = fallbackNext;
            }
        } else {
            // não havia pendências -> avança
            nextId = fallbackNext;
        }

    } else if (cur.type === 'message') {
        nextId = fallbackNext;

    } else {
        nextId = fallbackNext;
    }

    const walked = walkUntilInteractive(steps, nextId, nextSession.vars, stepsArr);
    outMessages.push(...walked.outMsgs);

    const nextInteractive = walked.interactiveStep || steps[walked.finalStepId];
    const newStepId = nextInteractive?.id || walked.finalStepId || 'end';

    if (outMessages.length === 0) {
        outMessages.push({ text: bot?.fallback?.noNextMessage || 'Perfeito, obrigado! 👌' });
    }

    logger.info('[computeNextStep]', {
        curId: cur.id, curType: cur.type,
        user: clean,
        chosenNextId: nextId,
        emitted: outMessages.length,
        newStepId
    });

    return {
        outMessages,
        handoff,
        session: {
            ...nextSession,
            stepId: newStepId,
            lastBotAt: Date.now(),
            fallbackCount: 0
        }
    };
}

function indexById(arr) {
    const m = {};
    for (const it of Array.isArray(arr) ? arr : []) {
        if (it && it.id) m[it.id] = it;
    }
    return m;
}

async function sendBotText(instanceId, token, clientToken, chatId, text) {
    const digits = (s) => String(s || '').replace(/\D/g,'');
    const phoneDigits = digits(chatId);
    const headers = { 'client-token': clientToken };
    const payload = { phone: phoneDigits, message: String(text || '') };
    await callZ(instanceId, token, '/send-text', payload, headers, 15000);
}

async function logOut(msgsColRef, content) {
    await msgsColRef.add({
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        fromMe: true,
        type: 'text',
        content: String(content || ''),
        status: 'sent',
        read: false,
        meta: { by: 'bot' }
    });
}

function asArray(x) {
    if (!x) return [];
    return Array.isArray(x) ? x : [x];
}

function normalizeBurst(b) {
    if (!Array.isArray(b)) return [];
    return b.map(x => (typeof x === 'string')
        ? ({ text: x, delayMs: 0 })
        : ({ text: String(x?.text || ''), delayMs: Number(x?.delayMs || 0) }));
}

function getPreMessages(step) {
    // suporte a chaves equivalentes
    return normalizeBurst(step?.pre || step?.preamble || step?.preMessages);
}

function getMenuAsk(step) {
    return step?.text || null;
}

function getFormAsk(step, vars) {
    // pega o próximo campo pendente
    const nextField = (step?.fields || []).find(f => !(vars || {})[f.name]);
    return nextField?.ask || null;
}

function getCaptureAsk(step) {
    return step?.ask || null;
}

function walkUntilInteractive(steps, startId, vars = {}, stepsArr = []) {
    const outMsgs = [];
    const seen = new Set();
    let curId = startId;
    let interactiveStep = null;
    let finalStepId = startId;

    const isInteractiveMessage = (s) =>
        s?.type === 'message' && Number(s?.meta?.timeoutMinutes || 0) > 0;

    while (curId && steps[curId] && !seen.has(curId)) {
        seen.add(curId);
        const s = steps[curId];
        finalStepId = s.id;

        if (s.type === 'end') {
            break;
        }

        if (s.type === 'menu') {
            if (s.text) outMsgs.push({ text: s.text });
            interactiveStep = s;
            break;
        }

        if (s.type === 'capture') {
            if (s.ask) outMsgs.push({ text: s.ask });
            interactiveStep = s;
            break;
        }

        if (s.type === 'form') {
            const ask = getFormAsk(s, vars);
            if (ask) outMsgs.push({ text: ask });
            interactiveStep = s; // form é interativo (espera resposta)
            break;
        }

        if (s.type === 'message') {
            if (s.text) outMsgs.push({ text: s.text });
            if (isInteractiveMessage(s)) {
                interactiveStep = s;
                break;
            }
            curId = s.next || 'end';
            continue;
        }

        // tipos desconhecidos: protege
        curId = s.next || 'end';
    }

    return { outMsgs, interactiveStep, finalStepId };
}