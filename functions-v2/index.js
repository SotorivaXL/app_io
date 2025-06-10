const {onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
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
app.use(cors({ origin: true }));
const { defineSecret } = require('firebase-functions/params');
const { SQSClient, SendMessageCommand } = require("@aws-sdk/client-sqs");

const sqsClient = new SQSClient({
    region: process.env.AWS_REGION || "us-east-2",
    credentials: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
    },
});

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

exports.sendNewLeadNotification = onDocumentCreated(
    'empresas/{empresaId}/campanhas/{campanhaId}/leads/{leadId}',
    async (event) => {
        try {
            console.log("Função sendNewLeadNotification iniciada.");

            // Obtenha o snapshot e os parâmetros do evento
            const snap = event.data;
            const { empresaId, campanhaId, leadId } = event.params;

            // Busca o documento da campanha
            const campanhaDoc = await admin.firestore()
                .collection('empresas')
                .doc(empresaId)
                .collection('campanhas')
                .doc(campanhaId)
                .get();

            if (!campanhaDoc.exists) {
                console.error(`Campanha com ID ${campanhaId} não encontrada para a empresa ${empresaId}`);
                return;
            }

            const nomeCampanha = campanhaDoc.data().nome_campanha;
            const tokensSet = new Set();

            // Adiciona token da empresa, se existir
            const empresaDoc = await admin.firestore()
                .collection('empresas')
                .doc(empresaId)
                .get();
            if (empresaDoc.exists && empresaDoc.data().fcmToken) {
                tokensSet.add(empresaDoc.data().fcmToken);
            }

            // Adiciona tokens dos usuários vinculados à empresa
            const usersSnapshot = await admin.firestore()
                .collection('users')
                .where('createdBy', '==', empresaId)
                .get();
            usersSnapshot.forEach(userDoc => {
                if (userDoc.data().fcmToken) {
                    tokensSet.add(userDoc.data().fcmToken);
                }
            });

            const tokens = Array.from(tokensSet).filter(token => token);
            if (tokens.length === 0) {
                console.log(`Nenhum token válido encontrado para a empresa ${empresaId}.`);
                return;
            }

            // Prepara o payload da notificação
            const payload = {
                notification: {
                    title: 'Novo Lead!',
                    body: `Você tem um novo lead na campanha ${nomeCampanha}`,
                },
                data: {
                    leadId: String(leadId),
                    campanhaId: String(campanhaId),
                    empresaId: String(empresaId),
                },
            };

            // Cria um array de mensagens, uma para cada token
            const messages = tokens.map(token => ({
                token,
                notification: payload.notification,
                data: payload.data,
            }));

            // Loga o array de mensagens para depuração
            console.log("Array de mensagens a ser enviado:", JSON.stringify(messages, null, 2));

            // Envia as mensagens utilizando sendEach
            console.log("Enviando mensagem...");
            const response = await admin.messaging().sendEach(messages);
            console.log(`Resposta do sendEach: ${JSON.stringify(response, null, 2)}`);

            console.log(`${response.successCount} notificações enviadas com sucesso.`);
            if (response.failureCount > 0) {
                response.responses.forEach((resp, idx) => {
                    if (!resp.success) {
                        console.error(`Erro ao enviar para o token ${messages[idx].token}: ${resp.error.message}`);
                    }
                });
            }
        } catch (error) {
            console.error('Erro ao enviar notificação:', error);
            if (error.errorInfo) {
                console.error("Detalhes do error.errorInfo:", JSON.stringify(error.errorInfo, null, 2));
            }
            console.error("Stack Trace:", error.stack);
            return;
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

exports.zApiWebhook = onRequest(async (req, res) => {
    try {
        logger.info("Recebido webhook da Z-API:", req.body);
        const data = req.body;

        // Processa somente se for callback de mensagem recebida
        if (data && data.type === "ReceivedCallback") {
            // "phone" é usado como chatId
            const chatId = data.phone;

            // Determina o nome do chat: usa data.chatName se disponível, senão data.senderName, senão o chatId
            const chatName = data.chatName || data.senderName || chatId;

            // Define o conteúdo e o tipo da mensagem conforme os campos disponíveis
            let messageContent = "";
            let messageType = "text";
            if (data.text && data.text.message) {
                messageContent = data.text.message;
                messageType = "text";
            } else if (data.audio && data.audio.audioUrl) {
                messageContent = data.audio.audioUrl;
                messageType = "audio";
            } else if (data.image && data.image.imageUrl) {
                messageContent = data.image.imageUrl;
                messageType = "image";
            } else if (data.video && data.video.videoUrl) {
                messageContent = data.video.videoUrl;
                messageType = "video";
            } if (data.sticker && data.sticker.stickerUrl) {
                messageContent = data.sticker.stickerUrl;
                messageType = "sticker";
            }

            // Converte o campo "momment" (milissegundos) para um horário formatado "HH:MM"
            let formattedTime = "";
            if (data.momment) {
                const dateObj = new Date(data.momment);
                const hours = dateObj.getHours().toString().padStart(2, '0');
                const minutes = dateObj.getMinutes().toString().padStart(2, '0');
                formattedTime = `${hours}:${minutes}`;
            } else {
                const now = new Date();
                formattedTime = `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}`;
            }

            // Sender e foto: para grupos, utiliza participantPhone; caso contrário, usa phone
            const sender = data.participantPhone || data.phone;
            const senderName = data.senderName || "";
            const senderPhoto = data.senderPhoto || data.photo || "";

            const chatDocRef = admin.firestore().collection("whatsappChats").doc(chatId);
            const msgDocRef = chatDocRef.collection("messages").doc();

            // Salva a mensagem recebida
            await msgDocRef.set({
                content: messageContent,
                type: messageType,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                fromMe: data.fromMe === true,
                sender: sender,
                senderName: senderName,
                senderPhoto: senderPhoto,
            });

            // Atualiza o documento do chat com as informações úteis
            const updateData = {
                chatId: chatId,
                name: chatName,
                contactPhoto: senderPhoto,
                lastMessage: messageContent,
                lastMessageTime: formattedTime,
                type: messageType,  // <-- Adiciona aqui o tipo da mensagem
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
            };
            if (data.fromMe !== true) {
                updateData.unreadCount = admin.firestore.FieldValue.increment(1);
            }
            await chatDocRef.set(updateData, { merge: true });
        }

        res.status(200).send("OK");
    } catch (error) {
        logger.error("Erro no webhook Z-API:", error);
        res.status(500).send("Erro interno");
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

    logger.info("sendMessage function called", { method: req.method, body: req.body });

    // Se o payload tiver um campo "type", trata-se de callback – ignora
    if (req.body.type) {
        logger.warn("Ignorando payload de callback", { type: req.body.type });
        return res.status(200).send("Callback ignorado");
    }

    if (req.method !== "POST") {
        logger.warn("Método não permitido", { method: req.method });
        return res.status(405).send("Method Not Allowed");
    }

    try {
        // Espera os seguintes campos: chatId, message (legenda para mídias), fileType e fileData
        const { chatId, message, fileType, fileData, clientMessageId } = req.body;
        if (!chatId || (!message && !fileData)) {
            logger.warn("Parâmetros ausentes", { chatId, message, fileData, clientMessageId });
            return res.status(400).send("Faltam parâmetros");
        }

        // Idempotência: gera um identificador único se não fornecido
        const uniqueId = clientMessageId || `${chatId}_${Date.now()}`;

        // Recupera as variáveis de ambiente
        const instanceId = process.env.ZAPI_ID;
        const token = process.env.ZAPI_TOKEN;
        const clientToken = process.env.ZAPI_CLIENT_TOKEN;
        if (!instanceId || !token) {
            logger.error("Variáveis de ambiente ZAPI_ID ou ZAPI_TOKEN não definidas");
            return res.status(500).send("Configuração do backend incorreta");
        }
        if (!clientToken) {
            logger.error("Variável de ambiente ZAPI_CLIENT_TOKEN não definida");
            return res.status(500).send("Client-Token não definido na configuração do backend");
        }
        logger.info("Valores das variáveis de ambiente", { instanceId, token, clientToken });

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
            payload = { phone: chatId, image: imageData, message: message };
        } else if (fileType === "audio") {
            endpoint = "/send-audio";
            // Se o fileData não iniciar com "data:audio/", adicione o prefixo (aqui assumimos audio/mp4; ajuste se necessário)
            let audioData = fileData;
            if (!fileData.startsWith("data:audio/")) {
                audioData = "data:audio/mp4;base64," + fileData;
            }
            payload = { phone: chatId, audio: audioData, message: message };
        } else if (fileType === "video") {
            endpoint = "/send-video";
            payload = { phone: chatId, video: fileData, message: message };
        } else {
            endpoint = "/send-text";
            payload = { phone: chatId, message: message };
        }

        const zApiUrl = `https://api.z-api.io/instances/${instanceId}/token/${token}${endpoint}`;
        logger.info("Enviando mensagem via Z-API", { url: zApiUrl, chatId, payload });

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
        logger.info("Resposta da Z-API", { data: zApiResponse.data });

        const chatDocRef = admin.firestore().collection("whatsappChats").doc(chatId);

        if (clientMessageId) {
            const existingMessages = await chatDocRef
                .collection("messages")
                .where("clientMessageId", "==", uniqueId)
                .get();
            if (!existingMessages.empty) {
                logger.warn("Mensagem duplicada detectada", { clientMessageId: uniqueId });
                return res.status(200).send(zApiResponse.data);
            }
        }

        // Prepara os dados para salvar no Firestore
        let firestoreData = {
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            fromMe: true,
            sender: zApiResponse.data.sender || null,
            clientMessageId: uniqueId,
            type: (fileType && fileType !== "text") ? fileType : "text",
        };

        if (fileType && fileType !== "text") {
            firestoreData.content = fileData; // Salva o valor original (sem prefixo) ou, se preferir, o imageData
            firestoreData.caption = message;   // Legenda
        } else {
            firestoreData.content = message;
        }

        await chatDocRef.collection("messages").add(firestoreData);

        await chatDocRef.set({
            chatId: chatId,
            lastMessage: (fileType && fileType !== "text" && message) ? message : firestoreData.content,
            lastMessageTime: admin.firestore.FieldValue.serverTimestamp(),
            type: firestoreData.type, // <-- Aqui o type que você definiu em firestoreData
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

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
        functions.logger.warn("Método não permitido", { method: req.method });
        return res.status(405).send("Method Not Allowed");
    }

    try {
        // Aqui, basta termos chatId e docId (ID do documento no Firestore)
        const { chatId, docId } = req.body;

        if (!chatId || !docId) {
            functions.logger.warn("Parâmetros ausentes", { chatId, docId });
            return res.status(400).send("Faltam parâmetros para deletar a mensagem (chatId e docId)");
        }

        // Remove o documento do Firestore
        await admin
            .firestore()
            .collection("whatsappChats")
            .doc(chatId)
            .collection("messages")
            .doc(docId)
            .delete();

        functions.logger.info("Mensagem excluída localmente com sucesso", { chatId, docId });
        return res.status(200).send({ success: true });
    } catch (error) {
        functions.logger.error("Erro ao deletar mensagem:", error);
        return res.status(500).send(error.toString());
    }
});

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
        const { motivo, assunto, dataReuniao, nomeEmpresa, tipoSolicitacao, createdAt } = req.body;

        // Validação simples
        if (!motivo || !dataReuniao || !nomeEmpresa || !tipoSolicitacao) {
            console.log("[sendMeetingRequestToSQS] Campos obrigatórios ausentes no body."); // ADICIONADO
            return res.status(400).json({ error: "Campos obrigatórios ausentes" });
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

        // Cria o comando e envia a mensagem
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
        return res.status(500).json({ error: "Erro interno ao enviar dados para o SQS" });
    }
});