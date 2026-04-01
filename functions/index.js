/**
 * ⚠️ ملاحظة للهندسة: تم تحسين الـ index ليدعم الجيل الثاني (v2) 
 * وضمان سرعة الاستجابة وربط "الجوهرة" بملف المنطق الصحيح.
 */
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");

// إعدادات الرام والمنطقة (us-central1 هي الافتراضية)
setGlobalOptions({ region: "us-central1", memory: "256MiB" });

// --- 1. المالية ---
exports.finance_grantWelcomePoints = onDocumentCreated("consumers/{uid}", (event) => {
    return require("./logic/finance/loyalty_points").onNewConsumer(event);
});

exports.finance_handleCashback = onDocumentUpdated("orders/{orderId}", (event) => {
    return require("./logic/finance/cashback_handler").handleCashbackSettlement(event);
});

exports.finance_runMonthlySettlement = onSchedule({ schedule: "0 0 1 * *", timeZone: "Africa/Cairo" }, async (event) => {
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

// --- 6. الطلبات (الجوهرة: تأمين عهدة الطلب) ---
// تم الربط مع Flutter 'orders_createSecureOrder'
exports.orders_createSecureOrder = onCall(async (request) => {
    /**
     * 🎯 شرح الربط:
     * - نستخدم require داخلي لضمان عدم تحميل المكتبات إلا عند الاستدعاء (Cold Start optimization).
     * - اسم الدالة في ملف المنطق: createOrderWithPromos
     */
    const logic = require("./logic/orders/create_order");
    
    // تمرير البيانات (request.data) ومعرف المستخدم (request.auth.uid)
    return await logic.createOrderWithPromos(
        request.data, 
        request.auth ? request.auth.uid : null
    );
});

