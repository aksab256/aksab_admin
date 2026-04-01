const taskLogic = require("./task_notifier");
const orderLogic = require("./order_engine");

module.exports = {
    // 1. إشعار المندوب بالتكليف المباشر (من المشرف)
    onNewDeliveryTask: taskLogic.notifyRepOnNewTask,

    // 2. تشغيل الرادار فور إنشاء أوردر جديد (البحث الجغرافي)
    handleNewOrderRadar: orderLogic.onOrderCreated,

    // 3. المحرك المالي والمزامنة عند تحديث الأوردر (القبول والتسليم)
    processOrderOperations: orderLogic.monitorOrderFlow
};

