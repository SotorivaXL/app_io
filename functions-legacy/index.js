const {onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const logger = require("firebase-functions/logger");
const functions = require("firebase-functions/v1");
const admin = require('firebase-admin');
const axios = require('axios');
const cors = require('cors');
const express = require("express");
admin.initializeApp();
const db = admin.firestore();
const auth = admin.auth();
const crypto = require('crypto');

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

exports.setCustomUserClaims = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'The function must be called while authenticated.');
    }

    const uid = context.auth.uid;

    try {
        // Tenta buscar os dados do usuário na coleção 'users'
        const userDoc = await admin.firestore().collection('users').doc(uid).get();

        let userData;
        if (userDoc.exists) {
            userData = userDoc.data();
        } else {
            // Caso o documento não exista em 'users', tenta buscar na coleção 'empresas'
            const empresaDoc = await admin.firestore().collection('empresas').doc(uid).get();
            if (empresaDoc.exists) {
                userData = empresaDoc.data();
                userData.name = userData.NomeEmpresa;  // Usa o nome da empresa se o usuário não for encontrado
            } else {
                throw new functions.https.HttpsError('not-found', 'User or company not found');
            }
        }

        const customClaims = {
            dashboard: userData.dashboard || false,
            leads: userData.leads || false,
            gerenciarColaboradores: userData.gerenciarColaboradores || false,
            gerenciarParceiros: userData.gerenciarParceiros || false,
        };

        // Define as custom claims para o usuário
        await admin.auth().setCustomUserClaims(uid, customClaims);

        // Retorna os dados do usuário ou empresa junto com as claims
        return {
            message: `Success! Custom claims have been set for user ${uid}.`,
            claims: customClaims,
            userData: {
                name: userData.name || 'Usuário',
                email: userData.email,
                role: userData.role || 'Empresa'
            }
        };
    } catch (error) {
        return {
            error: error.message
        };
    }
});

exports.addCampaign = functions.https.onCall(async (data, context) => {
    try {
        const {empresaId, nomeCampanha, descricao, dataInicio, dataFim} = data;

        // Verificar se os campos obrigatórios foram fornecidos
        if (!empresaId || !nomeCampanha) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'Os campos empresaId e nomeCampanha são necessários.'
            );
        }

        const campaignData = {
            nome_campanha: nomeCampanha,
            descricao,
            dataInicio: admin.firestore.Timestamp.fromDate(new Date(dataInicio)),
            dataFim: admin.firestore.Timestamp.fromDate(new Date(dataFim)),
        };

        // Referência para a coleção de campanhas dentro da empresa
        const campaignsCollectionRef = admin
            .firestore()
            .collection('empresas')
            .doc(empresaId)
            .collection('campanhas');

        // Adicionar a campanha à coleção
        await campaignsCollectionRef.add(campaignData);

        return {message: 'Campanha adicionada com sucesso.'};
    } catch (error) {
        console.error('Erro ao adicionar campanha:', error);
        throw new functions.https.HttpsError('internal', 'Erro ao adicionar campanha.');
    }
});

// Delete (Excluir uma empresa existente)
exports.deleteCompany = functions.https.onCall(async (data, context) => {
    // Verifica se o usuário está autenticado
    if (!context.auth) {
        throw new functions.https.HttpsError(
            'unauthenticated',
            'A função deve ser chamada enquanto autenticado.'
        );
    }

    const companyId = data.companyId;
    if (!companyId) {
        throw new functions.https.HttpsError(
            'invalid-argument',
            'O ID da empresa é necessário.'
        );
    }

    try {
        // 1. Deletar a empresa do Firestore
        await admin.firestore().collection('empresas').doc(companyId).delete();
        console.log(`Empresa ${companyId} deletada do Firestore.`);

        // 2. Deletar a conta da empresa no Firebase Authentication
        try {
            await admin.auth().deleteUser(companyId);
            console.log(`Conta da empresa ${companyId} deletada do Authentication.`);
        } catch (error) {
            console.error(`Erro ao deletar a conta da empresa ${companyId}:`, error);
            // Continua mesmo assim
        }

        // 3. Deletar os arquivos da empresa no Firebase Storage
        const bucket = admin.storage().bucket();
        const companyFolder = companyId + '/'; // Supõe que os arquivos estão em uma pasta nomeada com o companyId
        const [companyFiles] = await bucket.getFiles({prefix: companyFolder});
        for (const file of companyFiles) {
            try {
                await file.delete();
                console.log(`Arquivo ${file.name} deletado da empresa.`);
            } catch (error) {
                console.error(`Erro ao deletar arquivo ${file.name} da empresa:`, error);
            }
        }

        // 4. Buscar todos os usuários com 'createdBy' igual ao companyId
        const usersSnapshot = await admin.firestore()
            .collection('users')
            .where('createdBy', '==', companyId)
            .get();
        const userUids = [];
        usersSnapshot.forEach(doc => {
            const uid = doc.id; // Usa o ID do documento como UID do usuário
            if (uid) {
                userUids.push(uid);
            }
        });

        // 5. Para cada usuário vinculado, deletar conta, documento e arquivos no Storage
        for (const uid of userUids) {
            try {
                // Deletar do Firebase Authentication
                await admin.auth().deleteUser(uid);
                console.log(`Usuário ${uid} deletado do Authentication.`);

                // Deletar do Firestore
                await admin.firestore().collection('users').doc(uid).delete();
                console.log(`Usuário ${uid} deletado do Firestore.`);

                // Deletar os arquivos do usuário no Storage
                const userFolder = uid + '/';
                const [userFiles] = await bucket.getFiles({prefix: userFolder});
                for (const file of userFiles) {
                    try {
                        await file.delete();
                        console.log(`Arquivo ${file.name} deletado do usuário ${uid}.`);
                    } catch (error) {
                        console.error(`Erro ao deletar arquivo ${file.name} do usuário ${uid}:`, error);
                    }
                }
            } catch (error) {
                console.error(`Erro ao deletar usuário ${uid}:, error`);
                // Continua tentando com os próximos usuários
            }
        }

        return {success: true, message: 'Empresa e usuários vinculados excluídos com sucesso.'};
    } catch (error) {
        console.error('Erro ao excluir empresa e usuários vinculados:', error);
        throw new functions.https.HttpsError('unknown', 'Erro ao excluir empresa e usuários vinculados.');
    }
});

