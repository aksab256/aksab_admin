const { onCall } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

if (admin.apps.length === 0) { admin.initializeApp(); }
const db = admin.firestore();
setGlobalOptions({ region: "us-central1", memory: "256MiB" });

const PROMO_OFFERS_COLLECTION = "giftPromos";

// --- [منطق الهدايا المنسوخ بالنص] ---
const getActivePromotions = async () => {
    const snapshot = await db.collection(PROMO_OFFERS_COLLECTION).where('status', '==', 'active').get();
    return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
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

    // عروض الكمية
    sellerPromotions.filter(p => p.trigger?.type === 'specific_item' && p.trigger?.offerId).forEach(promo => {
        const itemId = promo.trigger.offerId; 
        const buyQty = promo.trigger.triggerQuantityBase; 
        const purchasedQty = itemQuantities[itemId] || 0;
        if (purchasedQty >= buyQty && buyQty > 0) {
            const freeUnits = Math.floor(purchasedQty / buyQty) * (promo.giftQuantityPerBase || 1);
            if (freeUnits > 0 && !finalItems.some(item => (item.offerId || item.itemId) === promo.giftOfferId && item.isGift)) {
                finalItems.push({
                    offerId: promo.giftOfferId, name: promo.giftProductName || 'هدية كمية', productName: promo.giftProductName || 'هدية كمية',
                    quantity: freeUnits, price: 0, priceForReport: promo.giftOfferPriceSnapshot || 1, isGift: true, promoId: promo.id, sellerId: currentSellerId
                });
            }
        }
    });

    // عروض القيمة
    const subTotal = paidItems.reduce((acc, item) => acc + (item.price * item.quantity), 0);
    sellerPromotions.filter(p => p.trigger?.type === 'min_order' && p.trigger?.value).forEach(promo => {
        if (subTotal >= promo.trigger.value && promo.giftOfferId && !finalItems.some(item => (item.offerId || item.itemId) === promo.giftOfferId && item.isGift)) {
            finalItems.push({
                offerId: promo.giftOfferId, name: promo.giftProductName || 'هدية قيمة', productName: promo.giftProductName || 'هدية قيمة',
                quantity: promo.giftQuantityPerBase || 1, price: 0, priceForReport: promo.giftOfferPriceSnapshot || 1, isGift: true, promoId: promo.id, sellerId: currentSellerId
            });
        }
    });
    return finalItems;
};

// --- [الجوهرة - النسخة المطابقة لهيكل البيانات القديم] ---
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
            if ((userData.cashback || 0) < cashbackToReserve) throw new Error("Insufficient balance.");

            if (cashbackToReserve > 0) {
                transaction.update(userRef, {
                    cashback: admin.firestore.FieldValue.increment(-cashbackToReserve),
                    cashbackReserved: admin.firestore.FieldValue.increment(cashbackToReserve)
                });
                const ledgerRef = db.collection('transactionsLedger').doc();
                transaction.set(ledgerRef, {
                    userId, type: 'CASHBACK_RESERVATION', amount: cashbackToReserve,
                    status: 'RESERVED', timestamp: admin.firestore.FieldValue.serverTimestamp()
                });
            }

            for (const orderData of ordersData) {
                const itemsAfterPromo = applyPromotionsLogic(orderData.items || [], orderData.total || 0, activePromotions, orderData.sellerId);
                
                // تحديث مخزون الهدايا
                for (const gift of itemsAfterPromo.filter(i => i.isGift && i.promoId)) {
                    const promoRef = db.collection(PROMO_OFFERS_COLLECTION).doc(gift.promoId);
                    transaction.update(promoRef, {
                        usedQuantity: admin.firestore.FieldValue.increment(gift.quantity),
                        totalGiftValue: admin.firestore.FieldValue.increment((gift.priceForReport || 0) * gift.quantity)
                    });
                }

                const orderRef = db.collection('orders').doc();
                transaction.set(orderRef, {
                    ...orderData,
                    orderId: orderRef.id,
                    orderDate: admin.firestore.FieldValue.serverTimestamp(),
                    items: itemsAfterPromo,
                    buyer: { ...(orderData.buyer || {}), id: userId }, // الـ ID جوه الـ buyer فقط
                    isCashbackReserved: true,
                    status: 'new-order',
                    createdAt: admin.firestore.FieldValue.serverTimestamp()
                });
                successfulOrders.push(orderRef.id);
            }
        });
        return { success: true, orderIds: successfulOrders };
    } catch (e) { throw e; }
});

