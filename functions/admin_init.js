const admin = require("firebase-admin");

// وظيفة لتهيئة التطبيق وضمان وجوده
function getFirestore() {
  if (admin.apps.length === 0) {
    admin.initializeApp();
    console.log("✅ Firebase Admin Initialized Successfully");
  }
  return admin.firestore();
}

// تصدير admin و db (بحيث db تنادي الدالة وتجيب الـ instance المظبوط)
module.exports = {
  admin: admin,
  get db() {
    return getFirestore();
  }
};

