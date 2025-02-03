importScripts('https://www.gstatic.com/firebasejs/9.6.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.6.1/firebase-messaging-compat.js');

// Configuração do Firebase
const firebaseConfig = {
    apiKey: "AIzaSyBx4PK6qJ808RewLurHS_6KYixVQ98OlU0",
    authDomain: "app-io-1c16f.firebaseapp.com",
    databaseURL: "https://app-io-1c16f-default-rtdb.firebaseio.com",
    projectId: "app-io-1c16f",
    storageBucket: "app-io-1c16f.appspot.com",
    messagingSenderId: "148670195922",
    appId: "1:148670195922:web:1d70121879d973f975a50b",
    measurementId: "G-ED88PRTRY3"
};

// Inicialize o Firebase
firebase.initializeApp(firebaseConfig);

// Inicialize o Firebase Messaging
const messaging = firebase.messaging();

// Escute mensagens em segundo plano
messaging.onBackgroundMessage((payload) => {
    console.log('[firebase-messaging-sw.js] Received background message: ', payload);
    const notificationTitle = payload.notification.title;
    const notificationOptions = {
        body: payload.notification.body,
        icon: '/icons/icon-192x192.png', // Substitua pelo caminho do seu ícone
    };

    self.registration.showNotification(notificationTitle, notificationOptions);
});