exports.createUserAndCompany = functions
    .runWith({secrets: ['ENCRYPTION_KEY']})
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'A função deve ser chamada enquanto autenticado.'
            );
        }

        const {
            email,
            password,
            nomeEmpresa,
            name,
            role,
            birth,
            founded,
            cnpj,
            accessRights = {},
            contract,
            countArtsValue,
            countVideosValue,

            // NOVO: campos para o WhatsApp/Z-API
            phoneNumber,       // e.g. "+5511999999999" (pode vir com máscara; será saneado)
            instanceId,        // ZAPI_ID
            token,             // ZAPI_TOKEN
            clientToken,       // Client-Token da Z-API
            phoneId: payloadPhoneId, // opcional: força o id do doc do telefone
        } = data;

        const coalesceBool = (vals, defVal) => {
            for (const v of vals) if (typeof v === 'boolean') return v;
            return !!defVal;
        };

        // helper p/ limpar o telefone (deixa só dígitos)
        const onlyDigits = (str) => (str || '').toString().replace(/\D/g, '');

        try {
            const userRecord = await admin.auth().createUser({
                email,
                password,
                emailVerified: false,
                disabled: false,
            });

            const hasAnyAdminSubPerm =
                !!(accessRights.gerenciarParceiros ||
                    accessRights.gerenciarColaboradores ||
                    accessRights.configurarDash ||
                    accessRights.criarForm ||
                    accessRights.criarCampanha);

            const perms = {
                // MÓDULOS
                modChats: coalesceBool([accessRights.modChats, accessRights.gerenciarWhatsapp], true),
                modIndicadores: coalesceBool([accessRights.modIndicadores, accessRights.dashboard], true),
                modPainel: coalesceBool([accessRights.modPainel], hasAnyAdminSubPerm),
                modConfig: coalesceBool([accessRights.modConfig], true),
                modRelatorios: coalesceBool([accessRights.modRelatorios], false),

                // Internas do Painel
                gerenciarParceiros: !!accessRights.gerenciarParceiros,
                gerenciarColaboradores: !!accessRights.gerenciarColaboradores,
                configurarDash: !!accessRights.configurarDash,
                criarForm: !!accessRights.criarForm,
                criarCampanha: !!accessRights.criarCampanha,

                // Outras
                leads: !!accessRights.leads,
                copiarTelefones: !!accessRights.copiarTelefones,
                executarAPIs: !!accessRights.executarAPIs,
                alterarSenha: !!accessRights.alterarSenha,
            };

            if (cnpj) {
                // ===== EMPRESA =====
                const companyRef = admin.firestore().collection('empresas').doc(userRecord.uid);

                await companyRef.set({
                    NomeEmpresa: nomeEmpresa,
                    email,
                    cnpj,
                    founded,

                    // MÓDULOS
                    modChats: perms.modChats,
                    modIndicadores: perms.modIndicadores,
                    modPainel: perms.modPainel,
                    modConfig: perms.modConfig,
                    modRelatorios: perms.modRelatorios,

                    // Internas do Painel
                    gerenciarParceiros: perms.gerenciarParceiros,
                    gerenciarColaboradores: perms.gerenciarColaboradores,
                    configurarDash: perms.configurarDash,
                    criarForm: perms.criarForm,
                    criarCampanha: perms.criarCampanha,

                    // Outras
                    leads: perms.leads,
                    copiarTelefones: perms.copiarTelefones,
                    executarAPIs: perms.executarAPIs,
                    alterarSenha: perms.alterarSenha,

                    contract: contract || '',
                    countArtsValue: countArtsValue || 0,
                    countVideosValue: countVideosValue || 0,
                    isDevAccount: false,
                    emailVerified: false,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                }, {merge: true});

                // ===== NOVO: salvar telefone e credenciais da Z-API =====
                const digits = onlyDigits(phoneNumber);
                const phoneId = payloadPhoneId || digits; // docId padrão = dígitos do telefone

                if (phoneId) {
                    const phoneDocRef = companyRef.collection('phones').doc(phoneId);

                    const phonePayload = {
                        phoneId,
                        // GRAVA CIFRADO
                        instanceId: seal(instanceId || ''),
                        token: seal(token || ''),
                        clientToken: seal(clientToken || ''),
                        // telefone pode ficar em claro (se quiser cifrar, aplique seal)
                        phone: digits || null,
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    };

                    await phoneDocRef.set(phonePayload, {merge: true});
                }

                return {
                    success: true,
                    message: 'Usuário e empresa criados com sucesso.',
                    uid: userRecord.uid,
                    phoneId: (payloadPhoneId || onlyDigits(phoneNumber)) || null,
                };

            } else {
                // ===== COLABORADOR =====
                await admin.firestore().collection('users').doc(userRecord.uid).set({
                    name,
                    email,
                    role,
                    birth,
                    createdBy: context.auth.uid,

                    // MÓDULOS
                    modChats: perms.modChats,
                    modIndicadores: perms.modIndicadores,
                    modPainel: perms.modPainel,
                    modConfig: perms.modConfig,
                    modRelatorios: perms.modRelatorios,

                    // Internas do Painel
                    gerenciarParceiros: perms.gerenciarParceiros,
                    gerenciarColaboradores: perms.gerenciarColaboradores,
                    configurarDash: perms.configurarDash,
                    criarForm: perms.criarForm,
                    criarCampanha: perms.criarCampanha,

                    // Outras
                    leads: perms.leads,
                    copiarTelefones: perms.copiarTelefones,
                    executarAPIs: perms.executarAPIs,
                    alterarSenha: perms.alterarSenha,

                    emailVerified: false,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                }, {merge: true});

                return {success: true, message: 'Usuário colaborador criado com sucesso.', uid: userRecord.uid};
            }
        } catch (error) {
            console.error('createUserAndCompany failed:', error);

            // exemplos de mapeamento comuns
            if (error?.code === 'auth/email-already-exists') {
                throw new functions.https.HttpsError('already-exists', 'E-mail já está em uso.');
            }
            if (error?.code === 'auth/invalid-password') {
                throw new functions.https.HttpsError('invalid-argument', 'Senha inválida.');
            }
            if (error?.code === 'permission-denied') {
                throw new functions.https.HttpsError('permission-denied', 'Sem permissão para criar usuários.');
            }

            throw new functions.https.HttpsError('internal', error?.message || 'Falha interna.');
        }
    });

exports.setCompanyClaims = functions.https.onCall(async (data, context) => {
    try {
        // Verifica se o usuário está autenticado
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', 'A função deve ser chamada enquanto autenticado.');
        }

        const uid = context.auth.uid;

        // Captura os dados do usuário no Firestore
        const userDoc = await admin.firestore().collection('users').doc(uid).get();
        if (!userDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Usuário não encontrado.');
        }

        const userData = userDoc.data();

        // Captura o ID da empresa associada ao usuário
        const companyId = userData.companyId;
        if (!companyId) {
            throw new functions.https.HttpsError('failed-precondition', 'Nenhum ID de empresa associado a este usuário.');
        }

        // Define a claim personalizada com o ID da empresa
        await admin.auth().setCustomUserClaims(uid, {companyId});

        return {
            message: 'Claims set successfully for user ${uid}.',
            companyId: companyId,
        };
    } catch (error) {
        return {
            error: error.message,
        };
    }
});

