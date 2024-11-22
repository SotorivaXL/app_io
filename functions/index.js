
const {onRequest} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

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
        const { empresaId, nomeCampanha, descricao, dataInicio, dataFim } = data;

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

        return { message: 'Campanha adicionada com sucesso.' };
    } catch (error) {
        console.error('Erro ao adicionar campanha:', error);
        throw new functions.https.HttpsError('internal', 'Erro ao adicionar campanha.');
    }
});

// Função para redirecionar o usuário após adicionar o lead
function redirectAfterAddLead(res, redirectUrl) {
    res.status(200).send(`
        <html>
            <head>
                <script type="text/javascript">
                    window.location.href = "${redirectUrl}";
                </script>
            </head>
            <body>
                Redirecionando...
            </body>
        </html>
    `);
}

// Função principal addLead
exports.addLead = functions.https.onRequest(async (req, res) => {
    try {
        const empresaId = req.body.empresa_id;
        const campanhaId = req.body.nome_campanha;

        if (!empresaId || !campanhaId) {
            res.status(400).send('empresa_id e nome_campanha são necessários.');
            return;
        }

        const leadData = {
            ...req.body,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
        };

        const leadsCollectionRef = admin
            .firestore()
            .collection('empresas')
            .doc(empresaId)
            .collection('campanhas')
            .doc(campanhaId)
            .collection('leads');

        await leadsCollectionRef.add(leadData);

        // Redirecionar após adicionar o lead
        const redirectUrl = req.body.redirect_url;
        redirectAfterAddLead(res, redirectUrl);

    } catch (error) {
        console.error('Erro ao adicionar lead:', error);
        res.status(500).send('Erro ao adicionar lead.');
    }
});

exports.getEmpresaCampanha = functions.https.onRequest(async (req, res) => {
    try {
        const { empresaId } = req.query;

        // Fetch the Empresa data
        const empresaDoc = await admin.firestore().collection('empresas').doc(empresaId).get();
        if (!empresaDoc.exists) {
            return res.status(404).json({ error: 'Empresa not found' });
        }
        const empresaData = empresaDoc.data();

        // Fetch all Campanha data within the Empresa
        const campanhasSnapshot = await admin.firestore().collection('empresas').doc(empresaId).collection().get();
        const campanhasData = campanhasSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));

        return res.status(200).json({
            empresa: empresaData,
            campanhas: campanhasData,
        });
    } catch (error) {
        console.error('Error fetching data:', error);
        return res.status(500).json({ error: 'Internal Server Error' });
    }
});

// Funções CRUD para a coleção de empresas

// Read (Ler todas as empresas)
exports.getCompanies = functions.https.onRequest(async (req, res) => {
    try {
        const snapshot = await admin.firestore().collection('empresas').get();
        const companies = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));

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

        const { companyId, NomeEmpresa, contract, countArtsValue, countVideosValue, dashboard, leads, gerenciarColaboradores, gerenciarParceiros } = req.body;

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

        res.status(200).send({ success: true, message: "Empresa atualizada com sucesso!" });
    } catch (error) {
        console.error("Error updating company:", error);
        res.status(500).send("Erro ao atualizar empresa");
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

        // 3. Buscar todos os usuários com 'createdBy' igual ao companyId
        const usersSnapshot = await admin.firestore()
            .collection('users')
            .where('createdBy', '==', companyId)
            .get();

        const userUids = [];

        usersSnapshot.forEach(doc => {
            const uid = doc.id; // Usando o ID do documento como UID do usuário
            if (uid) {
                userUids.push(uid);
            }
        });

        // 4. Deletar usuários do Firebase Authentication e Firestore
        for (const uid of userUids) {
            try {
                // Deletar do Firebase Authentication
                await admin.auth().deleteUser(uid);
                console.log(`Usuário ${uid} deletado do Authentication.`);

                // Deletar do Firestore
                await admin.firestore().collection('users').doc(uid).delete();
                console.log(`Usuário ${uid} deletado do Firestore.`);
            } catch (error) {
                console.error(`Erro ao deletar usuário ${uid}:`, error);
                // Continua tentando com os próximos usuários
            }
        }

        return { success: true, message: 'Empresa e usuários vinculados excluídos com sucesso.' };
    } catch (error) {
        console.error('Erro ao excluir empresa e usuários vinculados:', error);
        throw new functions.https.HttpsError('unknown', 'Erro ao excluir empresa e usuários vinculados.');
    }
});

