const {onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require('firebase-functions/v2/scheduler');
const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } = require('firebase-functions/v2/firestore');
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