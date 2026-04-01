const watcherLogic = require("./admin_watcher");

module.exports = {
    // مراقبة الطلبات
    watchOrders: watcherLogic.watchOrders,
    watchConsumerOrders: watcherLogic.watchConsumerOrders,
    watchSpecialRequests: watcherLogic.watchSpecialRequests,
    
    // مراقبة النواقص والمنتجات
    watchWaitingList: watcherLogic.watchWaitingList,
    
    // مراقبة طلبات الانضمام (Pending)
    watchPendingSellers: watcherLogic.watchPendingSellers,
    watchPendingDrivers: watcherLogic.watchPendingDrivers
};

