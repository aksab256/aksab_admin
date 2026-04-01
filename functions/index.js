const admin = require("firebase-admin");

// 🛡️ تهيئة ذاتية للملف لضمان عدم الاعتماد على ملف خارجي
if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();

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
        console.error("❌ Error fetching promotions:", error);
        return [];
    }
}

/**
 * دالة منطق الهدايا (يمكن توسيعها مستقبلاً)
 */
function applyPromotionsLogic(items, total, promotions, sellerId) {
    return items; 
}

/**
 * 🎯 الدالة الرئيسية: تنفيذ "تأمين عهدة الطلب"
 * يتم استدعاؤها من index.js
 */
exports.createOrderWithPromos = async (data, userIdFromAuth) => {
    // استلام البيانات من طلب Flutter
    const { ordersData } = data;
    const userId = data.userId || userIdFromAuth;
    let cashbackToReserve = parseFloat(data.cashbackToReserve) || 0;

    if (!userId || !ordersData) {
        throw new Error("بيانات الطلب أو معرف المستخدم ناقصة.");
    }

    const activePromotions = await getActivePromotions(db);
    const userRef = db.collection('users').doc(userId);
    const ledgerRef = db.collection('transactionsLedger');
    let successfulOrders = [];

    try {
        await db.runTransaction(async (transaction) => {
            // أ. التحقق من رصيد الكاش باك (نقاط الأمان)
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) throw new Error("USER_NOT_FOUND");

            const userData = userDoc.data();
            const currentCashback = userData.cashback || 0;

            if (currentCashback < cashbackToReserve) {
                throw new Error("رصيد الكاش باك غير كافٍ لتأمين العهدة.");
            }

            // ب. خصم من الكاش باك وحجز في "نقاط الأمان"
            if (cashbackToReserve > 0) {
                transaction.update(userRef, {
                    cashback: admin.firestore.FieldValue.increment(-cashbackToReserve),
                    cashbackReserved: admin.firestore.FieldValue.increment(cashbackToReserve)
                });

                // ج. توثيق العملية في سجل العمليات (Ledger)
                const newLedgerDoc = ledgerRef.doc();
                transaction.set(newLedgerDoc, {
                    userId: userId,
                    type: 'CASHBACK_RESERVATION',
                    amount: cashbackToReserve,
                    status: 'RESERVED',
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    description: `تأمين عهدة طلب جديد - رقم الوثيقة: ${newLedgerDoc.id}`
                });
            }

            // د. إنشاء مستندات الطلب لكل تاجر في السلة
            for (const orderData of ordersData) {
                const orderTotal = orderData.total || 0;

                const itemsAfterPromotion = applyPromotionsLogic(
                    orderData.items || [],
                    orderTotal,
                    activePromotions,
                    orderData.sellerId
                );

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
        // إلقاء الخطأ ليعود لـ Flutter بشكل صحيح
        throw error;
    }
};

