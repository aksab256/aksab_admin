/**
 * ⚠️ ملاحظة للهندسة: مفيش أي Require لمكتبات تقيلة فوق خالص!
 * الـ CLI هيقرأ الملف ده في أقل من ثانية بإذن الله.
 */
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");

// إعدادات الرام والمنطقة
setGlobalOptions({ region: "us-central1", memory: "256MiB" });

// --- 1. المالية ---
exports.finance_grantWelcomePoints = onDocumentCreated("consumers/{uid}", (event) => {
    return require("./logic/finance/loyalty_points").onNewConsumer(event);
});

exports.finance_handleCashback = onDocumentUpdated("orders/{orderId}", (event) => {
    return require("./logic/finance/cashback_handler").handleCashbackSettlement(event);
});

exports.finance_runMonthlySettlement = onSchedule({ schedule: "0 0 1 * *", timeZone: "Africa/Cairo" },
async (event) => {
    return require("./logic/finance/monthly_settlement").runMonthlySellerSettlement(event);
});

// --- 2. المراقب ---
exports.watcher_watchOrders = onDocumentUpdated("orders/{orderId}", (event) => {
    return require("./logic/watcher").watchOrders(event);
});

exports.watcher_watchConsumerOrders = onDocumentCreated("orders/{orderId}", (event) => {
    return require("./logic/watcher").watchConsumerOrders(event);
});

// --- 3. المخازن ---
exports.inventory_handleInventory = onDocumentUpdated("products/{productId}", (event) => {
    return require("./logic/inventory").handleInventoryAndRepCode(event);
});

// --- 4. التوصيل ---
exports.delivery_onNewTask = onDocumentCreated("delivery_tasks/{taskId}", (event) => {
    return require("./logic/delivery").onNewDeliveryTask(event);
});

// --- 5. التنبيهات ---
exports.notifications_sendPromo = onDocumentCreated("promotions/{promoId}", (event) => {
    return require("./logic/notifications_logic").sendPromoNotification(event);
});

// --- 6. الطلبات (الجوهرة الجديدة - بدون AWS) ---
exports.orders_createSecureOrder = onCall(async (request) => {
    // 🎯 التعديل هنا: تم تغيير المسار لـ create_order ليتطابق مع اسم الملف الفعلي
    const logic = require("./logic/orders/create_order");
    
    // تمرير البيانات والـ UID الخاص بالمستخدم المصرح له
    return await logic.createSecureOrder(request.data, request.auth ? request.auth.uid : null);
});