exports.addCampanha = functions.https.onCall(async (data, context) => {
    const {empresaId, nome_campanha, descricao, dataInicio, dataFim} = data;

    // Verifica se todos os dados necessários foram fornecidos
    if (!empresaId || !nome_campanha || !descricao || !dataInicio || !dataFim) {
        throw new functions.https.HttpsError('invalid-argument', 'Todos os campos são obrigatórios.');
    }

    try {
        // Adiciona a nova campanha à coleção de campanhas da empresa
        const campanhaRef = admin.firestore().collection('empresas').doc(empresaId).collection('campanhas').doc();

        await campanhaRef.set({
            nome_campanha: nome_campanha,
            descricao: descricao,
            dataInicio: new Date(dataInicio),
            dataFim: new Date(dataFim),
        });

        return {message: 'Campanha adicionada com sucesso!'};
    } catch (error) {
        console.error('Erro ao adicionar campanha:', error);
        throw new functions.https.HttpsError('internal', 'Erro ao adicionar campanha.');
    }
});

exports.deleteUser = functions.https.onCall(async (data, context) => {
    const uid = data.uid;

    if (!uid) {
        throw new functions.https.HttpsError('invalid-argument', 'O UID do usuário é necessário.');
    }

    try {
        // Apaga o usuário do Firebase Authentication
        await admin.auth().deleteUser(uid);

        // Apaga o documento do usuário no Firestore
        await admin.firestore().collection('users').doc(uid).delete();

        return {success: true};
    } catch (error) {
        console.error('Erro ao deletar o usuário:', error);
        throw new functions.https.HttpsError('internal', 'Erro ao deletar o usuário.');
    }
});

exports.deleteUserByEmail = functions.https.onCall(async (data, context) => {
    const email = data.email;

    try {
        const userRecord = await admin.auth().getUserByEmail(email);
        await admin.auth().deleteUser(userRecord.uid);
        return {message: 'Usuário excluído com sucesso'};
    } catch (error) {
        return {error: 'Erro ao excluir o usuário: ' + error.message};
    }
});

exports.changeUserPassword = functions.https.onCall(async (data, context) => {
    // Verifica se o usuário está autenticado
    if (!context.auth) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            'A função deve ser chamada por um usuário autenticado.'
        );
    }

    const uidRequester = context.auth.uid;
    const uid = data.uid;
    const newPassword = data.newPassword;

    // Verifica se o usuário solicitante tem permissão para alterar a senha
    try {
        const empresaDoc = await admin.firestore().collection('empresas').doc(uidRequester).get();

        if (!empresaDoc.exists) {
            throw new functions.https.HttpsError(
                'permission-denied',
                'Usuário não encontrado na coleção empresas.'
            );
        }

        const alterarSenha = empresaDoc.data().alterarSenha;

        if (!alterarSenha) {
            throw new functions.https.HttpsError(
                'permission-denied',
                'Você não tem permissão para alterar a senha.'
            );
        }

        // Atualiza a senha do usuário
        await admin.auth().updateUser(uid, {password: newPassword});
        return {message: 'Senha atualizada com sucesso'};

    } catch (error) {
        if (error instanceof functions.https.HttpsError) {
            throw error;
        } else {
            throw new functions.https.HttpsError('unknown', error.message);
        }
    }
});

