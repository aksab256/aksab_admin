const admin = require("firebase-admin");

/**
 * 🚀 خدمة إشعارات بلازا الموحدة
 * البديل الرسمي لـ AWS Lambda & SNS
 */
async function sendOrderNotifications(order, eventType) {
    const db = admin.firestore();
    const buyerId = order.buyer?.id || order.userId;
    const sellerId = order.sellerId || order.supermarketId;
    const driverId = order.driverId;

    let title = "";
    let body = "";
    let targetId = "";

    // 1. تحديد محتوى الرسالة بناءً على النوع (نفس قاموسك القديم)
    if (eventType === 'new_order') {
        title = "رابية أحلى: طلب جديد! 📦";
        body = `وصلك طلب جديد بقيمة ${order.totalAmount || 0} ج.م.`;
        targetId = sellerId;
    } else if (eventType === 'delivered') {
        title = "تم التسليم بنجاح ✅";
        body = `شكراً لثقتك! تم إتمام طلبك بنجاح.`;
        targetId = buyerId;
    }
    // ... تقدر تضيف بقية الحالات من ملف notifications.js القديم هنا بنفس النمط

    if (!targetId || !title) return;

    try {
        // 2. جلب التوكن (FCM Token) الخاص بالمستخدم من جدول UserEndpoints
        const userDoc = await db.collection('UserEndpoints').doc(targetId).get();
        const fcmToken = userDoc.exists ? userDoc.data().fcmToken : null;

        // 3. التسجيل في Firestore للشفافية
        await db.collection('notifications').add({
            userId: targetId,
            title: title,
            body: body,
            orderId: order.id || null,
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp()
        });

        // 4. الإرسال الفعلي عبر جوجل (FCM)
        if (fcmToken) {
            const message = {
                notification: { title, body },
                token: fcmToken,
                data: { orderId: String(order.id || ""), type: eventType }
            };
            await admin.messaging().send(message);
            console.log(`✅ إشعار بلازا وصل لـ ${targetId}`);
        }
    } catch (e) {
        console.error("❌ فشل إرسال إشعار بلازا:", e);
    }
}

module.exports = { sendOrderNotifications };

