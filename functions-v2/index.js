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

function buildSqsClient() {
    return new SQSClient({
        region: process.env.AWS_REGION || "us-east-2",
        credentials: {
            accessKeyId: process.env.AWS_ACCESS_KEY_ID,
            secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
        },
    });
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
            const msg  = event.data?.data() ?? {};

            /* 1. ignora mensagens enviadas pelo operador */
            if (msg.fromMe) return;

            /* 2. corpo do push */
            const isText = (msg.type ?? 'text') === 'text';
            const body   = isText
                ? (msg.content ?? '').substring(0, 40)
                : `📎 ${(msg.type ?? 'arquivo')[0].toUpperCase()}${(msg.type ?? 'arquivo').slice(1)} recebido`;

            /* 3. coleta tokens */
            const tokens = new Set();

            const empresaSnap = await db.doc(`empresas/${empresaId}`).get();
            empresaSnap.exists && empresaSnap.data().fcmToken && tokens.add(empresaSnap.data().fcmToken);

            const usersSnap = await db.collection('users').where('createdBy', '==', empresaId).get();
            usersSnap.forEach(d => d.data().fcmToken && tokens.add(d.data().fcmToken));

            const tokenArr = [...tokens].filter(Boolean);
            if (!tokenArr.length) return;

            /* 4. payload */
            const notif = {                     // será usado só se o SO precisar
                title : msg.senderName || 'Novo lead',
                body,
            };
            const data = {
                empresaId : empresaId,
                phoneId   : phoneId,
                chatId    : chatId,
                openChat  : 'true',
                chatName  : nomeContato,          // opcional
                contactPhoto: fotoContato,        // opcional
                click_action: 'FLUTTER_NOTIFICATION_CLICK'   // <- aqui
            };

            const message = {
                token,
                notification: { title: '...', body: '...' },
                data,                       //  ← inclui a action no mesmo objeto
                android: { priority: 'high' }
            };

            /* 5. dispara em lotes de 500 */
            const chunks = [];
            for (let i=0;i<tokenArr.length;i+=500) chunks.push(tokenArr.slice(i,i+500));

            for (const chunk of chunks) {
                const messages = chunk.map(token => ({
                    token,
                    notification: notif,
                    data,                       // ← só data
                    android : { priority:'high' },
                    apns    : { headers:{ 'apns-priority':'10' } },
                }));

                await admin.messaging().sendEach(messages);   // <-- devolve promise
            }

            const res = await admin.messaging().sendEach(messages);
            console.log(
                `push chat:${chatId} – ok:${res.successCount} nok:${res.failureCount}`,
            );
        } catch (err) {
            console.error('Erro push mensagem:', err);
        }
    },
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

