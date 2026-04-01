const { admin, db } = require("../../admin_init");

/**
 * دالة جلب العروض النشطة (Gift Promotions)
 */
async function getActivePromotions(db) {
    try {
        const snapshot = await db.collection("giftPromos")
            .where("isActive", "==", true)
            .get();
        return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    } catch (error) {
        console.error("Error fetching promotions:", error);
        return [];
    }
}

/**
 * منطق تطبيق الهدايا تلقائياً (يمكن توسيعه لاحقاً)
 */
function applyPromotionsLogic(items, total, promotions, sellerId) {
    // حالياً نمرر العناصر كما هي، مع الاحتفاظ بالعناصر التي تم تحديدها ككادو من الفرونت إند
    return items;
}

/**
 * 🎯 الدالة الرئيسية: orders_createSecureOrder
 * ملاحظة: يتم تصديرها بهذا الاسم ليتم استدعاؤها من Flutter
 */
exports.createOrderWithPromos = async (data, context) => {
    // 💡 في Cloud Functions (Callable), البيانات تأتي مباشرة في أول بارامتر (data)
    // والـ context يحتوي على بيانات التوثيق (auth)
    
    const userId = data.userId || (context.auth ? context.auth.uid : null);
    const { ordersData } = data;
    let cashbackToReserve = parseFloat(data.cashbackToReserve) || 0;

    if (!userId || !ordersData) {
        throw new Error("بيانات الطلب ناقصة (Missing userId or ordersData)");
    }

    const activePromotions = await getActivePromotions(db);
    const userRef = db.collection('users').doc(userId);
    const ledgerRef = db.collection('transactionsLedger');
    let successfulOrders = [];

    try {
        await db.runTransaction(async (transaction) => {
            // أ. التحقق من رصيد الكاش باك
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) throw new Error("USER_NOT_FOUND");

            const userData = userDoc.data();
            const currentCashback = userData.cashback || 0;

            if (currentCashback < cashbackToReserve) {
                throw new Error("INSUFFICIENT_CASHBACK");
            }

            // ب. تنفيذ "تأمين العهدة" (خصم وحجز الكاش باك)
            if (cashbackToReserve > 0) {
                transaction.update(userRef, {
                    cashback: admin.firestore.FieldValue.increment(-cashbackToReserve),
                    cashbackReserved: admin.firestore.FieldValue.increment(cashbackToReserve)
                });

                const newLedgerDoc = ledgerRef.doc();
                transaction.set(newLedgerDoc, {
                    userId: userId,
                    type: 'CASHBACK_RESERVATION',
                    amount: cashbackToReserve,
                    status: 'RESERVED',
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    description: `تأمين عهدة (نقاط أمان) لطلب جديد رقم ${newLedgerDoc.id}`
                });
            }

            // ج. إنشاء الطلبات لكل تاجر
            for (const orderData of ordersData) {
                const orderTotal = orderData.total || 0;

                const itemsAfterPromotion = applyPromotionsLogic(
                    orderData.items || [],
                    orderTotal,
                    activePromotions,
                    orderData.sellerId
                );

                // د. تحديث إحصائيات الهدايا إذا وجدت
                const gifts = itemsAfterPromotion.filter(i => i.isGift);
                for (const gift of gifts) {
                    if (gift.promoId) {
                        const promoRef = db.collection("giftPromos").doc(gift.promoId);
                        transaction.update(promoRef, {
                            usedQuantity: admin.firestore.FieldValue.increment(gift.quantity || 1),
                            totalOrderValue: admin.firestore.FieldValue.increment(orderTotal)
                        });
                    }
                }

                // هـ. حفظ وثيقة الطلب النهائية
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
        console.error("❌ Transaction Failed:", error.message);
        throw new admin.functions.HttpsError('internal', error.message);
    }
};

