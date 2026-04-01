const { onCall } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

// 1. تهيئة الفايربيز (مرة واحدة وشاملة)
if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();

// إعدادات السيرفر
setGlobalOptions({ region: "us-central1", memory: "256MiB" });

/**
 * 🎯 الجوهرة: orders_createSecureOrder
 * المنطق بالكامل هنا لضمان النجاح 100% بدون ملفات خارجية
 */
exports.orders_createSecureOrder = onCall(async (request) => {
    const data = request.data;
    const authUid = request.auth ? request.auth.uid : null;
    
    const { ordersData } = data;
    const userId = data.userId || authUid;
    let cashbackToReserve = parseFloat(data.cashbackToReserve) || 0;

    if (!userId || !ordersData) {
        throw new Error("بيانات الطلب ناقصة (Missing userId or ordersData)");
    }

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

            // ب. تأمين العهدة (خصم وحجز)
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
                    description: `تأمين عهدة لطلب جديد رقم ${newLedgerDoc.id}`
                });
            }

            // ج. إنشاء الطلبات
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

        return {
            success: true,
            orderIds: successfulOrders,
            cashbackReserved: cashbackToReserve
        };

    } catch (error) {
        console.error("❌ Transaction Failed:", error.message);
        throw error;
    }
});

// ملاحظة: باقي الدوال (Watcher, Finance) يمكن إضافتها لاحقاً بنفس الطريقة الموحدة.