exports.getSyncOptions = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    }

    const {level, bmId, adAccountId, campaignId} = data;

    try {
        switch (level.toUpperCase()) {
            case 'BM':
                // Retorna as opções de Business Managers
                const bmsSnapshot = await admin.firestore().collection('dashboard').get();
                return bmsSnapshot.docs.map(doc => ({
                    label: doc.data().name,
                    value: doc.data().id // Usando o verdadeiro ID da BM
                }));

            case 'CONTA_ANUNCIO':
                if (!bmId) {
                    // bmId ausente, retorna opções de BM
                    const bmsForAdSnapshot = await admin.firestore().collection('dashboard').get();
                    return bmsForAdSnapshot.docs.map(doc => ({
                        label: doc.data().name,
                        value: doc.data().id
                    }));
                }
                // Fetch Ad Accounts para o bmId fornecido
                const accountsSnapshot = await admin.firestore().collection('dashboard')
                    .where('id', '==', bmId).get();

                if (accountsSnapshot.empty) {
                    throw new functions.https.HttpsError('not-found', `Nenhum Business Manager encontrado com id: ${bmId}`);
                }

                const bmDoc = accountsSnapshot.docs[0];
                const bmDocId = bmDoc.id; // Nome do documento (nome da BM)

                const adAccounts = await admin.firestore().collection('dashboard')
                    .doc(bmDocId).collection('contasAnuncio').get();

                return adAccounts.docs.map(doc => ({
                    label: doc.data().name,
                    value: doc.data().name // Usando 'name' como value
                }));

            case 'CAMPANHA':
                if (!bmId) {
                    // bmId ausente, retorna opções de BM
                    const bmsForCampaignSnapshot = await admin.firestore().collection('dashboard').get();
                    return bmsForCampaignSnapshot.docs.map(doc => ({
                        label: doc.data().name,
                        value: doc.data().id
                    }));
                } else if (bmId && !adAccountId) {
                    // adAccountId ausente, retorna Contas de Anúncio
                    const accountsSnapshotCamp = await admin.firestore().collection('dashboard')
                        .where('id', '==', bmId).get();

                    if (accountsSnapshotCamp.empty) {
                        throw new functions.https.HttpsError('not-found', `Nenhum Business Manager encontrado com id: ${bmId}`);
                    }

                    const bmDocCamp = accountsSnapshotCamp.docs[0];
                    const bmDocIdCamp = bmDocCamp.id; // Nome do documento (nome da BM)

                    const adAccountsCamp = await admin.firestore().collection('dashboard')
                        .doc(bmDocIdCamp).collection('contasAnuncio').get();

                    return adAccountsCamp.docs.map(doc => ({
                        label: doc.data().name,
                        value: doc.data().name
                    }));
                } else if (bmId && adAccountId && !campaignId) {
                    // Retorna opções de Campanhas
                    const campaignsSnapshot = await admin.firestore().collection('dashboard')
                        .where('id', '==', bmId).get();

                    if (campaignsSnapshot.empty) {
                        throw new functions.https.HttpsError('not-found', `Nenhum Business Manager encontrado com id: ${bmId}`);
                    }

                    const bmCampaignDoc = campaignsSnapshot.docs[0];
                    const bmCampaignDocId = bmCampaignDoc.id;

                    // Buscar o documento da Conta de Anúncio pelo nome para obter o 'id'
                    const adAccountDoc = await admin.firestore().collection('dashboard')
                        .doc(bmCampaignDocId).collection('contasAnuncio')
                        .where('name', '==', adAccountId).get();

                    if (adAccountDoc.empty) {
                        throw new functions.https.HttpsError('not-found', `Nenhuma Conta de Anúncio encontrada com name: ${adAccountId}`);
                    }

                    const adAccountRealId = adAccountDoc.docs[0].data().id;
                    const adAccountFirestoreId = adAccountDoc.docs[0].id; // Nome da Conta de Anúncio

                    const campaignsFirestoreSnapshot = await admin.firestore().collection('dashboard')
                        .doc(bmCampaignDocId).collection('contasAnuncio')
                        .doc(adAccountFirestoreId).collection('campanhas').get();

                    return campaignsFirestoreSnapshot.docs.map(doc => ({
                        label: doc.data().name,
                        value: doc.data().name // Usando 'name' como value
                    }));
                } else {
                    // Todos os parâmetros presentes, sem opções para retornar
                    return [];
                }

            case 'GRUPO_ANUNCIO':
                if (!bmId) {
                    // bmId ausente, retorna opções de BM
                    const bmsForGrupoSnapshot = await admin.firestore().collection('dashboard').get();
                    return bmsForGrupoSnapshot.docs.map(doc => ({
                        label: doc.data().name,
                        value: doc.data().id
                    }));
                } else if (bmId && !adAccountId) {
                    // adAccountId ausente, retorna Contas de Anúncio
                    const accountsSnapshotGrupo = await admin.firestore().collection('dashboard')
                        .where('id', '==', bmId).get();

                    if (accountsSnapshotGrupo.empty) {
                        throw new functions.https.HttpsError('not-found', `Nenhum Business Manager encontrado com id: ${bmId}`);
                    }

                    const bmDocGrupo = accountsSnapshotGrupo.docs[0];
                    const bmDocIdGrupo = bmDocGrupo.id; // Nome do documento (nome da BM)

                    const adAccountsGrupo = await admin.firestore().collection('dashboard')
                        .doc(bmDocIdGrupo).collection('contasAnuncio').get();

                    return adAccountsGrupo.docs.map(doc => ({
                        label: doc.data().name,
                        value: doc.data().name
                    }));
                } else if (bmId && adAccountId && !campaignId) {
                    // campaignId ausente, retorna Campanhas
                    const campaignsSnapshotGrupo = await admin.firestore().collection('dashboard')
                        .where('id', '==', bmId).get();

                    if (campaignsSnapshotGrupo.empty) {
                        throw new functions.https.HttpsError('not-found', `Nenhum Business Manager encontrado com id: ${bmId}`);
                    }

                    const bmCampaignDocGrupo = campaignsSnapshotGrupo.docs[0];
                    const bmCampaignDocIdGrupo = bmCampaignDocGrupo.id;

                    // Buscar o documento da Conta de Anúncio pelo nome para obter o 'id'
                    const adAccountDocGrupo = await admin.firestore().collection('dashboard')
                        .doc(bmCampaignDocIdGrupo).collection('contasAnuncio')
                        .where('name', '==', adAccountId).get();

                    if (adAccountDocGrupo.empty) {
                        throw new functions.https.HttpsError('not-found', `Nenhuma Conta de Anúncio encontrada com name: ${adAccountId}`);
                    }

                    const adAccountRealIdGrupo = adAccountDocGrupo.docs[0].data().id;
                    const adAccountFirestoreIdGrupo = adAccountDocGrupo.docs[0].id;

                    // Buscar Campanhas
                    const campaignsFirestoreSnapshotGrupo = await admin.firestore().collection('dashboard')
                        .doc(bmCampaignDocIdGrupo).collection('contasAnuncio')
                        .doc(adAccountFirestoreIdGrupo).collection('campanhas').get();

                    return campaignsFirestoreSnapshotGrupo.docs.map(doc => ({
                        label: doc.data().name,
                        value: doc.data().name // Usando 'name' como value
                    }));
                } else if (bmId && adAccountId && campaignId) {
                    // Retorna opções de Grupos de Anúncio
                    const gruposAnuncioSnapshot = await admin.firestore().collection('dashboard')
                        .where('id', '==', bmId).get();

                    if (gruposAnuncioSnapshot.empty) {
                        throw new functions.https.HttpsError('not-found', `Nenhum Business Manager encontrado com id: ${bmId}`);
                    }

                    const bmGrupoDoc = gruposAnuncioSnapshot.docs[0];
                    const bmGrupoDocId = bmGrupoDoc.id;

                    // Buscar o documento da Conta de Anúncio pelo nome para obter o 'id'
                    const adAccountGrupoDoc = await admin.firestore().collection('dashboard')
                        .doc(bmGrupoDocId).collection('contasAnuncio')
                        .where('name', '==', adAccountId).get();

                    if (adAccountGrupoDoc.empty) {
                        throw new functions.https.HttpsError('not-found', `Nenhuma Conta de Anúncio encontrada com name: ${adAccountId}`);
                    }

                    const adAccountGrupoRealId = adAccountGrupoDoc.docs[0].data().id;
                    const adAccountGrupoFirestoreId = adAccountGrupoDoc.docs[0].id; // Nome da Conta de Anúncio

                    // Buscar a Campanha pelo nome para obter o 'id'
                    const campaignDocSnapshot = await admin.firestore().collection('dashboard')
                        .doc(bmGrupoDocId).collection('contasAnuncio')
                        .doc(adAccountGrupoFirestoreId).collection('campanhas')
                        .where('name', '==', campaignId).get();

                    if (campaignDocSnapshot.empty) {
                        throw new functions.https.HttpsError('not-found', `Nenhuma Campanha encontrada com name: ${campaignId}`);
                    }

                    const campaignGrupoDoc = campaignDocSnapshot.docs[0];
                    const campaignGrupoRealId = campaignGrupoDoc.data().id;
                    const campaignGrupoFirestoreId = campaignGrupoDoc.id; // Nome da Campanha

                    // Buscar Grupos de Anúncio
                    const gruposAnuncioFirestoreSnapshot = await admin.firestore().collection('dashboard')
                        .doc(bmGrupoDocId).collection('contasAnuncio')
                        .doc(adAccountGrupoFirestoreId).collection('campanhas')
                        .doc(campaignGrupoFirestoreId).collection('gruposAnuncio').get();

                    return gruposAnuncioFirestoreSnapshot.docs.map(doc => ({
                        label: doc.data().name,
                        value: doc.data().name // Usando 'name' como value
                    }));
                }

            case 'INSIGHTS':
                if (!bmId) {
                    // bmId ausente, retorna opções de BM
                    const bmsForInsightsSnapshot = await admin.firestore().collection('dashboard').get();
                    return bmsForInsightsSnapshot.docs.map(doc => ({
                        label: doc.data().name,
                        value: doc.data().id
                    }));
                } else if (bmId && !adAccountId) {
                    // adAccountId ausente, retorna Contas de Anúncio
                    const accountsSnapshotInsights = await admin.firestore().collection('dashboard')
                        .where('id', '==', bmId).get();

                    if (accountsSnapshotInsights.empty) {
                        throw new functions.https.HttpsError('not-found', `Nenhum Business Manager encontrado com id: ${bmId}`);
                    }

                    const bmDocInsights = accountsSnapshotInsights.docs[0];
                    const bmDocIdInsights = bmDocInsights.id; // Nome do documento (nome da BM)

                    const adAccountsInsights = await admin.firestore().collection('dashboard')
                        .doc(bmDocIdInsights).collection('contasAnuncio').get();

                    return adAccountsInsights.docs.map(doc => ({
                        label: doc.data().name,
                        value: doc.data().name
                    }));
                } else if (bmId && adAccountId) {
                    // Não há seleção adicional necessária para Insights
                    // Retorna uma mensagem indicando que não há mais opções
                    return [];
                }

            default:
                return [];
        }
    } catch (error) {
        console.error('Erro em getSyncOptions:', error);
        throw new functions.https.HttpsError('internal', 'Erro ao buscar opções', error);
    }
});

