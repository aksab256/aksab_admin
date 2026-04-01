const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

/**
 * دالة المقاصة الشهرية للموردين (نسخة المحاسب الصافية)
 * التكرار: أول يوم من كل شهر الساعة 12 صباحاً
 */
exports.runMonthlySellerSettlement = onSchedule("0 0 1 * *", async (event) => {
    const db = admin.firestore();
    console.log("🚀 بدء عملية مراجعة حسابات الموردين والترحيل الشهري...");

    try {
        // 1. جلب الموردين النشطين فقط
        const sellersSnapshot = await db.collection('sellers').where('status', '==', 'active').get();

        if (sellersSnapshot.empty) {
            console.log("ℹ️ لا يوجد موردين نشطين للمعالجة حالياً.");
            return;
        }

        let count = 0;
        let totalCommissionsSum = 0;
        let totalMonthlyFeesSum = 0;
        let totalCashbackNetSum = 0;
        let globalTotalAmount = 0;

        // مصفوفة لتخزين وعود العمليات (Promises) لضمان السرعة
        for (const doc of sellersSnapshot.docs) {
            const sellerData = doc.data();
            const sellerId = doc.id;

            // استخراج القيم المالية مع التأكد من أنها أرقام
            const realizedCommission = parseFloat(sellerData.realizedCommission || 0);
            const cashbackDebt = parseFloat(sellerData.cashbackAccruedDebt || 0);
            const platformCredit = parseFloat(sellerData.cashbackPlatformCredit || 0);
            const monthlyFee = parseFloat(sellerData.monthlyFee || 0);

            // الحسبة الأساسية: (العمولات + ديون الكاش باك + الرسوم) - رصيد الكاش باك لدى المنصة
            const totalAmount = (realizedCommission + cashbackDebt + monthlyFee) - platformCredit;

            // نرحل فقط لو المبلغ مستحق (أكبر من صفر)
            if (totalAmount > 0) {
                const batch = db.batch();
                const invoiceRef = db.collection('pendingInvoices').doc();
                
                // [أ] إنشاء الفاتورة في المجموعات (نفس الحقول بالظبط)
                batch.set(invoiceRef, {
                    sellerId: sellerId,
                    merchantName: sellerData.merchantName || sellerData.fullname || "مورد رابية أحلى",
                    amount: totalAmount,
                    status: 'pending_payment', 
                    phone: sellerData.phone || "",
                    email: sellerData.email || "",
                    type: 'MONTHLY_SETTLEMENT', // تمييز نوع الفاتورة
                    calculations: {
                        commission: realizedCommission,
                        cashbackNet: cashbackDebt - platformCredit,
                        fixedFee: monthlyFee
                    },
                    createdAt: admin.firestore.FieldValue.serverTimestamp()
                });

                // [ب] تصفير حساب المورد وتحديث الحالة (تأمين العهدة)
                const sellerRef = db.collection('sellers').doc(sellerId);
                batch.update(sellerRef, {
                    realizedCommission: 0,
                    cashbackAccruedDebt: 0,
                    cashbackPlatformCredit: 0,
                    hasPendingInvoice: true,
                    lastSettlementDate: admin.firestore.FieldValue.serverTimestamp(),
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                });

                await batch.commit();
                
                // تجميع الأرقام للتقرير المركزي (Ledger)
                totalCommissionsSum += realizedCommission;
                totalMonthlyFeesSum += monthlyFee;
                totalCashbackNetSum += (cashbackDebt - platformCredit);
                globalTotalAmount += totalAmount;
                
                count++;
                console.log(`✅ تم ترحيل حساب المورد [${sellerId}] بمبلغ: ${totalAmount}`);
            }
        }

        // 2. تسجيل "إيراد الموردين" في الـ Ledger العام (platform_ledger)
        if (count > 0) {
            const currentMonth = new Date().toLocaleString('ar-EG', { month: 'long', year: 'numeric' });
            
            await db.collection('platform_ledger').add({
                source: "sellers",
                entryType: "revenue",
                period: currentMonth,
                details: {
                    totalCommissions: totalCommissionsSum,
                    totalFixedFees: totalMonthlyFeesSum,
                    netCashbackAdjustment: totalCashbackNetSum
                },
                totalAmount: globalTotalAmount,
                invoiceCount: count,
                createdAt: admin.firestore.FieldValue.serverTimestamp()
            });
            console.log(`📊 تم تسجيل مستند الإيراد العام (Sellers Ledger) لشهر: ${currentMonth}`);
        }

        console.log(`🏁 انتهت المهمة: تم إصدار ${count} فاتورة بنجاح.`);

    } catch (error) {
        console.error("❌ خطأ حرج في عملية المحاسبة الشهرية:", error);
    }
});

