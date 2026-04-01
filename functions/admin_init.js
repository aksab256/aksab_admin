const admin = require("firebase-admin");

// أضمن طريقة للتحقق من التهيئة في بيئة Cloud Functions
if (admin.apps.length === 0) {
    admin.initializeApp();
}

const db = admin.firestore();

// تصدير الكائنات للاستخدام في باقي المشروع
module.exports = { admin, db };

