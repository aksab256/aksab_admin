const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

/**
 * الجزء الأول: تسوية الكاش باك عند تغيير حالة الطلب (Original Logic)
 */
exports.handleCashbackSettlement = onDocumentUpdated("orders/{orderId}", async (event) => {
    const newOrder = event.data.after.data();
    const oldOrder = event.data.before.data();
    const orderId = event.params.orderId;

    // 1. شروط الأمان: الحالة اتغيرت؟
    if (!newOrder || !oldOrder || newOrder.status === oldOrder.status) return null;

    const isCashbackUsed = newOrder.isCashbackUsed === true;
    const amount = parseFloat(newOrder.cashbackApplied || newOrder.cashbackAmount || 0);
    const buyerId = newOrder.buyer?.id || newOrder.buyerId;

    if (!isCashbackUsed || amount <= 0 || !buyerId) return null;

    const db = admin.firestore();
    const userRef = db.collection('users').doc(buyerId);

    // --- [أ] حالة الإلغاء: إرجاع الكاش باك للمحفظة ---
    if (['cancelled', 'rejected', 'failed'].includes(newOrder.status) && !newOrder.cashbackRefunded) {
        try {
            await db.runTransaction(async (transaction) => {
                const userDoc = await transaction.get(userRef);
                if (!userDoc.exists) return;

                const currentBal = userDoc.data().cashback || 0;
                const currentRes = userDoc.data().cashbackReserved || 0;

                // إعادة الرصيد وفك الحجز
                transaction.update(userRef, {
                    cashback: currentBal + amount,
                    cashbackReserved: Math.max(0, currentRes - amount),
                    lastUpdateType: 'cashback_refund'
                });

                transaction.update(event.data.after.ref, {
                    cashbackRefunded: true,
                    cashbackStatus: 'refunded'
                });

                // تسجيل الحركة في سجل الحسابات
                const ledgerRef = db.collection('finance_ledger').doc();
                transaction.set(ledgerRef, {
                    type: 'CASHBACK_REFUND',
                    userId: buyerId,
                    orderId: orderId,
                    amount: amount,
                    createdAt: admin.firestore.FieldValue.serverTimestamp()
                });
            });
            console.log(`💰 [Finance] Refund Success: ${orderId}`);
        } catch (e) {
            console.error("❌ Refund Error:", e);
        }
    }
    // --- [ب] حالة التسليم: تأكيد الخصم النهائي (Settlement) ---
    else if (['delivered'].includes(newOrder.status) && !newOrder.cashbackConfirmedSettlement) {
        try {
            await db.runTransaction(async (transaction) => {
                const userDoc = await transaction.get(userRef);
                if (!userDoc.exists) return;
                
                const currentRes = userDoc.data().cashbackReserved || 0;

                // تصفية المحجوز نهائياً من المحفظة
                transaction.update(userRef, {
                    cashbackReserved: Math.max(0, currentRes - amount)
                });

                transaction.update(event.data.after.ref, {
                    cashbackConfirmedSettlement: true,
                    cashbackStatus: 'confirmed'
                });

                // تحديث رصيد المنصة لدى المورد (Platform Credit)
                if (newOrder.sellerId) {
                    const sellerRef = db.collection('sellers').doc(newOrder.sellerId);
                    transaction.update(sellerRef, {
                        cashbackPlatformCredit: admin.firestore.FieldValue.increment(amount)
                    });
                }
            });
            console.log(`🔒 [Finance] Confirmation Success: ${orderId}`);
        } catch (e) {
            console.error("❌ Settlement Error:", e);
        }
    }
    return null;
});

/**
 * الجزء الثاني: محرك إشعارات الكاش باك الذكي (Migrated from EC2)
 * يتم تشغيله عند إضافة قاعدة كاش باك جديدة من لوحة التحكم
 */
exports.onNewCashbackRule = onDocumentCreated("cashbackRules/{ruleId}", async (event) => {
    const rule = event.data.data();
    if (!rule || rule.status !== 'active') return null;

    const db = admin.firestore();
    const description = rule.description || "عرض كاش باك جديد ينتظرك في حسابك!";
    const sellerName = rule.sellerName || "أحد موردينا";

    // استدعاء ملف الإشعارات داخلياً (Lazy Loading) لتجنب الـ Deployment Timeout
    const { sendPushNotification, getUserEndpointData } = require("../notifications_logic");

    try {
        // --- الحالة الأولى: قاعدة خاصة بمورد (Seller) معين ---
        if (rule.appliesTo === 'seller' && rule.sellerId) {
            console.log(`🎯 استهداف التجار الذين تعاملوا مع المورد: ${sellerName}`);

            const pastOrders = await db.collection('orders')
                .where('sellerId', '==', rule.sellerId)
                .where('status', '==', 'delivered')
                .get();

            const uniqueUserIds = [...new Set(
                pastOrders.docs
                    .map(doc => doc.data().buyer ? doc.data().buyer.id : (doc.data().buyerId || null))
                    .filter(id => id !== null)
            )];

            if (uniqueUserIds.length > 0) {
                for (const uid of uniqueUserIds) {
                    const userDoc = await db.collection('users').doc(uid).get();
                    const customerName = userDoc.exists ? (userDoc.data().fullname || "عزيزنا التاجر") : "عزيزنا التاجر";
                    
                    const endpointData = await getUserEndpointData(uid);
                    if (endpointData && endpointData.endpointArn) {
                        await sendPushNotification(
                            endpointData.endpointArn,
                            `يا سيد ${customerName}، فرصة كاش باك من ${sellerName} 💰`,
                            description,
                            'cashback_promo_seller',
                            null,
                            uid
                        );
                    }
                }
                console.log(`✅ تم إرسال ${uniqueUserIds.length} إشعار كاش باك مخصص.`);
            }
        }
        // --- الحالة الثانية: قاعدة عامة لجميع تجار التجزئة (Users) ---
        else if (rule.appliesTo === 'all') {
            console.log(`🌍 إرسال إشعار عام لجميع تجار التجزئة...`);

            const allUsers = await db.collection('users').get();
            for (const doc of allUsers.docs) {
                const uid = doc.id;
                const customerName = doc.data().fullname || "عزيزنا التاجر";
                
                const endpointData = await getUserEndpointData(uid);
                if (endpointData && endpointData.endpointArn) {
                    await sendPushNotification(
                        endpointData.endpointArn,
                        `يا سيد ${customerName}، كاش باك جديد من المنصة 🎁`,
                        description,
                        'cashback_promo_general',
                        null,
                        uid
                    );
                }
            }
            console.log(`✅ تم إرسال الإشعار العام لـ ${allUsers.size} مستخدم.`);
        }
    } catch (error) {
        console.error(`❌ [Marketing Error]: حدث خطأ في معالجة الكاش باك: ${error.message}`);
    }
    return null;
});

