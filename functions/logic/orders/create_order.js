const { onCall } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

// 1. تهيئة Firebase Admin
if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();

// إعدادات السيرفر (الجيل الثاني)
setGlobalOptions({ region: "us-central1", memory: "256MiB" });

const PROMO_OFFERS_COLLECTION = "giftPromos";

// ===================================
// دوال مساعدة (منطق الهدايا المنسوخ بالنص)
// ===================================

const getActivePromotions = async () => {
    try {
        const snapshot = await db.collection(PROMO_OFFERS_COLLECTION)
            .where('status', '==', 'active')
            .get();
        return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    } catch (e) {
        console.error("❌ ERROR PROMO:", e);
        return [];
    }
};

const applyPromotionsLogic = (currentItems, subTotalValue, promotions, currentSellerId) => {
    const paidItems = currentItems.filter(item => !item.isGift && !item.isDeliveryFee);
    const finalItems = [...currentItems]; 

    const itemQuantities = paidItems.reduce((acc, item) => {
        const key = item.offerId || item.itemId; 
        if (key) { acc[key] = (acc[key] || 0) + (item.quantity || 0); }
        return acc;
    }, {});

    const sellerPromotions = promotions.filter(p => p.sellerId === currentSellerId);

    // 1. تطبيق عروض الكمية (N+1 Free)
    const quantityPromos = sellerPromotions.filter(p => p.trigger && p.trigger.type === 'specific_item' && p.trigger.offerId);
    for (const promo of quantityPromos) {
        const itemId = promo.trigger.offerId; 
        const buyQuantity = promo.trigger.triggerQuantityBase; 
        const giftItemId = promo.giftOfferId; 
        const purchasedQty = itemQuantities[itemId] || 0;

        if (purchasedQty >= buyQuantity && buyQuantity > 0) {
            const freeUnitsCount = Math.floor(purchasedQty / buyQuantity) * (promo.giftQuantityPerBase || 1);
            if (freeUnitsCount > 0 && !finalItems.some(item => (item.offerId || item.itemId) === giftItemId && item.isGift)) {
                finalItems.push({
                    offerId: giftItemId, 
                    name: promo.giftProductName || 'هدية كمية',
                    productName: promo.giftProductName || 'هدية كمية',
                    quantity: freeUnitsCount,
                    price: 0,
                    priceForReport: promo.giftOfferPriceSnapshot || 1,
                    isGift: true,
                    promoId: promo.id, 
                    sellerId: currentSellerId
                });
            }
        }
    }

    // 2. تطبيق عروض القيمة الإجمالية (Minimum Total Value)
    const valuePromos = sellerPromotions.filter(p => p.trigger && p.trigger.type === 'min_order' && p.trigger.value);
    const subTotalWithoutDelivery = paidItems.reduce((acc, item) => acc + (item.price * item.quantity), 0);
    for (const promo of valuePromos) {
        const minValue = promo.trigger.value;
        const giftItemId = promo.giftOfferId;
        if (subTotalWithoutDelivery >= minValue && giftItemId && !finalItems.some(item => (item.offerId || item.itemId) === giftItemId && item.isGift)) {
            finalItems.push({
                offerId: giftItemId, 
                name: promo.giftProductName || 'هدية قيمة',
                productName: promo.giftProductName || 'هدية قيمة',
                quantity: promo.giftQuantityPerBase || 1, 
                price: 0,
                priceForReport: promo.giftOfferPriceSnapshot || 1,
                isGift: true,
                promoId: promo.id, 
                sellerId: currentSellerId
            });
        }
    }
    return finalItems;
};

// ===================================
// الجوهرة (orders_createSecureOrder)
// ===================================

exports.orders_createSecureOrder = onCall(async (request) => {
    const { ordersData, userId } = request.data;
    let cashbackToReserve = parseFloat(request.data.cashbackToReserve) || 0;

    try {
        const activePromotions = await getActivePromotions();
        const userRef = db.collection('users').doc(userId);
        let successfulOrders = [];

        await db.runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) throw new Error("User not found.");

            const userData = userDoc.data();
            const currentCashback = userData.cashback || 0;
            const reservedCashback = userData.cashbackReserved || 0;

            if (currentCashback < cashbackToReserve) {
                throw new Error("Insufficient cashback balance.");
            }

            // 1. منطق الكاش باك (تأمين العهدة)
            if (cashbackToReserve > 0) {
                transaction.update(userRef, {
                    cashback: currentCashback - cashbackToReserve,
                    cashbackReserved: reservedCashback + cashbackToReserve
                });

                // 2. التوثيق في سجل العمليات (Ledger) بديل DynamoDB
                const ledgerRef = db.collection('transactionsLedger').doc();
                transaction.set(ledgerRef, {
                    userId: userId,
                    type: 'CASHBACK_RESERVATION',
                    amount: cashbackToReserve,
                    status: 'RESERVED',
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    description: `تأمين عهدة طلب جديد من خلال Cloud Functions`
                });
            }

            // 3. معالجة الطلبات
            for (const orderData of ordersData) {
                const itemsAfterPromotion = applyPromotionsLogic(
                    orderData.items || [],
                    orderData.total || 0,
                    activePromotions,
                    orderData.sellerId
                );

                // خصم مخزون الهدايا وتحديث التقارير المالية (تجميع)
                const giftsToDeduct = itemsAfterPromotion.filter(item => item.isGift && item.promoId);
                for (const giftItem of giftsToDeduct) {
                    const promoRef = db.collection(PROMO_OFFERS_COLLECTION).doc(giftItem.promoId);
                    const promoDoc = await transaction.get(promoRef);
                    if (!promoDoc.exists) throw new Error(`Promotion ${giftItem.promoId} not found.`);

                    const promoData = promoDoc.data();
                    if ((promoData.usedQuantity || 0) + giftItem.quantity > (promoData.maxQuantity || 0)) {
                        throw new Error(`INSUFFICIENT_GIFT_STOCK: ${promoData.promoName || giftItem.promoId}`);
                    }

                    transaction.update(promoRef, {
                        usedQuantity: (promoData.usedQuantity || 0) + giftItem.quantity,
                        totalGiftValue: admin.firestore.FieldValue.increment((giftItem.priceForReport || 0) * giftItem.quantity),
                        totalOrderValue: admin.firestore.FieldValue.increment(orderData.total || 0)
                    });
                }

                // إنشاء وثيقة الطلب (الهيكل المطابق للفرونت)
                const orderRef = db.collection('orders').doc();
                transaction.set(orderRef, {
                    ...orderData,
                    orderId: orderRef.id,
                    orderDate: admin.firestore.FieldValue.serverTimestamp(),
                    items: itemsAfterPromotion,
                    buyer: {
                        ...(orderData.buyer || {}),
                        id: userId // الحفاظ على الـ id داخل ماب الـ buyer
                    },
                    isCashbackReserved: true,
                    status: 'new-order',
                    createdAt: admin.firestore.FieldValue.serverTimestamp()
                });
                successfulOrders.push(orderRef.id);
            }
        });

        return {
            success: true,
            orderIds: successfulOrders,
            cashbackDeducted: cashbackToReserve
        };

    } catch (error) {
        console.error("⛔️ FINAL ERROR:", error.message);
        throw error; // يعود لـ Flutter كـ FirebaseFunctionsException
    }
});

