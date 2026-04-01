const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const axios = require('axios');

// إعدادات التيليجرام من كودك الأصلي
const TELEGRAM_TOKEN = "8678311363:AAHseL5dsO77gU5IsSBCveOIrNv22zzRfMw";
const ADMIN_CHAT_ID = "-1003756794902";
const OPERATIONS_CHAT_ID = "-1003818388213";

async function sendTelegram(chatId, message) {
    try {
        await axios.post(`https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage`, {
            chat_id: chatId,
            text: message,
            parse_mode: "HTML"
        });
    } catch (e) {
        console.error("❌ Telegram Watcher Error:", e.message);
    }
}

// دالة عامة لبناء الرسالة وإرسالها
const processWatchEvent = async (col, docData, docId) => {
    let msg = "";
    let targetChat = OPERATIONS_CHAT_ID;
    const d = docData;

    if (col === 'orders') {
        msg = `📦 <b>طلب جملة جديد (B2B)</b>\n━━━━━━━━━━━━━━\n🏬 <b>البائع:</b> ${d.sellerId || 'N/A'}\n🛒 <b>المشتري:</b> ${d.buyer?.name || 'تاجر'}\n💰 <b>القيمة:</b> ${d.total || 0} ج.م`;
    } else if (col === 'consumerorders') {
        msg = `🍎 <b>طلب استهلاكي (B2C)</b>\n━━━━━━━━━━━━━━\n🏪 <b>المحل:</b> ${d.supermarketName || 'N/A'}\n👤 <b>العميل:</b> ${d.customerName || 'N/A'}\n💰 <b>المبلغ:</b> ${d.finalAmount || 0} ج.م`;
    } else if (col === 'specialRequests') {
        const vehicle = d.vehicleType === 'motorcycle' ? 'موتوسيكل 🏍️' : d.vehicleType === 'pickup' ? 'طلب نقل 🛻' : d.vehicleType;
        msg = `⚡ <b>طلب رادار جديد</b>\n━━━━━━━━━━━━━━\n📍 <b>من:</b> ${d.pickupAddress || 'N/A'}\n🚚 <b>المركبة:</b> ${vehicle}\n💰 <b>التكلفة:</b> ${d.totalPrice || 0} ج.م`;
    } else if (col === 'waiting_list') {
        msg = `🔍 <b>رادار النواقص</b>\n━━━━━━━━━━━━━━\n🛍️ <b>المنتج:</b> <code>${d.requestedItem}</code>\n👤 <b>العميل:</b> ${d.userName || 'N/A'}`;
    } else if (col.startsWith('pending')) {
        targetChat = ADMIN_CHAT_ID;
        msg = `⏳ <b>طلب انضمام للمراجعة</b>\n━━━━━━━━━━━━━━\n📂 <b>الفئة:</b> ${col}\n👤 <b>الاسم:</b> ${d.merchantName || d.fullname || 'N/A'}\n📞 <b>هاتف:</b> <code>${d.phone || 'N/A'}</code>`;
    }

    if (msg !== "") {
        msg += `\n🆔 <b>ID:</b> <code>${docId}</code>`;
        await sendTelegram(targetChat, msg);
    }
};

// إنشاء التريجرز لكل مجموعة
exports.watchOrders = onDocumentCreated("orders/{id}", (event) => processWatchEvent('orders', event.data.data(), event.params.id));
exports.watchConsumerOrders = onDocumentCreated("consumerorders/{id}", (event) => processWatchEvent('consumerorders', event.data.data(), event.params.id));
exports.watchSpecialRequests = onDocumentCreated("specialRequests/{id}", (event) => processWatchEvent('specialRequests', event.data.data(), event.params.id));
exports.watchWaitingList = onDocumentCreated("waiting_list/{id}", (event) => processWatchEvent('waiting_list', event.data.data(), event.params.id));
exports.watchPendingSellers = onDocumentCreated("pendingSellers/{id}", (event) => processWatchEvent('pendingSellers', event.data.data(), event.params.id));
exports.watchPendingDrivers = onDocumentCreated("pendingFreeDrivers/{id}", (event) => processWatchEvent('pendingFreeDrivers', event.data.data(), event.params.id));
// ... وهكذا لبقية المجموعات

