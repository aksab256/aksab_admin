// logic/finance/index.js
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");

// 1. تسوية الكاش باك (عند تحديث حالة الطلب)
exports.handleCashbackSettlement = onDocumentUpdated("orders/{orderId}", (event) => {
    return require("./cashback_handler").handleCashbackSettlement(event);
});

// 2. إشعارات الكاش باك الجديدة (عند إضافة قاعدة كاش باك)
exports.onNewCashbackRule = onDocumentCreated("cashback_rules/{ruleId}", (event) => {
    return require("./cashback_handler").onNewCashbackRule(event);
});

// 3. نقاط الترحيب (عند تسجيل مستخدم جديد)
exports.grantWelcomePoints = onDocumentCreated("consumers/{uid}", (event) => {
    return require("./loyalty_points").onNewConsumer(event);
});

// 4. المحاسب الشهري (Scheduler - اللي كانت Lambda)
exports.runMonthlySellerSettlement = onSchedule({
    schedule: "0 0 1 * *",
    timeZone: "Africa/Cairo"
}, async (event) => {
    const { runMonthlySellerSettlement } = require("./monthly_settlement");
    return runMonthlySellerSettlement(event);
});

