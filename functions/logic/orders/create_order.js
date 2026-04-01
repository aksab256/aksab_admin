const admin = require("firebase-admin");

// تهيئة ذاتية لكل ملف لضمان الاستقلالية
if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();

/**
 * دالة جلب العروض النشطة
 */
async function getActivePromotions(db) {
    const snapshot = await db.collection("giftPromos").where("isActive", "==", true).get();
    return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
}

/**
 * دالة إنشاء الطلب وتطبيق الهدايا وخصم الكاش باك
 */
exports.createOrderWithPromos = async (data, userIdFromAuth) => {
    const { ordersData } = data;
    const userId = data.userId || userIdFromAuth;
    let cashbackToReserve = parseFloat(data.cashbackToReserve) || 0;

    const activePromotions = await getActivePromotions(db);
    const userRef = db.collection('users').doc(userId);
    const ledgerRef = db.collection('transactionsLedger');
    let successfulOrders = [];

    try {
        await db.runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) throw new Error("USER_NOT_FOUND");

            const userData = userDoc.data();
            const currentCashback = userData.cashback || 0;

            if (currentCashback < cashbackToReserve) {
                throw new Error("INSUFFICIENT_CASHBACK");
            }

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
                    description: `تأمين عهدة طلب جديد رقم ${newLedgerDoc.id}`
                });
            }

            for (const orderData of ordersData) {
                const orderRef = db.collection('orders').doc();
                transaction.set(orderRef, {
                    ...orderData,
                    orderId: orderRef.id,
                    buyerId: userId,
                    status: 'new-order',
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    isCashbackReserved: cashbackToReserve > 0
                });
                successfulOrders.push(orderRef.id);
            }
        });

        return { success: true, orderIds: successfulOrders, cashbackReserved: cashbackToReserve };
    } catch (error) {
        console.error("❌ Order Transaction Failed:", error.message);
        throw error;
    }
};