// Função principal para sincronizar dados
exports.syncMetaData = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    }

    const {level, bmId, adAccountId, campaignId} = data;

    // Log dos parâmetros recebidos
    console.log(`syncMetaData chamada com: level=${level}, bmId=${bmId}, adAccountId=${adAccountId}, campaignId=${campaignId}`);

    const metaDoc = await admin.firestore().collection(META_CONFIG.collection).doc(META_CONFIG.docId).get();

    if (!metaDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Configurações da Meta não encontradas');
    }

    const metaData = metaDoc.data();

    // Verificação do access_token
    if (!metaData.access_token) {
        throw new functions.https.HttpsError('failed-precondition', 'Access Token não configurado');
    }

    const makeMetaRequest = async (url, params = {}) => {
        try {
            const response = await axios.get(url, {
                params: {
                    access_token: metaData.access_token,
                    ...params
                },
                timeout: 10000
            });
            return response.data.data || [];
        } catch (error) {
            const errorData = error.response?.data?.error || {};
            console.error('Erro na API Meta:', {
                code: errorData.code,
                type: errorData.type,
                message: errorData.message,
                fbtrace_id: errorData.fbtrace_id
            });

            throw new functions.https.HttpsError(
                'internal',
                'Erro na API Meta: ' + (errorData.message || 'Erro desconhecido'),
                {
                    code: errorData.code,
                    subcode: errorData.error_subcode,
                    fbtrace_id: errorData.fbtrace_id
                }
            );
        }
    };

    const refreshFirestoreData = async (collectionPath, newData, idField = 'id', nameField = 'name') => {
        const batch = admin.firestore().batch();
        const collectionRef = admin.firestore().collection(collectionPath);

        const snapshot = await collectionRef.get();
        snapshot.forEach(doc => batch.delete(doc.ref));

        newData.forEach(item => {
            if (!item[idField] || !item[nameField]) {
                throw new functions.https.HttpsError(
                    'internal',
                    `Campos de ID ou Nome ausentes no item: ${JSON.stringify(item)}`
                );
            }
            // Sanitizar o nome para ser usado como ID do documento
            const sanitizedName = item[nameField].replace(/[^a-zA-Z0-9_-]/g, '_');
            const docRef = collectionRef.doc(sanitizedName);
            batch.set(docRef, sanitizeMetaData(item));
        });

        await batch.commit();
    };

    try {
        let result;
        switch (level.toUpperCase()) {
            case 'BM':
                console.log('Sincronizando Business Managers...');
                const bms = await makeMetaRequest(`${metaData[META_CONFIG.fields.baseUrl]}/me/businesses?limit=10000000000000`, {
                    fields: 'id,name,created_time,vertical'
                });
                console.log(`Recebidos ${bms.length} Business Managers.`);
                await refreshFirestoreData('dashboard', bms, 'id', 'name');
                result = {message: `${bms.length} BMs sincronizadas`};
                break;

            case 'CONTA_ANUNCIO':
                // Verificação do formato do BM ID
                if (!bmId) {
                    console.log('bmId está ausente.');
                    throw new functions.https.HttpsError(
                        'invalid-argument',
                        'ID do Business Manager inválido: bmId ausente'
                    );
                }

                // Assegure-se de que bmId é uma string numérica
                if (typeof bmId !== 'string' || !/^\d+$/.test(bmId)) {
                    console.log(`bmId inválido: ${bmId}`);
                    throw new functions.https.HttpsError(
                        'invalid-argument',
                        'ID do Business Manager deve ser uma string numérica'
                    );
                }

                console.log(`Sincronizando Contas de Anúncio para BM ID: ${bmId}`);

                // Consultar a coleção 'dashboard' para encontrar o documento com 'id' igual a 'bmId'
                const bmQuerySnapshot = await admin.firestore().collection('dashboard')
                    .where('id', '==', bmId).get();

                if (bmQuerySnapshot.empty) {
                    console.error(`Nenhum documento encontrado na coleção 'dashboard' com id: ${bmId}`);
                    throw new functions.https.HttpsError(
                        'not-found',
                        `Nenhum documento encontrado para BM ID: ${bmId}`
                    );
                }

                if (bmQuerySnapshot.size > 1) {
                    console.warn(`Mais de um documento encontrado na coleção 'dashboard' com id: ${bmId}`);
                }

                // Obter o primeiro documento encontrado
                const bmDoc = bmQuerySnapshot.docs[0];
                const bmDocId = bmDoc.id; // Nome do documento (nome da BM)

                const adAccounts = await makeMetaRequest(
                    `${metaData[META_CONFIG.fields.baseUrl]}/${bmId}/owned_ad_accounts`, {
                        fields: 'id,name,account_id,account_status,currency,timezone_name',
                        limit: 200
                    }
                );
                console.log(`Recebidas ${adAccounts.length} Contas de Anúncio.`);

                // Acessar a subcoleção 'contasAnuncio' dentro do documento BM existente
                const adAccountsRef = admin.firestore().collection('dashboard').doc(bmDocId).collection('contasAnuncio');

                // Preparar o batch para deletar contas existentes e adicionar novas
                const adBatch = admin.firestore().batch();
                const existingAdAccounts = await adAccountsRef.get();
                existingAdAccounts.forEach(doc => adBatch.delete(doc.ref));

                adAccounts.forEach(account => {
                    if (!account.name || !account.id) { // Verificação atualizada para 'name' e 'id'
                        console.error('Conta sem name ou id:', account);
                        return;
                    }
                    // Sanitizar o nome para ser usado como ID do documento
                    const sanitizedName = account.name.replace(/[^a-zA-Z0-9_-]/g, '_');
                    const docRef = adAccountsRef.doc(sanitizedName); // Usando 'name' como ID do documento
                    adBatch.set(docRef, sanitizeMetaData(account));
                });

                await adBatch.commit();
                result = {message: `${adAccounts.length} contas sincronizadas`};
                break;

            case 'CAMPANHA':
                if (!bmId) {
                    console.log('bmId está ausente para CAMPANHA.');
                    throw new functions.https.HttpsError(
                        'invalid-argument',
                        'bmId é necessário para sincronizar campanhas.'
                    );
                }

                if (!adAccountId) {
                    console.log('adAccountId está ausente para CAMPANHA.');
                    throw new functions.https.HttpsError(
                        'invalid-argument',
                        'adAccountId é necessário para sincronizar campanhas.'
                    );
                }

                console.log(`Sincronizando Campanhas para Ad Account Name: ${adAccountId}`);

                // Consultar o BM document para obter o ID do BM
                const bmCampaignSnapshot = await admin.firestore().collection('dashboard')
                    .where('id', '==', bmId).get();

                if (bmCampaignSnapshot.empty) {
                    console.error(`Nenhum documento BM encontrado com id: ${bmId}`);
                    throw new functions.https.HttpsError(
                        'not-found',
                        `Nenhum documento BM encontrado com id: ${bmId}`
                    );
                }

                const bmCampaignDoc = bmCampaignSnapshot.docs[0];
                const bmCampaignDocId = bmCampaignDoc.id;

                // Buscar o documento da Conta de Anúncio pelo nome para obter o 'id'
                const adAccountCampaignSnapshot = await admin.firestore().collection('dashboard')
                    .doc(bmCampaignDocId).collection('contasAnuncio')
                    .where('name', '==', adAccountId).get();

                if (adAccountCampaignSnapshot.empty) {
                    console.error(`Nenhuma Conta de Anúncio encontrada com name: ${adAccountId}`);
                    throw new functions.https.HttpsError(
                        'not-found',
                        `Nenhuma Conta de Anúncio encontrada com name: ${adAccountId}`
                    );
                }

                const adAccountCampaignDoc = adAccountCampaignSnapshot.docs[0];
                const adAccountCampaignRealId = adAccountCampaignDoc.data().id;
                const adAccountCampaignFirestoreId = adAccountCampaignDoc.id; // Nome da Conta de Anúncio

                const campaignsUrl = `${metaData[META_CONFIG.fields.baseUrl]}/${adAccountCampaignRealId}/campaigns`;
                const campaigns = await makeMetaRequest(campaignsUrl, {
                    fields: 'id,name,status,objective,spend_cap',
                    effective_status: '["ACTIVE"]'
                });
                console.log(`Recebidas ${campaigns.length} campanhas.`);

                // Acessar a subcoleção 'campanhas' dentro da Conta de Anúncio existente
                const campanhasRef = admin.firestore().collection('dashboard').doc(bmCampaignDocId)
                    .collection('contasAnuncio').doc(adAccountCampaignFirestoreId).collection('campanhas');

                // Preparar o batch para deletar campanhas existentes e adicionar novas
                const campanhaBatch = admin.firestore().batch();
                const existingCampaigns = await campanhasRef.get();
                existingCampaigns.forEach(doc => campanhaBatch.delete(doc.ref));

                campaigns.forEach(campaign => {
                    if (!campaign.name || !campaign.id) { // Verificação atualizada para 'name' e 'id'
                        console.error('Campanha sem name ou id:', campaign);
                        return;
                    }
                    // Sanitizar o nome para ser usado como ID do documento
                    const sanitizedName = campaign.name.replace(/[^a-zA-Z0-9_-]/g, '_');
                    const docRef = campanhasRef.doc(sanitizedName); // Usando 'name' como ID do documento
                    campanhaBatch.set(docRef, sanitizeMetaData(campaign));
                });

                await campanhaBatch.commit();
                result = {message: `${campaigns.length} campanhas sincronizadas`};
                break;

            case 'GRUPO_ANUNCIO':
                if (!bmId || !adAccountId || !campaignId) {
                    console.log('bmId, adAccountId ou campaignId está ausente para GRUPO_ANUNCIO.');
                    throw new functions.https.HttpsError(
                        'invalid-argument',
                        'bmId, adAccountId e campaignId são necessários para sincronizar grupos de anúncio.'
                    );
                }

                console.log(`Sincronizando Grupos de Anúncio para Campanha Name: ${campaignId}`);

                // Consultar o BM document para obter o ID do BM
                const bmGrupoSnapshot = await admin.firestore().collection('dashboard')
                    .where('id', '==', bmId).get();

                if (bmGrupoSnapshot.empty) {
                    console.error(`Nenhum documento BM encontrado com id: ${bmId}`);
                    throw new functions.https.HttpsError(
                        'not-found',
                        `Nenhum documento BM encontrado com id: ${bmId}`
                    );
                }

                const bmGrupoDoc = bmGrupoSnapshot.docs[0];
                const bmGrupoDocId = bmGrupoDoc.id;

                // Buscar o documento da Conta de Anúncio pelo nome para obter o 'id'
                const adAccountGrupoSnapshot = await admin.firestore().collection('dashboard')
                    .doc(bmGrupoDocId).collection('contasAnuncio')
                    .where('name', '==', adAccountId).get();

                if (adAccountGrupoSnapshot.empty) {
                    console.error(`Nenhuma Conta de Anúncio encontrada com name: ${adAccountId}`);
                    throw new functions.https.HttpsError(
                        'not-found',
                        `Nenhuma Conta de Anúncio encontrada com name: ${adAccountId}`
                    );
                }

                const adAccountGrupoDoc = adAccountGrupoSnapshot.docs[0];
                const adAccountGrupoRealId = adAccountGrupoDoc.data().id;
                const adAccountGrupoFirestoreId = adAccountGrupoDoc.id; // Nome da Conta de Anúncio

                // Buscar o documento da Campanha pelo nome para obter o 'id'
                const campaignGrupoSnapshot = await admin.firestore().collection('dashboard')
                    .doc(bmGrupoDocId).collection('contasAnuncio')
                    .doc(adAccountGrupoFirestoreId).collection('campanhas')
                    .where('name', '==', campaignId).get();

                if (campaignGrupoSnapshot.empty) {
                    console.error(`Nenhuma Campanha encontrada com name: ${campaignId}`);
                    throw new functions.https.HttpsError(
                        'not-found',
                        `Nenhuma Campanha encontrada com name: ${campaignId}`
                    );
                }

                const campaignGrupoDoc = campaignGrupoSnapshot.docs[0];
                const campaignGrupoRealId = campaignGrupoDoc.data().id;
                const campaignGrupoFirestoreId = campaignGrupoDoc.id; // Nome da Campanha

                const adGroupsUrl = `${metaData[META_CONFIG.fields.baseUrl]}/${campaignGrupoRealId}/adsets`;
                const adGroups = await makeMetaRequest(adGroupsUrl, {
                    fields: 'id,name,status,budget_remaining',
                    effective_status: '["ACTIVE"]'
                });
                console.log(`Recebidas ${adGroups.length} grupos de anúncio.`);

                // Acessar a subcoleção 'gruposAnuncio' dentro da Campanha existente
                const gruposAnuncioRef = admin.firestore().collection('dashboard').doc(bmGrupoDocId)
                    .collection('contasAnuncio').doc(adAccountGrupoFirestoreId)
                    .collection('campanhas').doc(campaignGrupoFirestoreId)
                    .collection('gruposAnuncio');

                // Preparar o batch para deletar grupos existentes e adicionar novos
                const grupoBatch = admin.firestore().batch();
                const existingGrupos = await gruposAnuncioRef.get();
                existingGrupos.forEach(doc => grupoBatch.delete(doc.ref));

                adGroups.forEach(group => {
                    if (!group.name || !group.id) { // Verificação atualizada para 'name' e 'id'
                        console.error('Grupo de Anúncio sem name ou id:', group);
                        return;
                    }
                    // Sanitizar o nome para ser usado como ID do documento
                    const sanitizedName = group.name.replace(/[^a-zA-Z0-9_-]/g, '_');
                    const docRef = gruposAnuncioRef.doc(sanitizedName); // Usando 'name' como ID do documento
                    grupoBatch.set(docRef, sanitizeMetaData(group));
                });

                await grupoBatch.commit();
                result = {message: `${adGroups.length} grupos de anúncio sincronizados`};
                break;

            case 'INSIGHTS': {
                if (!bmId || !adAccountId) {
                    throw new functions.https.HttpsError(
                        'invalid-argument',
                        'bmId e adAccountId são necessários para insights.'
                    );
                }

                // 1. Obter a data do callData ou usar ontem
                let dateStr = data.date; // <--- Recebe a data do Flutter
                if (!dateStr) {
                    const today = new Date();
                    const yesterday = new Date(today);
                    yesterday.setDate(today.getDate() - 1);
                    dateStr = yesterday.toISOString().split('T')[0];
                }

                // 2. Validação de segurança da data
                if (!/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) {
                    throw new functions.https.HttpsError(
                        'invalid-argument',
                        'Formato de data inválido. Use YYYY-MM-DD'
                    );
                }

                // 3. Restante do código de busca...
                const bmSnapshot = await admin.firestore().collection('dashboard')
                    .where('id', '==', bmId).get();

                if (bmSnapshot.empty) {
                    throw new functions.https.HttpsError('not-found', `BM ${bmId} não encontrado`);
                }
                const bmDocInsights = bmSnapshot.docs[0]; // Renomeado para evitar conflito

                // 3. Buscar a Conta de Anúncio pelo nome
                const adAccountsSnapshot = await admin.firestore().collection('dashboard')
                    .doc(bmDocInsights.id).collection('contasAnuncio')
                    .where('name', '==', adAccountId).get();

                if (adAccountsSnapshot.empty) {
                    throw new functions.https.HttpsError('not-found', `Conta ${adAccountId} não encontrada`);
                }

                // 4. Obter o ID real da conta de anúncio
                const adAccountData = adAccountsSnapshot.docs[0].data();
                const adAccountInsightsRealId = adAccountData.id;

                const insightsUrl = `${metaData[META_CONFIG.fields.baseUrl]}/${adAccountInsightsRealId}/insights`;
                const insights = await makeMetaRequest(insightsUrl, {
                    fields: 'reach,cpm,impressions,inline_link_clicks,cost_per_inline_link_click,clicks,cpc,inline_post_engagement,spend',
                    time_range: JSON.stringify({since: dateStr, until: dateStr}), // <--- Data dinâmica
                    time_increment: 1
                });

                // 6. Salvar no Firestore
                const insightsRef = admin.firestore().collection('dashboard').doc(bmDocInsights.id)
                    .collection('contasAnuncio').doc(adAccountsSnapshot.docs[0].id)
                    .collection('insights');

                // Usar dateStr que já contém a data correta (selecionada ou do dia anterior)
                await insightsRef.doc(dateStr).set({
                    ...insights[0],
                    syncDate: admin.firestore.FieldValue.serverTimestamp()
                }, {merge: true});

                result = {
                    message: `Insights de ${dateStr} salvos com sucesso`,
                    date: dateStr,
                    data: insights[0]
                };
                break;
            }

            default:
                throw new functions.https.HttpsError(
                    'invalid-argument',
                    `Nível inválido: ${level}`
                );
        }

        console.log('Resultado da sincronização:', result);
        return result;

    } catch (error) {
        console.error('Erro completo:', {
            message: error.message,
            details: error.details,
            stack: error.stack
        });

        throw new functions.https.HttpsError(
            error.code || 'internal',
            error.message,
            error.details
        );
    }
});

