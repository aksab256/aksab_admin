const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const { sendOrderNotifications } = require("../../services/notifications_service"); // هنجهز السيرفيس ده لاحقاً

const PLATFORM_ID = "4KflsGbA1vRWeuZOU18yo35T3nw2";

exports.handleInventoryAndRepCode = onDocumentCreated("orders/{orderId}", async (event) => {
    const order = event.data.data();
    const orderRef = event.data.ref;
    const sellerId = order.sellerId || order.supermarketId;

    if (!sellerId || order.orderHandled) return null;

    const db = admin.firestore();

    try {
        await db.runTransaction(async (transaction) => {
            // 1. جلب الـ repCode (كود المندوب) وربطه بالطلب
            const buyerId = order.buyer?.id || order.userId;
            let foundRepCode = null;
            if (buyerId) {
                const userDoc = await transaction.get(db.collection('users').doc(buyerId));
                if (userDoc.exists) foundRepCode = userDoc.data().repCode || null;
            }

            const paidItems = (order.items || []).filter(item => !item.isGift);
            
            // 2. معالجة المخزون بناءً على نوع التاجر
            for (const item of paidItems) {
                if (sellerId === PLATFORM_ID) {
                    // --- منطق المنصة (index.js) ---
                    const vRef = db.collection('vendor_inventories').doc(PLATFORM_ID).collection('items').doc(item.productId);
                    const vDoc = await transaction.get(vRef);
                    if (vDoc.exists) {
                        const bal = Number(vDoc.data().balance) || 0;
                        const res = Number(vDoc.data().reserved_stock) || 0;
                        const qty = Number(item.quantity);
                        transaction.update(vRef, { balance: bal - qty, reserved_stock: res + qty });
                    }
                } else {
                    // --- منطق التجار الخارجيين (other.js) ---
                    if (item.offerId) {
                        const offerRef = db.collection('productOffers').doc(item.offerId);
                        const offerDoc = await transaction.get(offerRef);
                        if (offerDoc.exists) {
                            let units = offerDoc.data().units || [];
                            let idx = Number(item.unitIndex);
                            if (units[idx]) {
                                units[idx].availableStock = (Number(units[idx].availableStock) || 0) - Number(item.quantity);
                                transaction.update(offerRef, { units: units });
                            }
                        }
                    }
                }
            }

            // 3. التحديث النهائي للأوردر
            const finalUpdate = {
                orderHandled: true,
                inventoryProcessed: true,
                deliveryHandled: false,
                cancellationHandled: false,
                cashbackProcessedPerOrder: false
            };
            if (foundRepCode) {
                finalUpdate.buyer = { ...(order.buyer || {}), repCode: foundRepCode };
            }
            transaction.update(orderRef, finalUpdate);
        });

        // 4. إرسال الإشعار بعد نجاح الترانزاكشن (باستخدام سيرفيس بلازا الجديد)
        await sendOrderNotifications(order, 'new_order');

    } catch (error) {
        console.error("❌ Inventory Error:", error);
        await orderRef.update({ status: 'failed', errorMessage: error.message });
    }
});

