const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

exports.sendPromoNotification = onDocumentCreated("push_notifications/{docId}", async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const data = snapshot.data();
    
    // التأكد إن الحالة "pending" عشان ما نبعتش مرتين (حماية إضافية)
    if (data.status !== 'pending') return;

    const topic = data.topic;
    const title = data.title || "أكسب 💰";
    const message = data.message;
    const imageUrl = data.image; // رابط الصورة من Firebase Storage اللي رفعناه في الفلوتر
    const extraData = data.data || {}; // مثلاً {screen: 'Home'}

    if (!topic || !message) {
        console.log("⚠️ بيانات الإشعار غير مكتملة.");
        return;
    }

    // بناء محتوى الإشعار (Message Payload)
    const payload = {
        notification: {
            title: title,
            body: message,
        },
        topic: topic,
        // إضافة الصورة والبيانات الإضافية
        data: {
            ...extraData,
            click_action: "FLUTTER_NOTIFICATION_CLICK",
        }
    };

    // لو فيه صورة، ضيفها للـ notification (للأندرويد والـ iOS)
    if (imageUrl) {
        payload.notification.imageUrl = imageUrl;
    }

    try {
        // 🚀 الإرسال الفعلي عبر سيرفرات جوجل (FCM)
        const response = await admin.messaging().send(payload);
        console.log(`✅ تم إرسال الإشعار بنجاح للتوبيك [${topic}]:`, response);

        // تحديث حالة الوثيقة في Firestore بعد النجاح
        await snapshot.ref.update({
            status: 'completed',
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            messageId: response
        });

    } catch (error) {
        console.error("❌ فشل إرسال الإشعار:", error);
        
        // تحديث الحالة للفشل عشان الآدمن يعرف
        await snapshot.ref.update({
            status: 'failed',
            error: error.message
        });
    }
});

