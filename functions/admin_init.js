const admin = require("firebase-admin");
const path = require("path");

// مسار ملف serviceAccountKey.json
// لو موجود جوه نفس فولدر functions
const serviceAccountPath = path.join(__dirname, "serviceAccountKey.json");

// تهيئة Firebase بطريقة آمنة
if (!admin.apps.length) {
    try {
        const serviceAccount = require(serviceAccountPath);

        admin.initializeApp({
            credential: admin.credential.cert(serviceAccount),
            // لو انت عايز تستخدم Realtime Database:
            // databaseURL: "https://<YOUR_PROJECT_ID>.firebaseio.com"
        });

        console.log("✅ Firebase app initialized successfully");
    } catch (err) {
        console.error("❌ Firebase initialization error:", err);
        process.exit(1); // يوقف العملية لو فيه مشكلة
    }
}

// تصدير الـ admin و db للاستخدام في أي ملف
const db = admin.firestore();

module.exports = { admin, db };