const corsHandler = cors({
    origin: '*', // Permite todas as origens
    methods: ['POST', 'OPTIONS'], // Métodos permitidos
    allowedHeaders: ['Content-Type'], // Cabeçalhos permitidos
});

exports.addLead = functions.https.onRequest((req, res) => {
    corsHandler(req, res, async () => {
        try {
            // Extraímos os campos essenciais e o restante dos dados enviados
            const {empresa_id, nome_campanha, redirect_url, ...rest} = req.body;

            // Validação dos campos necessários
            if (!empresa_id || !nome_campanha || !rest.whatsapp) {
                res.status(400).json({message: 'empresa_id, nome_campanha e whatsapp são necessários.'});
                return;
            }

            // Cria a referência para a coleção de leads
            const leadsCollectionRef = admin
                .firestore()
                .collection('empresas')
                .doc(empresa_id)
                .collection('campanhas')
                .doc(nome_campanha)
                .collection('leads');

            // Calcula o timestamp de 5 minutos atrás
            const cincoMinutosAtras = admin.firestore.Timestamp.fromDate(new Date(Date.now() - 5 * 60 * 1000));

            // Verifica se já existe um lead com o mesmo WhatsApp nos últimos 5 minutos
            const snapshot = await leadsCollectionRef
                .where('whatsapp', '==', rest.whatsapp)
                .where('timestamp', '>=', cincoMinutosAtras)
                .limit(1)
                .get();

            if (!snapshot.empty) {
                // Já existe um lead com esse WhatsApp nos últimos 5 minutos
                res.status(409).json({message: 'Já existe uma resposta com este número de WhatsApp nos últimos 5 minutos.'});
                return;
            }

            // Monta os dados do lead incluindo todos os campos enviados,
            // além de adicionar os campos "status" e "timestamp"
            const leadData = {
                ...rest,
                status: 'Aguardando',
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
            };

            await leadsCollectionRef.add(leadData);

            // Retorna a URL de redirecionamento
            res.status(200).json({message: 'Resposta enviada com sucesso.', redirectUrl: redirect_url});
        } catch (error) {
            console.error('Erro ao enviar resposta:', error);
            res.status(500).json({message: 'Erro ao enviar resposta.'});
        }
    });
});