async function getPhoneCtxByInstance(instanceId) {
    const snap = await db
        .collectionGroup('phones')
        .where('instanceId', '==', instanceId)
        .limit(1)
        .get();

    if (snap.empty) throw new Error(`instance ${instanceId} não cadastrado`);

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
        if (data?.ack === 'read' && data.id && data.phone) {
            const phoneDigits = digits(data.phone);
            const zapiId      = data.id;

            const { empresaId, phoneDoc } = await getPhoneCtxByNumber(phoneDigits);
            const phoneId = phoneDoc.id;                       // NEW → 554691395827
            const { chatDocRef, msgsColRef } = getChatRefs(
                empresaId,
                phoneId,
                phoneDigits + '@s.whatsapp.net',
            );

            const snap  = await msgsColRef.where('zapiId','==', zapiId).get();
            const batch = admin.firestore().batch();
            snap.docs.forEach(d =>
                batch.set(d.ref, { read: true, status: 'read' }, { merge: true })
            );
            await batch.commit();
            return res.status(200).send('ACK de leitura processado');
        }

        /* ───── 2. Callback de mensagem recebida ───── */
        if (data?.type === 'ReceivedCallback') {
            /* a) dados do remetente (cliente) */
            const remoteDigits = digits(data.phone);           // 55…      ← cliente
            const chatId       = remoteDigits + '@s.whatsapp.net';

            /* b) descobre qual é o SEU número-empresa pelo instanceId */
            const { empresaId, phoneDoc } =
                await getPhoneCtxByInstance(data.instanceId);  // helper
            const phoneId = phoneDoc.id;                         // ex.: 554691395827

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

exports.sendMessage = onRequest(async (req, res) => {
    // Cabeçalhos CORS
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");

    if (req.method === "OPTIONS") {
        return res.status(204).send("");
    }

    logger.info("sendMessage function called", {method: req.method, body: req.body});

    // Se o payload tiver um campo "type", trata-se de callback – ignora
    if (req.body.type) {
        logger.warn("Ignorando payload de callback", {type: req.body.type});
        return res.status(200).send("Callback ignorado");
    }

    if (req.method !== "POST") {
        logger.warn("Método não permitido", {method: req.method});
        return res.status(405).send("Method Not Allowed");
    }

    try {
        // Espera os seguintes campos: chatId, message (legenda para mídias), fileType e fileData
        const {empresaId, phoneId, chatId, message, fileType, fileData, clientMessageId} = req.body;

        const { phoneDocRef, chatDocRef, msgsColRef } =
                         getChatRefs(empresaId, phoneId, chatId);

        if (!chatId || (!message && !fileData && fileType !== "read")) {          /* ← ajustado */
            logger.warn("Parâmetros ausentes", {chatId, message, fileData, clientMessageId});
            return res.status(400).send("Faltam parâmetros");
        }

        // Idempotência: gera um identificador único se não fornecido
        const uniqueId = clientMessageId || `${chatId}_${Date.now()}`;

        // Recupera as variáveis de ambiente
        const phoneData  = (await phoneDocRef.get()).data() || {};
        const instanceId = phoneData.instanceId   || process.env.ZAPI_ID;
        const token      = phoneData.token        || process.env.ZAPI_TOKEN;
        const clientToken= phoneData.clientToken  || process.env.ZAPI_CLIENT_TOKEN;
        if (!instanceId || !token) {
            logger.error("Variáveis de ambiente ZAPI_ID ou ZAPI_TOKEN não definidas");
            return res.status(500).send("Configuração do backend incorreta");
        }
        if (!clientToken) {
            logger.error("Variável de ambiente ZAPI_CLIENT_TOKEN não definida");
            return res.status(500).send("Client-Token não definido na configuração do backend");
        }
        logger.info("Valores das variáveis de ambiente", {instanceId, token, clientToken});

        /* ─────────────────────────────
         *  SUPORTE A fileType === "read"
         * ───────────────────────────── */
        if (fileType === "read") {
            const phoneDigits = chatId.replace(/\D/g, '');
            const modifyUrl   = `https://api.z-api.io/instances/${instanceId}/token/${token}/modify-chat`;
            const modifyPayload = { phone: phoneDigits, action: "read" };

            logger.info("Marcando chat como lido via Z-API", { modifyUrl, modifyPayload });

            await axios.post(
                modifyUrl,
                modifyPayload,
                { headers: { "Content-Type": "application/json", "Client-Token": clientToken } }
            );

            // zera contador + marca todas as mensagens como lidas no Firestore
            const { phoneDocRef, chatDocRef, msgsColRef } = getChatRefs(empresaId, phoneId, chatId);
            const unreadSnap = await msgsColRef
                     .where("read","==",false).get();

            const batch = admin.firestore().batch();
            unreadSnap.docs.forEach(d => batch.set(d.ref, { read: true }, { merge: true }));
            batch.set(chatDocRef, { unreadCount: 0 }, { merge: true });
            await batch.commit();

            return res.status(200).send({ value: true });
        }

        // Define o endpoint e payload com base no fileType
        let endpoint = "";
        let payload = {};
        if (fileType === "image") {
            endpoint = "/send-image";
            // Se o fileData não contiver o prefixo "data:image", adiciona-o (assumindo JPEG; adapte conforme necessário)
            let imageData = fileData;
            if (!fileData.startsWith("data:image/")) {
                imageData = "data:image/jpeg;base64," + fileData;
            }
            payload = {phone: chatId, image: imageData, message: message};
        } else if (fileType === "audio") {
            endpoint = "/send-audio";
            // Se o fileData não iniciar com "data:audio/", adicione o prefixo (aqui assumimos audio/mp4; ajuste se necessário)
            let audioData = fileData;
            if (!fileData.startsWith("data:audio/")) {
                audioData = "data:audio/mp4;base64," + fileData;
            }
            payload = {phone: chatId, audio: audioData, message: message};
        } else if (fileType === "video") {
            endpoint = "/send-video";
            payload = {phone: chatId, video: fileData, message: message};
        } else {
            endpoint = "/send-text";
            payload = {phone: chatId, message: message};
        }

        const zApiUrl = `https://api.z-api.io/instances/${instanceId}/token/${token}${endpoint}`;
        logger.info("Enviando mensagem via Z-API", {url: zApiUrl, chatId, payload});

        const zApiResponse = await axios.post(
            zApiUrl,
            payload,
            {
                headers: {
                    "Content-Type": "application/json",
                    "Client-Token": clientToken
                }
            }
        );
        logger.info("Resposta da Z-API", {data: zApiResponse.data});

        if (clientMessageId) {
            const existingMessages = await msgsColRef
                .where("clientMessageId","==",uniqueId).get();
            if (!existingMessages.empty) {
                logger.warn("Mensagem duplicada detectada", {clientMessageId: uniqueId});
                return res.status(200).send(zApiResponse.data);
            }
        }

        // Prepara os dados para salvar no Firestore

        const zMsgId = zApiResponse.data.messageId       // send-text / send-image …
                        || zApiResponse.data.msgId           // send-audio / outros
                        || zApiResponse.data.id;             // fallback (caso antigo)

        const firestoreData = {
            timestamp        : admin.firestore.FieldValue.serverTimestamp(),
            fromMe           : true,
            sender           : zApiResponse.data.sender || null,
            clientMessageId  : uniqueId,
            zapiId          : zMsgId || null,                // ← agora sempre coincide
            status           : 'sent',                       // delivered/read virão via webhook
            read             : false,
            type             : (fileType && fileType !== "text") ? fileType : "text",
            content          : (fileType && fileType !== "text") ? fileData : message,
        };

        if (fileType && fileType !== "text") {
            firestoreData.content = fileData; // Salva o valor original (sem prefixo) ou, se preferir, o imageData
            firestoreData.caption = message;   // Legenda
        } else {
            firestoreData.content = message;
        }

        await msgsColRef.add(firestoreData);

        await chatDocRef.set({
            chatId: chatId,
            lastMessage: (fileType && fileType !== "text" && message) ? message : firestoreData.content,
            lastMessageTime: admin.firestore.FieldValue.serverTimestamp(),
            type: firestoreData.type, // <-- Aqui o type que você definiu em firestoreData
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});

        return res.status(200).send(zApiResponse.data);
    } catch (error) {
        logger.error("Erro ao enviar mensagem:", error.response ? error.response.data : error);
        return res
            .status(500)
            .send(error.response ? error.response.data : error.toString());
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
    { cors: true, invoker: 'public' },
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
        const { phoneDocRef } = getChatRefs(empresaId, phoneId, phoneId);
        const phoneData = (await phoneDocRef.get()).data() || {};
        const ZAPI_ID           = phoneData.instanceId   || process.env.ZAPI_ID;
        const ZAPI_TOKEN        = phoneData.token        || process.env.ZAPI_TOKEN;
        const ZAPI_CLIENT_TOKEN = phoneData.clientToken  || process.env.ZAPI_CLIENT_TOKEN;

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
async function getCred(empresaId, phoneId){
    const snap = await db.doc(`empresas/${empresaId}/phones/${phoneId}`).get();
    if(!snap.exists) throw new Error('phone not found');
    const d = snap.data();
    return { instanceId:d.instanceId, token:d.token, clientToken:d.clientToken };
}

/* ========== 1. QR-Code (base64) ========== */
exports.getQr = onRequest(async (req,res)=>{
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
exports.getPhoneCode = onRequest(async (req,res)=>{
    try{
        const {empresaId, phoneId, phone} = req.body;
        const {instanceId, token, clientToken} = await getCred(empresaId,phoneId);

        const url=`https://api.z-api.io/instances/${instanceId}/token/${token}/phone-code/${phone}`;
        const z = await axios.get(url,{ headers:{'Client-Token':clientToken} });

        res.json({code:z.data.code});
    }catch(e){ console.error(e); res.status(500).json({error:e.message});}
});

/* ========== 3. Status de conexão ========== */
exports.getConnectionStatus = onRequest(async (req,res)=>{
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

exports.updateContactPhotos = onRequest(async (req, res) => {
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

        const { instanceId, token, clientToken } = phoneSnap.data();
        if (!instanceId || !token || !clientToken) {
            throw new Error('Credenciais Z‑API ausentes no documento phone');
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
            const zUrl = `https://api.z-api.io/instances/${instanceId}/token/${token}` +
                `/contacts/profile-picture/${phoneDigits}`;

            try {
                const zRes = await axios.get(zUrl, { headers: { 'Client-Token': clientToken } });
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

//FIM DAS FUNCTIONS PARA ATUALIZAR TEMPO DE ATENDIMENTO

