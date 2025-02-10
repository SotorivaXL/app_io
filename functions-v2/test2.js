const admin = require('firebase-admin');
admin.initializeApp();
const messaging = admin.messaging();

console.log("Propriedades próprias:", Object.keys(messaging));
console.log("Propriedades no protótipo:", Object.getOwnPropertyNames(Object.getPrototypeOf(messaging)));