exports.getEmpresaCampanha = functions.https.onRequest(async (req, res) => {
    try {
        const {empresaId} = req.query;

        // Fetch the Empresa data
        const empresaDoc = await admin.firestore().collection('empresas').doc(empresaId).get();
        if (!empresaDoc.exists) {
            return res.status(404).json({error: 'Empresa not found'});
        }
        const empresaData = empresaDoc.data();

        // Fetch all Campanha data within the Empresa
        const campanhasSnapshot = await admin.firestore().collection('empresas').doc(empresaId).collection().get();
        const campanhasData = campanhasSnapshot.docs.map(doc => ({id: doc.id, ...doc.data()}));

        return res.status(200).json({
            empresa: empresaData,
            campanhas: campanhasData,
        });
    } catch (error) {
        console.error('Error fetching data:', error);
        return res.status(500).json({error: 'Internal Server Error'});
    }
});

// Funções CRUD para a coleção de empresas

// Read (Ler todas as empresas)
exports.getCompanies = functions.https.onRequest(async (req, res) => {
    try {
        const snapshot = await admin.firestore().collection('empresas').get();
        const companies = snapshot.docs.map(doc => ({id: doc.id, ...doc.data()}));

        res.status(200).json(companies);
    } catch (error) {
        console.error("Error getting companies: ", error);
        res.status(500).send("Erro ao buscar empresas");
    }
});

