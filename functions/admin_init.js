const admin = require("firebase-admin");

// التحقق من أن التطبيق لم يتم تهيئته مسبقاً
if (!admin.apps.length) {
    admin.initializeApp();
}

const db = admin.firestore();

// تصدير الأدوات لاستخدامها في باقي الملفات
module.exports = { admin, db };

