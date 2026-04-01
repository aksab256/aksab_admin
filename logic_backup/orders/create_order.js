const { admin, db } = require("../../admin_init");

/**
 * دالة إنشاء الطلب وتطبيق الهدايا وخصم الكاش باك (كلها في Firestore)
 */
exports.createOrderWithPromos = async (requestData, userId) => {
    const { ordersData } = requestData;
    let cashbackToReserve = parseFloat(requestData.cashbackToReserve) || 0;

    // 1. جلب العروض النشطة (Firestore Only)
    const activePromotions = await getActivePromotions(db);

    const userRef = db.collection('users').doc(userId);
    const ledgerRef = db.collection('transactionsLedger'); // البديل لـ DynamoDB
    let successfulOrders = [];

    try {
        await db.runTransaction(async (transaction) => {
            // أ. التحقق من رصيد المستخدم
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) throw new Error("USER_NOT_FOUND");

            const userData = userDoc.data();
            const currentCashback = userData.cashback || 0;

            if (currentCashback < cashbackToReserve) {
                throw new Error("INSUFFICIENT_CASHBACK");
            }

            // ب. تحديث رصيد الكاش باك (خصم وحجز)
            if (cashbackToReserve > 0) {
                transaction.update(userRef, {
                    cashback: admin.firestore.FieldValue.increment(-cashbackToReserve),
                    cashbackReserved: admin.firestore.FieldValue.increment(cashbackToReserve)
                });

                // ج. توثيق العملية في الـ Ledger (داخل نفس المعاملة!)
                const newLedgerDoc = ledgerRef.doc();
                transaction.set(newLedgerDoc, {
                    userId: userId,
                    type: 'CASHBACK_RESERVATION',
                    amount: cashbackToReserve,
                    status: 'RESERVED',
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    description: `حجز كاش باك لطلب جديد رقم ${newLedgerDoc.id}`
                });
            }

            // د. معالجة الطلبات لكل تاجر
            for (const orderData of ordersData) {
                const orderTotal = orderData.total || 0;
                
                // تطبيق منطق الهدايا
                const itemsAfterPromotion = applyPromotionsLogic(
                    orderData.items || [],
                    orderTotal,
                    activePromotions,
                    orderData.sellerId
                );

                // تحديث مخزون الهدايا وإحصائيات العرض
                const gifts = itemsAfterPromotion.filter(i => i.isGift);
                for (const gift of gifts) {
                    const promoRef = db.collection("giftPromos").doc(gift.promoId);
                    transaction.update(promoRef, {
                        usedQuantity: admin.firestore.FieldValue.increment(gift.quantity),
                        totalGiftValue: admin.firestore.FieldValue.increment((gift.priceForReport || 0) * gift.quantity),
                        totalOrderValue: admin.firestore.FieldValue.increment(orderTotal)
                    });
                }

                // إنشاء وثيقة الطلب
                const orderRef = db.collection('orders').doc();
                transaction.set(orderRef, {
                    ...orderData,
                    orderId: orderRef.id,
                    items: itemsAfterPromotion,
                    buyerId: userId,
                    status: 'new-order',
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    isCashbackReserved: cashbackToReserve > 0
                });
                successfulOrders.push(orderRef.id);
            }
        });

        return { 
            success: true, 
            orderIds: successfulOrders, 
            cashbackReserved: cashbackToReserve 
        };

    } catch (error) {
        console.error("❌ Order Transaction Failed:", error.message);
        throw error;
    }
};

