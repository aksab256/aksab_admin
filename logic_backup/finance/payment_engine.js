const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const axios = require('axios');

// نستخدم الدالة المتاحة فعلياً في ملف الـ services
//const { sendOrderNotifications } = require("../../services/notifications_service");

const SECRET_KEY = "egy_sk_test_c4811a307a9c6fcf3b98d267de789f913e208a19b90cd84ea82a739984643487";
const PUBLIC_KEY = "egy_pk_test_5jCU1CY5YHrZ2oymVSAJMgWA0zgasnpz";
const INTEGRATION_ID = 5476155;

// مراقبة طلبات إنشاء رابط الدفع
exports.onInvoicePaymentRequest = onDocumentUpdated("pendingInvoices/{docId}", async (event) => {
    const data = event.data.after.data();
    const docId = event.params.docId;

    // 1. إرسال إشعار بصدور فاتورة جديدة (للتجار - النوع العادي)
    if (data.status === 'pending_payment' && data.type === 'NORMAL_INVOICE' && !data.notified) {
        try {
            // صياغة بيانات تحاكي كائن الطلب ليفهمها ملف الإشعارات
            const notificationPayload = {
                id: docId,
                sellerId: data.sellerId,
                totalAmount: data.amount
            };
            
//            await sendOrderNotifications(notificationPayload, 'new_order');
            
            // تحديث الفاتورة لضمان عدم تكرار الإشعار
            await event.data.after.ref.update({ notified: true });
            console.log(`✅ تم إرسال إشعار فاتورة جديدة: ${docId}`);
        } catch (error) {
            console.error("❌ خطأ في إرسال إشعار الفاتورة:", error);
        }
    }

    // 2. توليد رابط Paymob عند طلب الدفع
    if (data.status === 'pay_now' && !data.paymentUrl) {
        const amountValue = parseFloat(data.amount);
        if (isNaN(amountValue) || amountValue < 1) {
            console.warn(`⚠️ قيمة غير صالحة للدفع: ${docId}`);
            return null;
        }

        try {
            const amountInCents = Math.round(amountValue * 100);

            // تحديد بيانات العميل بناءً على نوع العملية
            let firstName = "Client";
            if (data.type === 'OPERATIONAL_FEES') firstName = "Driver";
            else if (data.type === 'SUBSCRIPTION_RENEW') firstName = "Store";

            const res = await axios.post('https://accept.paymob.com/v1/intention/', {
                amount: amountInCents,
                currency: "EGP",
                payment_methods: [INTEGRATION_ID],
                billing_data: {
                    first_name: firstName,
                    last_name: data.merchantName?.split(' ')[0] || "Aksab",
                    email: data.email || "billing@aksab.com",
                    phone_number: data.phone || "01021070462",
                    country: "EG",
                    city: "Alexandria", // بما أن أغلب العمل في الإسكندرية
                    street: "NA"
                }
            }, { 
                headers: { 'Authorization': `Token ${SECRET_KEY}` } 
            });

            const paymobOrderId = res.data.intention_order_id || res.data.id;
            const finalLink = `https://accept.paymob.com/unifiedcheckout/?publicKey=${PUBLIC_KEY}&client_secret=${res.data.client_secret}`;

            await event.data.after.ref.update({
                paymentUrl: finalLink,
                paymobOrderId: paymobOrderId,
                status: 'ready_for_payment'
            });
            
            console.log(`✅ تم تجهيز رابط الدفع لـ ${data.type}: ${docId}`);
        } catch (err) {
            console.error("❌ فشل ربط Paymob:", err.response?.data || err.message);
        }
    }
    return null;
});

