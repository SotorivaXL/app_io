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