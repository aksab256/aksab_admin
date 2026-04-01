const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

/**
 * 🎁 نظام نقاط الترحيب - رابية أحلى
 * الالتزام التام بمجموعة consumers وحقل loyaltyPoints
 */
exports.grantWelcomePoints = onDocumentCreated("consumers/{userId}", async (event) => {
    const userId = event.params.userId;
    const userRef = event.data.ref;
    const db = admin.firestore();

    try {
        await db.runTransaction(async (transaction) => {
            // 1. جلب إعدادات النقاط (نفس المسار الأصلي)
            const settingsDoc = await transaction.get(db.doc('appSettings/points'));
            if (!settingsDoc.exists) return;

            const earningRules = settingsDoc.data().earningRules || [];
            const registrationRule = earningRules.find(r => r.type === 'on_new_customer_registration');

            // التحقق من حالة القاعدة
            if (!registrationRule || !registrationRule.isActive || registrationRule.value <= 0) {
                transaction.update(userRef, { welcomePointsProcessed: true });
                return;
            }

            const pointsToAdd = Number(registrationRule.value);
            const userDoc = await transaction.get(userRef);
            
            // الحماية من التكرار بنفس مسمى الحقل الأصلي
            if (userDoc.data().welcomePointsProcessed === true) return;

            // 2. تحديث النقاط (loyaltyPoints) والوكوم (welcomePointsProcessed)
            const currentPoints = userDoc.data().loyaltyPoints || 0;
            
            transaction.update(userRef, {
                loyaltyPoints: currentPoints + pointsToAdd,
                welcomePointsProcessed: true
            });

            console.log(`✅ [Loyalty] Success for Consumer: ${userId}. Added: ${pointsToAdd}`);
        });
    } catch (error) {
        console.error("❌ [Loyalty] Error:", error.message);
    }
});


