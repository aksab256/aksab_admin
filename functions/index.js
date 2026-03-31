const admin = require("firebase-admin");

// 1. Initialize Firebase Admin (مرة واحدة فقط للمشروع بالكامل)
if (admin.apps.length === 0) {
    admin.initializeApp();
}

// 2. استيراد ملفات المنطق (Logic Files)
// تأكد إن المسارات دي صحيحة في الفولدر عندك
const authLogic = require("./logic/auth_logic");
const notificationsLogic = require("./logic/notifications_logic");

// 3. تصدير الدوال للسحابة (الأسماء اللي بتظهر في Firebase Console)

// 🛡️ دوال الصلاحيات والاشتراك التلقائي (القديمة)
// ده هيصدر كل الدوال اللي جوه auth_logic (زي autoSubscribeOnSignup)
exports.auth = authLogic;

// 📢 دوال إرسال الإشعارات والترويج (الجديدة)
// ده هيصدر الدالة المسؤولة عن مراقبة push_notifications وإرسالها
exports.notifications = notificationsLogic;

