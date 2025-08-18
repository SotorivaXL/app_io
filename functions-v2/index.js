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

    const keyB64 = ZAPI_ENC_KEY.value();
    if (!keyB64) throw new Error('ZAPI_ENC_KEY não configurada');
    const key = Buffer.from(keyB64, 'base64'); // 32 bytes

    const tryAesGcm = (iv, ct, tag) => {
        try {
            const dec = crypto.createDecipheriv('aes-256-gcm', key, iv);
            dec.setAuthTag(tag);
            return Buffer.concat([dec.update(ct), dec.final()]).toString('utf8');
        } catch {
            return null;
        }
    };

    // Novo formato com prefixo: enc:v1: base64( iv | ct | tag )
    if (value.startsWith('enc:v1:')) {
        const buf = Buffer.from(value.slice(7), 'base64');
        if (buf.length < 12 + 16 + 1) throw new Error('cipher muito curto (v1)');
        const iv  = buf.subarray(0, 12);
        const ct  = buf.subarray(12, buf.length - 16);
        const tag = buf.subarray(buf.length - 16);
        const out = tryAesGcm(iv, ct, tag);
        if (out !== null) return out;
        throw new Error(`Falha ao descriptografar (v1) ${fieldName || ''}`.trim());
    }

    // Sem prefixo: tente AMBOS os layouts: (iv|ct|tag) e (iv|tag|ct)
    try {
        const b = Buffer.from(value, 'base64');
        if (b.length >= 12 + 16 + 1) {
            // (a) iv | ct | tag
            const ivA  = b.subarray(0, 12);
            const ctA  = b.subarray(12, b.length - 16);
            const tagA = b.subarray(b.length - 16);
            const outA = tryAesGcm(ivA, ctA, tagA);
            if (outA !== null) return outA;

            // (b) iv | tag | ct (legado)
            const ivB  = b.subarray(0, 12);
            const tagB = b.subarray(12, 28);
            const ctB  = b.subarray(28);
            const outB = tryAesGcm(ivB, ctB, tagB);
            if (outB !== null) return outB;
        }
    } catch {
        // cai para plaintext
    }

    // Plaintext (nada a decriptar)
    return value;
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
        if (data?.type === 'ReceivedCallback') {
            const digits = (n) => (n || '').toString().replace(/\D/g, '');
            const remoteDigits   = digits(data.phone);            // cliente
            const serverDigits   = digits(data.connectedPhone);   // seu número-empresa
            const chatId         = remoteDigits + '@s.whatsapp.net';

            let empresaId, phoneDoc;
            try {
                ({ empresaId, phoneDoc } = await getPhoneCtxByInstance(data.instanceId));
            } catch (e) {
                // fallback: usa o número-empresa (connectedPhone)
                if (!serverDigits) throw e;
                ({ empresaId, phoneDoc } = await getPhoneCtxByNumber(serverDigits));
            }

            const phoneId  = phoneDoc.id;
            const chatName = data.chatName || data.senderName || remoteDigits;

            /* c) tipo + conteúdo ------------------------------------------------ */
            let messageContent = '';
            let messageType    = 'text';
            if      (data.text?.message)       { messageContent = data.text.message;       }
            else if (data.audio?.audioUrl)     { messageContent = data.audio.audioUrl;     messageType = 'audio'; }
            else if (data.image?.imageUrl)     { messageContent = data.image.imageUrl;     messageType = 'image'; }
            else if (data.video?.videoUrl)     { messageContent = data.video.videoUrl;     messageType = 'video'; }
            else if (data.sticker?.stickerUrl) { messageContent = data.sticker.stickerUrl; messageType = 'sticker'; }

            /* d) refs Firestore -------------------------------------------------- */
            const { chatDocRef, msgsColRef } = getChatRefs(empresaId, phoneId, chatId);
            const msgDocRef = msgsColRef.doc();

            await msgDocRef.set({
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

            await admin.firestore().runTransaction(async (tx) => {
                const snap = await tx.get(chatDocRef);
                const cur  = snap.exists ? snap.data() : {};
                const curStatus = cur?.status ?? 'novo';

                // ─── status que NÃO devem voltar para “novo” ───
                const preserve = ['atendendo'];

                const newStatus = preserve.includes(curStatus) ? curStatus : 'novo';

                /* histórico se estiver finalizado ---------------------------------- */
                if (['concluido_com_venda', 'recusado'].includes(curStatus)) {
                    await chatDocRef.collection('history').add({
                        status    : curStatus,
                        saleValue : cur.saleValue ?? null,
                        changedAt : admin.firestore.FieldValue.serverTimestamp(),
                        updatedBy : 'system',                       // ou outro identificador
                    });
                }

                /* atualiza / cria o doc principal ---------------------------------- */
                tx.set(
                    chatDocRef,
                    {
                        chatId,
                        arrivalAt : cur.arrivalAt ?? admin.firestore.FieldValue.serverTimestamp(),
                        name         : chatName,
                        contactPhoto : data.senderPhoto || data.photo || '',
                        lastMessage  : messageContent,
                        lastMessageTime : new Date().toLocaleTimeString(
                            'pt-BR', { hour:'2-digit', minute:'2-digit' }),
                        type       : messageType,
                        timestamp  : admin.firestore.FieldValue.serverTimestamp(),
                        status     : newStatus,        // <<<<<  usa newStatus calculado
                        saleValue  : newStatus === 'novo' ? null : cur.saleValue ?? null,
                        ...(data.fromMe
                            ? {}
                            : { unreadCount: admin.firestore.FieldValue.increment(1) }),
                    },
                    { merge: true },
                );
            });
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
        instanceId : decryptIfNeeded(d.instanceId),
        token      : decryptIfNeeded(d.token),
        clientToken: decryptIfNeeded(d.clientToken),
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
            instanceId : decryptIfNeeded(instanceId),
            token      : decryptIfNeeded(token),
            clientToken: decryptIfNeeded(clientToken),
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