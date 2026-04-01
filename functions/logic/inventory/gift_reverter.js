const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const { FieldValue } = require("firebase-admin/firestore");

exports.revertGiftsOnCancellation = onDocumentUpdated("orders/{orderId}", async (event) => {
    const orderId = event.params.orderId;
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    const db = admin.firestore();

    // 1. التحقق من تغيير الحالة إلى cancelled ومنع التكرار
    const oldStatus = beforeData.status?.toLowerCase().trim();
    const newStatus = afterData.status?.toLowerCase().trim();
    const isAlreadyReverted = afterData.giftStockReverted === true;

    if (newStatus === 'cancelled' && oldStatus !== 'cancelled' && !isAlreadyReverted) {
        console.log(`🔍 [Gifts] Cancellation detected for Order ${orderId}.`);

        const giftsToRevert = (afterData.items || []).filter(item => item.isGift === true && item.promoId);

        // لو مفيش هدايا، بنقفل الملف برضه عشان ما نرجعش نشيك تاني
        if (giftsToRevert.length === 0) {
            await event.data.after.ref.update({ giftStockReverted: true });
            return null;
        }

        // 2. تجميع الهدايا (نفس منطق الـ EC2 بالظبط)
        const promoReversionMap = giftsToRevert.reduce((acc, giftItem) => {
            const promoId = giftItem.promoId;
            const qty = giftItem.quantity || 0;
            const val = (giftItem.priceForReport || 0) * qty;

            if (!acc[promoId]) acc[promoId] = { quantity: 0, value: 0 };
            acc[promoId].quantity += qty;
            acc[promoId].value += val;
            return acc;
        }, {});

        // 3. تنفيذ العملية بنظام الـ Batch (نفس أسماء الحقول: giftPromos)
        const batch = db.batch();
        
        for (const promoId in promoReversionMap) {
            const { quantity, value } = promoReversionMap[promoId];
            const promoRef = db.collection("giftPromos").doc(promoId);
            
            batch.update(promoRef, {
                usedQuantity: FieldValue.increment(-quantity),
                totalGiftValue: FieldValue.increment(-value)
            });
        }

        // وضع علامة الإرجاع النهائية
        batch.update(event.data.after.ref, { giftStockReverted: true });

        try {
            await batch.commit();
            console.log(`🎉 [Gifts] Successfully reverted stock for Order ${orderId}`);
        } catch (error) {
            console.error(`❌ [Gifts] Batch Error for Order ${orderId}:`, error);
        }
    }
    return null;
});

