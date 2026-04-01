const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const { sendOrderNotifications } = require("../../services/notifications_service");
const { processRadarAlert } = require("./radar_engine"); // 👈 استدعاء الرادار

// دالة لمراقبة الأوردرات الجديدة (للتنظيف والرادار)
exports.onOrderCreated = onDocumentCreated("specialRequests/{orderId}", async (event) => {
    const orderData = event.data.data();
    const orderId = event.params.orderId;

    if (orderData.status === 'pending') {
        console.log(`📡 [Radar] New pending order detected: ${orderId}. Starting scan...`);
        await processRadarAlert({ ...orderData, id: orderId });
    }
});

// دالة لمراقبة التحديثات (المالية والمزامنة)
exports.monitorOrderFlow = onDocumentUpdated("specialRequests/{orderId}", async (event) => {
    const orderId = event.params.orderId;
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    const status = afterData.status;
    const db = admin.firestore();

    try {
        // 1️⃣ حجز العهدة (عند قبول المندوب)
        if (status === 'accepted' && !afterData.moneyLocked) {
            await db.runTransaction(async (t) => {
                const driverRef = db.collection('freeDrivers').doc(afterData.driverId);
                const driverDoc = await t.get(driverRef);
                if (!driverDoc.exists) return;

                const { walletBalance, creditLimit } = driverDoc.data();
                const insuranceValue = afterData.requestSource === 'retailer' ? 
                                     (parseFloat(afterData.orderFinalAmount || 0) - parseFloat(afterData.driverNet || 0)) : 0;
                const commissionValue = parseFloat(afterData.commissionAmount || 0);

                if ((walletBalance + creditLimit) >= (insuranceValue + commissionValue)) {
                    let driverUpdates = {
                        insurance_points: admin.firestore.FieldValue.increment(insuranceValue),
                        walletBalance: admin.firestore.FieldValue.increment(-insuranceValue)
                    };
                    
                    let cCredit = 0, cWallet = 0;
                    if (commissionValue > 0) {
                        if (creditLimit >= commissionValue) {
                            driverUpdates.creditLimit = admin.firestore.FieldValue.increment(-commissionValue);
                            cCredit = commissionValue;
                        } else {
                            const rem = commissionValue - creditLimit;
                            driverUpdates.creditLimit = admin.firestore.FieldValue.increment(-creditLimit);
                            driverUpdates.walletBalance = admin.firestore.FieldValue.increment(-rem);
                            cCredit = creditLimit; cWallet = rem;
                        }
                    }

                    t.update(driverRef, driverUpdates);
                    t.update(event.data.after.ref, {
                        insurance_points: insuranceValue,
                        commission_locked_credit: cCredit,
                        commission_locked_wallet: cWallet,
                        moneyLocked: true,
                        lockedAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                }
            });
        }

        // 2️⃣ التسوية عند التسليم (تحديث المندوب والتاجر)
        if (status === 'delivered' && afterData.moneyLocked && !afterData.settlementDone) {
            await db.runTransaction(async (t) => {
                t.update(db.collection('freeDrivers').doc(afterData.driverId), {
                    insurance_points: admin.firestore.FieldValue.increment(-parseFloat(afterData.insurance_points || 0))
                });

                if (afterData.requestSource === 'retailer' && (afterData.ownerId || afterData.userId)) {
                    const mQuery = await db.collection('deliverySupermarkets')
                                    .where('ownerId', '==', (afterData.ownerId || afterData.userId))
                                    .limit(1).get();
                    if (!mQuery.empty) {
                        const netToMerchant = parseFloat(afterData.insurance_points || 0) - parseFloat(afterData.commissionAmount || 0);
                        t.update(mQuery.docs[0].ref, {
                            walletBalance: admin.firestore.FieldValue.increment(netToMerchant),
                            updatedAt: admin.firestore.FieldValue.serverTimestamp()
                        });
                    }
                }
                t.update(event.data.after.ref, { settlementDone: true });
            });
        }

        // 3️⃣ مزامنة الحالات مع تطبيق العميل
        if (afterData.originalOrderId) {
            const syncStatus = { 'accepted': 'processing', 'picked_up': 'shipped', 'delivered': 'delivered', 'cancelled': 'cancelled' }[status];
            if (syncStatus) {
                await db.collection('consumerorders').doc(afterData.originalOrderId).update({
                    status: syncStatus,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                });
            }
        }
    } catch (e) {
        console.error(`❌ Error: ${e.message}`);
    }
});

