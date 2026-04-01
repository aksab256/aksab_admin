const { onRequest } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const crypto = require('crypto');
const HMAC_SECRET = "F7E8BE06B4CB216D1FF12245B1BA0C42";

exports.paymobWebhook = onRequest(async (req, res) => {
    const transactionData = req.body.obj || req.body;
    const hmacReceived = req.query.hmac;
    const db = admin.firestore();

    // 1. مصفوفة التحقق من الـ HMAC (نفس ترتيب بايموب بالضبط)
    const keys = ["amount_cents", "created_at", "currency", "error_occured", "has_parent_transaction", "id", "integration_id", "is_3d_secure", "is_auth", "is_capture", "is_refunded", "is_standalone_payment", "is_voided", "order.id", "owner", "pending", "source_data.pan", "source_data.sub_type", "source_data.type", "success"];
    
    let concatString = "";
    keys.forEach(key => {
        let val = key.split('.').reduce((o, i) => o ? o[i] : '', transactionData);
        concatString += val;
    });

    const expectedHmac = crypto.createHmac('sha512', HMAC_SECRET).update(concatString).digest('hex');

    if (hmacReceived !== expectedHmac) {
        console.warn("⚠️ HMAC Mismatch!");
        return res.status(400).send('Invalid Signature');
    }

    if (transactionData && (transactionData.success === true || transactionData.success === "true")) {
        const paymobOrderId = transactionData.order ? transactionData.order.id : transactionData.order_id;
        
        const snapshot = await db.collection('pendingInvoices').where('paymobOrderId', '==', paymobOrderId).limit(1).get();
        if (snapshot.empty) return res.status(200).send('Order Not Found');

        const invoiceDoc = snapshot.docs[0];
        const invData = invoiceDoc.data();

        // تحديث الفاتورة لـ مدفوعة
        await invoiceDoc.ref.update({
            status: 'paid',
            paymobTransactionId: transactionData.id,
            paidAt: admin.firestore.FieldValue.serverTimestamp()
        });

        // منطق "تأمين عهدة الطلب" (محفظة المندوب)
        if (invData.type === 'OPERATIONAL_FEES') {
            await db.collection('freeDrivers').doc(invData.driverId).update({
                walletBalance: admin.firestore.FieldValue.increment(parseFloat(invData.amount))
            });
        } 
        // منطق "إدارة العهدة" (تجديد اشتراك المتجر)
        else if (invData.type === 'SUBSCRIPTION_RENEW') {
            const durationDays = invData.durationDays || 30;
            const newExpiryDate = new Date(Date.now() + (durationDays * 24 * 60 * 60 * 1000));
            
            await db.collection('deliverySupermarkets').doc(invData.storeId).update({
                trialExpiryDate: admin.firestore.Timestamp.fromDate(newExpiryDate),
                subscriptionStatus: 'active',
                isVisibleInStore: true
            });
        }
    }

    res.status(200).send('OK');
});

