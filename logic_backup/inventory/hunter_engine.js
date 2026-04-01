const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const axios = require('axios');
const { sendPushNotification } = require("../../services/notifications_service");

// إعدادات تيليجرام (نفس بياناتك بالظبط)
const TELEGRAM_TOKEN = "8678311363:AAHseL5dsO77gU5IsSBCveOIrNv22zzRfMw";
const OPERATIONS_CHAT_ID = "-1003818388213";

async function sendTelegramAlert(message) {
    try {
        await axios.post(`https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage`, {
            chat_id: OPERATIONS_CHAT_ID,
            text: message,
            parse_mode: "HTML"
        });
    } catch (e) { console.error("❌ Telegram Hunter Error:", e.message); }
}

function normalizeText(text) {
    if (!text) return "";
    return text.toLowerCase().replace(/\s+/g, '').replace(/[أإآ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي').replace(/[ًٌٍَُِّ]/g, '').trim();
}

// الدالة بتشتغل لما حالة المنتج تتغير لـ Active
exports.onProductBackInStock = onDocumentUpdated("productOffers/{productId}", async (event) => {
    const afterData = event.data.after.data();
    const beforeData = event.data.before.data();
    const db = admin.firestore();

    // نتحرك فقط لو المنتج بقى Active وكان قبل كدة حاجة تانية
    if (afterData.status === 'active' && beforeData.status !== 'active') {
        const productName = afterData.productName;
        const cleanName = normalizeText(productName);
        const productId = event.params.productId;

        try {
            // البحث عن الناس اللي مستنية المنتج ده في الـ waiting_list
            const waitingSnap = await db.collection('waiting_list')
                .where('status', '==', 'pending')
                .get();

            if (waitingSnap.empty) return null;

            for (const waitDoc of waitingSnap.docs) {
                const waitData = waitDoc.data();
                const cleanRequested = normalizeText(waitData.requestedItem);

                // مقارنة الأسماء (لو اسم المنتج فيه جزء من اللي العميل طالبه)
                if (cleanName.includes(cleanRequested) || cleanRequested.includes(cleanName)) {
                    
                    // 1. إشعار الموبايل (عن طريق Firebase FCM)
                    if (waitData.fcmToken) {
                        await sendPushNotification(
                            waitData.fcmToken,
                            "طلبك متاح الآن في رابية أحلى! ✨",
                            `يا ${waitData.userName || 'غالي'}، الـ [${productName}] بقى متاح دلوقتي. اطلبه فوراً!`,
                            { type: "item_back_in_stock", productId: productId }
                        );
                    }

                    // 2. إشعار تيليجرام للعمليات
                    const telegramMsg = `🎯 <b>صيد موفق (رادار النواقص)</b>\n━━━━━━━━━━━━━━\n✅ تم توفير: <b>${productName}</b>\n👤 للعميل: ${waitData.userName || 'N/A'}\n📞 هاتف: <code>${waitData.userPhone || 'N/A'}</code>\n🚀 تم إرسال إشعار للموبايل الآن.`;
                    await sendTelegramAlert(telegramMsg);

                    // 3. تحديث الداتابيز
                    await waitDoc.ref.update({
                        status: 'notified',
                        foundProductId: productId,
                        notifiedAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                }
            }
        } catch (error) {
            console.error("❌ Hunter Logic Error:", error);
        }
    }
    return null;
});

