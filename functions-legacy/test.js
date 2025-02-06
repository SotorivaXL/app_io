const admin = require('firebase-admin');
admin.initializeApp();

console.log("Chaves em admin.messaging():", Object.keys(admin.messaging()));
