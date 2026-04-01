const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

exports.autoSubscribeOnSignup = onDocumentCreated("users/{userId}", async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const userData = snapshot.data();
    const token = userData.fcmToken;
    const role = userData.role; // مثلاً: driver, retailer, buyer

    if (!token || !role) return;

    try {
        // 1. الاشتراك الفعلي في FCM
        await admin.messaging().subscribeToTopic(token, "all_users");
        await admin.messaging().subscribeToTopic(token, role);

        // 2. 🎯 الحركة الصايعة: تسجيل التوبيك في كولكشن الإدارة
        const topicRef = admin.firestore().collection('notification_topics').doc(role);
        const doc = await topicRef.get();

        if (!doc.exists) {
            await topicRef.set({
                'name': role.charAt(0).toUpperCase() + role.slice(1), // بيخلي أول حرف Capital للشياكة
                'createdAt': admin.firestore.FieldValue.serverTimestamp(),
                'type': 'auto_generated'
            });
            console.log(`✨ تم إضافة توبيك جديد لقائمة الإدارة: ${role}`);
        }

        // تسجيل توبيك all_users برضه لو مش موجود
        await admin.firestore().collection('notification_topics').doc('all_users').set({
            'name': 'كل المستخدمين',
            'type': 'system'
        }, { merge: true });

        console.log(`✅ تم اشتراك ${event.params.userId} وتحديث القائمة.`);
    } catch (error) {
        console.error("❌ خطأ:", error);
    }
});

