const inventoryLogic = require("./inventory_core");
const giftLogic = require("./gift_reverter");
const hunterLogic = require("./hunter_engine");
const purchaseLogic = require("./purchase_processor"); // 👈 المحاسب الجديد

module.exports = {
    handleInventoryAndRepCode: inventoryLogic.handleInventoryAndRepCode,
    revertGifts: giftLogic.revertGiftsOnCancellation,
    matchProductToWaitingList: hunterLogic.onProductBackInStock,
    processPurchaseInvoice: purchaseLogic.processNewPurchase // 👈 تفعيل معالجة الفواتير
};

