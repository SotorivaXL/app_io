const admin = require('firebase-admin');
const serviceAccount = require('app-io-1c16f-firebase-adminsdk-nj5oz-ff36796da0.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    databaseURL: 'https://app-io-1c16f-default-rtdb.firebaseio.com'
});

const functions = require('firebase-functions');

// Exemplo de uso do Firebase Admin SDK
const db = admin.firestore();

exports.setCustomUserClaims = functions.https.onCall(async (data, context) => {
    try {
        // Define as custom claims para o usuário
        await admin.auth().setCustomUserClaims(data.uid, {
            dashboard: data.dashboard || false,
            leads: data.leads || false,
            gerenciarColaboradores: data.gerenciarColaboradores || false,
            gerenciarParceiros: data.gerenciarParceiros || false
        });

        // Atualiza as permissões no Firestore
        await db.collection('empresas').doc(data.uid).update({
            dashboard: data.dashboard || false,
            leads: data.leads || false,
            gerenciarColaboradores: data.gerenciarColaboradores || false,
            gerenciarParceiros: data.gerenciarParceiros || false
        });

        return {
            message: `Success! Permissions have been set for user ${data.uid}.`
        };
    } catch (err) {
        return {
            error: err.message
        };
    }
});
