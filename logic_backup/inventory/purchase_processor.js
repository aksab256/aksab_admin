const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

// الـ ID الثابت للأدمن (Aksab) زي ما هو في كودك
const SUPER_ADMIN_FIXED_ID = "4KflsGbA1vRWeuZOU18yo35T3nw2";

exports.processNewPurchase = onDocumentCreated("purchases/{purchaseId}", async (event) => {
    const purchaseData = event.data.data();
    const purchaseId = event.params.purchaseId;
    const db = admin.firestore();

    // منع المعالجة المكررة
    if (purchaseData.isProcessed) return null;

    const products = purchaseData.products || [];
    if (products.length === 0) {
        await event.data.ref.update({ isProcessed: true, processingStatus: 'SKIPPED_EMPTY' });
        return null;
    }

    try {
        for (const item of products) {
            const inventoryRef = db.doc(`vendor_inventories/${SUPER_ADMIN_FIXED_ID}/items/${item.productId}`);
            const offerQuery = db.collection('productOffers')
                                .where('productId', '==', item.productId)
                                .where('sellerId', '==', SUPER_ADMIN_FIXED_ID)
                                .limit(1);

            await db.runTransaction(async (transaction) => {
                // 1. القراءات
                const invDoc = await transaction.get(inventoryRef);
                const offerSnap = await transaction.get(offerQuery);
                
                // 2. حسبة المخزن والتكلفة
                const qty = parseFloat(item.quantity) || 0;
                const cost = parseFloat(item.unitPrice) || 0;
                const sellPrice = parseFloat(item.sellingPrice) || 0;

                let oldBal = invDoc.exists ? (invDoc.data().balance || 0) : 0;
                let oldAvg = invDoc.exists ? (invDoc.data().averageCost || 0) : 0;
                
                const newBal = oldBal + qty;
                const newAvg = newBal > 0 ? ((oldAvg * oldBal) + (qty * cost)) / newBal : 0;

                // 3. تحديث مصفوفة الوحدات (Units Array)
                let offerRef, units = [];
                if (!offerSnap.empty) {
                    offerRef = offerSnap.docs[0].ref;
                    units = offerSnap.docs[0].data().units || [];
                } else {
                    offerRef = db.collection('productOffers').doc(`${item.productId}_${SUPER_ADMIN_FIXED_ID}`);
                }

                const unitName = item.unit || 'وحدة';
                const uIdx = units.findIndex(u => u.unitName === unitName);
                if (uIdx !== -1) {
                    units[uIdx].availableStock = (units[uIdx].availableStock || 0) + qty;
                    units[uIdx].price = sellPrice;
                } else {
                    units.push({ unitName, price: sellPrice, availableStock: qty });
                }

                // 4. الكتابة
                transaction.set(inventoryRef, {
                    balance: newBal,
                    averageCost: parseFloat(newAvg.toFixed(4)),
                    lastPurchasePrice: cost,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                }, { merge: true });

                transaction.set(offerRef, {
                    productId: item.productId,
                    productName: item.productName,
                    sellerId: SUPER_ADMIN_FIXED_ID,
                    status: 'active',
                    units: units,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                }, { merge: true });
            });
        }

        // إغلاق الفاتورة
        await event.data.ref.update({ 
            isProcessed: true, 
            processedAt: admin.firestore.FieldValue.serverTimestamp() 
        });

    } catch (error) {
        console.error(`❌ Purchase Processor Error:`, error);
    }
    return null;
});