// Update (Atualizar uma empresa existente)
exports.updateCompany = functions.https.onRequest(async (req, res) => {
    try {
        console.log('Recebendo dados:', req.body);

        const {
            companyId,
            NomeEmpresa,
            contract,
            countArtsValue,
            countVideosValue,
            dashboard,
            leads,
            gerenciarColaboradores,
            gerenciarParceiros
        } = req.body;

        // Verifique se todos os campos obrigatórios estão presentes
        if (!companyId || !NomeEmpresa || !contract) {
            return res.status(400).send('Missing companyId, NomeEmpresa, or contract');
        }

        const updateData = {
            NomeEmpresa: NomeEmpresa,
            contract: contract,
            countArtsValue: countArtsValue,
            countVideosValue: countVideosValue,
            dashboard: dashboard,
            leads: leads,
            gerenciarColaboradores: gerenciarColaboradores,
            gerenciarParceiros: gerenciarParceiros,
        };

        console.log('Dados para atualizar:', updateData);

        // Atualize a empresa no Firestore
        const docRef = admin.firestore().collection('empresas').doc(companyId);
        await docRef.update(updateData);

        res.status(200).send({success: true, message: "Empresa atualizada com sucesso!"});
    } catch (error) {
        console.error("Error updating company:", error);
        res.status(500).send("Erro ao atualizar empresa");
    }
});

exports.deleteUser = functions.https.onCall(async (data, context) => {
    // Verifica se o parâmetro uid foi enviado
    const uid = data.uid;
    if (!uid) {
        throw new functions.https.HttpsError('invalid-argument', 'O uid é obrigatório.');
    }

    try {
        // Deleta o usuário do Firebase Authentication
        await admin.auth().deleteUser(uid);

        // Deleta todos os arquivos na pasta do usuário no Firebase Storage
        const bucket = admin.storage().bucket();
        const prefix = uid + '/'; // Supondo que os arquivos estejam organizados em uma pasta cujo nome é o uid
        const [files] = await bucket.getFiles({prefix});

        const deletePromises = files.map(file => file.delete());
        await Promise.all(deletePromises);

        return {success: true};
    } catch (error) {
        console.error("Erro ao excluir usuário:", error);
        throw new functions.https.HttpsError('unknown', 'Erro ao excluir usuário', error);
    }
});

// INICIO DE FUNÇÕES PARA CRIPTOGRAFIA

function getKey() {
    const raw = process.env.ENCRYPTION_KEY; // vem do runWith(secrets)
    if (!raw) throw new Error('Missing ENCRYPTION_KEY secret');
    const key = Buffer.from(raw, 'base64');
    if (key.length !== 32) throw new Error('ENCRYPTION_KEY inválida (precisa ter 32 bytes após base64-decoding)');
    return key;
}

// Retorna string base64: IV(12) + TAG(16) + CIPHERTEXT
function seal(plain) {
    if (plain == null || plain === '') return null;
    const key = getKey();
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
    const ct = Buffer.concat([cipher.update(String(plain), 'utf8'), cipher.final()]);
    const tag = cipher.getAuthTag();
    return Buffer.concat([iv, tag, ct]).toString('base64');
}

function open(sealed) {
    if (!sealed) return null;
    const key = getKey();
    const buf = Buffer.from(sealed, 'base64');
    const iv = buf.subarray(0, 12);
    const tag = buf.subarray(12, 28);
    const ct = buf.subarray(28);
    const dec = crypto.createDecipheriv('aes-256-gcm', key, iv);
    dec.setAuthTag(tag);
    return Buffer.concat([dec.update(ct), dec.final()]).toString('utf8');
}

async function assertCanManageCompany(context, targetCompanyId) {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Auth required');
    }

    const caller = context.auth.uid;
    if (caller === targetCompanyId) return;

    // Se tiver custom claim, libera
    if (context.auth.token && context.auth.token.gerenciarParceiros) return;

    // Procura permissão tanto em empresas quanto em users
    const empDoc = await admin.firestore().collection('empresas').doc(caller).get();
    if (empDoc.exists && empDoc.data()?.gerenciarParceiros) return;

    const userDoc = await admin.firestore().collection('users').doc(caller).get();
    if (userDoc.exists && userDoc.data()?.gerenciarParceiros) return;

    throw new functions.https.HttpsError('permission-denied', 'Sem permissão');
}

// Upsert com criptografia
exports.upsertCompanyPhoneConfig = functions
    .runWith({secrets: ['ENCRYPTION_KEY']})
    .https.onCall(async (data, context) => {
            const {companyId, phoneNumber, instanceId, token, clientToken, oldPhoneId} = data;
            await assertCanManageCompany(context, companyId);

            const onlyDigits = (s) => (s || '').toString().replace(/\D/g, '');
            const digits = onlyDigits(phoneNumber);
            if (!digits) throw new functions.https.HttpsError('invalid-argument', 'Número inválido');

            const phoneId = digits; // docId = número
            const col = admin.firestore().collection('empresas').doc(companyId).collection('phones');
            const payload = {
                phoneId,
                instanceId: seal(instanceId || ''),
                token: seal(token || ''),
                clientToken: seal(clientToken || ''),
                phone: digits,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            };

            // se trocou o número/docId, cria novo e apaga antigo
            if (oldPhoneId && oldPhoneId !== phoneId) {
                await col.doc(phoneId).set(payload, {merge: true});
                await col.doc(oldPhoneId).delete().catch(() => {
                });
            } else {
                await col.doc(phoneId).set(payload, {merge: true});
            }

            return {success: true, phoneId};
        }
    );

// Ler descriptografado (para preencher o formulário no Edit)
exports.getCompanyPhoneConfig = functions
    .runWith({secrets: ['ENCRYPTION_KEY']})
    .https.onCall(async (data, context) => {
        const {companyId} = data;
        await assertCanManageCompany(context, companyId);

        const snap = await admin.firestore()
            .collection('empresas').doc(companyId)
            .collection('phones').limit(1).get();

        if (snap.empty) return {exists: false};

        const d = snap.docs[0].data();
        return {
            exists: true,
            phoneId: d.phoneId,
            phone: d.phone || null,
            instanceId: openMaybe(d.instanceId),
            token: openMaybe(d.token),
            clientToken: openMaybe(d.clientToken),
        };
    });

function openMaybe(sealed) {
    if (!sealed) return '';
    try {
        const key = getKey();
        const buf = Buffer.from(sealed, 'base64');
        // tamanho mínimo: 12 (IV) + 16 (TAG) + 1 (CT)
        if (buf.length < 29) throw new Error('not sealed');
        const iv = buf.subarray(0, 12);
        const tag = buf.subarray(12, 28);
        const ct = buf.subarray(28);
        const dec = crypto.createDecipheriv('aes-256-gcm', key, iv);
        dec.setAuthTag(tag);
        return Buffer.concat([dec.update(ct), dec.final()]).toString('utf8');
    } catch {
        // valor antigo sem criptografia
        return String(sealed);
    }
}

// FIM DAS FUNCTIONS DE CRIPTOGRAFIA