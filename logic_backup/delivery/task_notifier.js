const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
// بننادي الخدمة اللي بتشحن لـ Firebase
const { sendPushNotification } = require("../../services/notifications_service");

exports.notifyRepOnNewTask = onDocumentCreated("waitingdelivery/{orderId}", async (event) => {
    const taskData = event.data.data();
    const orderId = event.params.orderId;
    const repCode = taskData.repCode;

    if (!repCode) return null;

    const db = admin.firestore();

    try {
        // 1. البحث عن المندوب (بنفس الطريقة اللي بتحبها)
        const repQuery = await db.collection('deliveryReps')
            .where('repCode', '==', repCode.toString())
            .limit(1)
            .get();

        if (repQuery.empty) return null;

        const repDoc = repQuery.docs[0];
        const repData = repDoc.data();
        
        // 2. سحب التوكن بتاع Firebase (FCM Token) 
        // تأكد إن الحقل ده اسمه fcmToken في داتابيز المناديب عندك
        const fcmToken = repData.fcmToken; 

        if (fcmToken) {
            const repName = repData.fullname || "كابتن";
            const buyerName = taskData.buyer?.name || "عميل جديد";

            // 3. النداء على الخدمة الجاهزة اللي بتبعت لـ Firebase
            await sendPushNotification(
                fcmToken, // التوكن الجديد
                "مهمة توصيل جديدة 🚚",
                `يا ${repName}، عندك طلب للعميل ${buyerName}`,
                { 
                    type: 'new_task_assigned', 
                    orderId: orderId 
                }
            );
            console.log(`✅ إشعار Firebase وصل للمندوب: ${repName}`);
        }
    } catch (error) {
        console.error("❌ خطأ في إرسال إشعار التوصيل:", error);
    }
});