exports.createUserAndCompany = functions.https.onCall(async (data, context) => {
    // Verifica se o usuário está autenticado
    if (!context.auth) {
        throw new functions.https.HttpsError('failed-precondition', 'A função deve ser chamada enquanto autenticado.');
    }

    const { email, password, nomeEmpresa, name, role, birth, founded, cnpj, accessRights, contract, countArtsValue, countVideosValue } = data;

    try {
        // Cria o novo usuário
        const userRecord = await admin.auth().createUser({
            email: email,
            password: password,
            emailVerified: false,
            disabled: false,
        });

        // Verifica se o CNPJ está presente para decidir entre empresa e colaborador
        if (cnpj) {
            // Adiciona os dados da empresa no Firestore
            await admin.firestore().collection('empresas').doc(userRecord.uid).set({
                NomeEmpresa: nomeEmpresa,
                email: email,
                cnpj: cnpj,
                founded: founded,
                dashboard: accessRights.dashboard || false,
                leads: accessRights.leads || false,
                gerenciarColaboradores: accessRights.gerenciarColaboradores || false,
                gerenciarParceiros: accessRights.gerenciarParceiros || false,
                configurarDash: accessRights.configurarDash || false,
                copiarTelefones: accessRights.copiarTelefones || false,
                criarCampanha: accessRights.criarCampanha || false,
                criarForm: accessRights.criarForm || false,
                contract: contract || '',
                countArtsValue: countArtsValue || 0,
                countVideosValue: countVideosValue || 0,
                isDevAccount: false,
            });

            return { success: true, message: 'Usuário e empresa criados com sucesso.' };
        } else {
            // Adiciona os dados do colaborador no Firestore na coleção 'users'
            await admin.firestore().collection('users').doc(userRecord.uid).set({
                name: name,
                email: email,
                role: role,
                birth: birth,
                dashboard: accessRights.dashboard || false,
                leads: accessRights.leads || false,
                configurarDash: accessRights.configurarDash || false,
                copiarTelefones: accessRights.copiarTelefones || false,
                criarCampanha: accessRights.criarCampanha || false,
                criarForm: accessRights.criarForm || false,
                createdBy: context.auth.uid,
            });

            return { success: true, message: 'Usuário colaborador criado com sucesso.' };
        }
    } catch (error) {
        throw new functions.https.HttpsError('internal', 'Erro ao criar usuário ou empresa.', error);
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
        await admin.auth().setCustomUserClaims(uid, { companyId });

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
    const { empresaId, nome_campanha, descricao, dataInicio, dataFim } = data;

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

        return { message: 'Campanha adicionada com sucesso!' };
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

        return { success: true };
    } catch (error) {
        console.error('Erro ao deletar o usuário:', error);
        throw new functions.https.HttpsError('internal', 'Erro ao deletar o usuário.');
    }
});

exports.sendNewLeadNotification = functions.firestore
  .document('empresas/{empresaId}/campanhas/{campanhaId}/leads/{leadId}')
  .onCreate(async (snap, context) => {
    const newValue = snap.data();
    const empresaId = context.params.empresaId;
    const campanhaId = context.params.campanhaId;

    // Recuperar o nome da campanha
    const campanhaDoc = await admin.firestore()
      .collection('empresas')
      .doc(empresaId)
      .collection('campanhas')
      .doc(campanhaId)
      .get();

    const nomeCampanha = campanhaDoc.data().nome_campanha;

    const tokens = [];

    // Buscar o documento do usuário que tem o mesmo ID da empresa
    const userSnapshot = await admin.firestore().collection('empresas').doc(empresaId).get();

    if (userSnapshot.exists) {
      const userDoc = userSnapshot.data();

      // Verificar se o documento do usuário tem um fcmToken e adicioná-lo à lista de tokens
      if (userDoc.fcmToken) {
        tokens.push(userDoc.fcmToken);
      }

      // Buscar o documento da empresa para obter o fcmToken
      const empresaDoc = await admin.firestore().collection('empresas').doc(empresaId).get();
      if (empresaDoc.exists && empresaDoc.data().fcmToken) {
        tokens.push(empresaDoc.data().fcmToken);
      }
    } else {
      console.log(`Usuário com ID ${empresaId} não encontrado.`);
    }

    // Buscar os tokens FCM dos usuários da empresa na coleção 'users'
    const usersSnapshot = await admin.firestore().collection('users')
      .where('createdBy', '==', empresaId)
      .get();

    usersSnapshot.forEach(doc => {
      if (doc.data().fcmToken) {
        tokens.push(doc.data().fcmToken);
      }
    });

    if (tokens.length > 0) {
      // Enviar a notificação para os tokens
      const payload = {
        notification: {
          title: 'Novo Lead!',
          body: `Você tem um novo lead na campanha ${nomeCampanha}`,
        },
      };

      return admin.messaging().sendToDevice(tokens, payload);
    } else {
      console.log('Nenhum token FCM encontrado.');
      return null;
    }
});

exports.deleteUserByEmail = functions.https.onCall(async (data, context) => {
    const email = data.email;

    try {
        const userRecord = await admin.auth().getUserByEmail(email);
        await admin.auth().deleteUser(userRecord.uid);
        return { message: 'Usuário excluído com sucesso' };
    } catch (error) {
        return { error: 'Erro ao excluir o usuário: ' + error.message };
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
        await admin.auth().updateUser(uid, { password: newPassword });
        return { message: 'Senha atualizada com sucesso' };

    } catch (error) {
        if (error instanceof functions.https.HttpsError) {
            throw error;
        } else {
            throw new functions.https.HttpsError('unknown', error.message);
        }
    }
});