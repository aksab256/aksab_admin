const admin = require('firebase-admin');
const { sendPushNotification } = require("../../services/notifications_service");

// دالة حساب المسافة (نفس المعادلة الحسابية بدقة)
function calculateDistance(lat1, lon1, lat2, lon2) {
    const R = 6371; 
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
              Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
}

async function processRadarAlert(orderData) {
    const db = admin.firestore();
    const { pickupLocation, id, driverNet, insurance_points, vehicleType } = orderData;

    if (!pickupLocation?.latitude) return;

    const maxDistance = 15; // النطاق المعتمد في رابية أحلى
    const dbVehicleConfig = vehicleType.includes('Config') ? vehicleType : `${vehicleType}Config`;

    try {
        // جلب المناديب المتاحين فقط
        const driversSnap = await db.collection('freeDrivers')
            .where('currentStatus', 'in', ['online', 'browsing_radar'])
            .where('vehicleConfig', '==', dbVehicleConfig)
            .get();

        for (const doc of driversSnap.docs) {
            const driver = doc.data();
            const driverId = doc.id;
            const dLat = driver.lat || driver.location?.latitude;
            const dLng = driver.lng || driver.location?.longitude;

            if (dLat && dLng) {
                const dist = calculateDistance(pickupLocation.latitude, pickupLocation.longitude, dLat, dLng);

                if (dist <= maxDistance) {
                    const title = "📦 عهدة متاحة بالقرب منك";
                    const body = `اربح ${driverNet} ج.م. (تأمين العهدة: ${insurance_points || 0} نقطة).`;

                    // 1. تحديث السجل الداخلي (النقطة الحمراء)
                    await db.collection('notifications').add({
                        userId: driverId,
                        title, body,
                        eventType: 'radar_new_order',
                        orderId: id,
                        isRead: false,
                        createdAt: admin.firestore.FieldValue.serverTimestamp()
                    });

                    // 2. إرسال Push Notification (لو مش فاتح صفحة الرادار حالياً)
                    if (driver.currentStatus !== 'browsing_radar' && driver.fcmToken) {
                        await sendPushNotification(driver.fcmToken, title, body, {
                            type: 'radar_new_order',
                            orderId: id
                        });
                    }
                }
            }
        }
    } catch (error) {
        console.error("❌ [Radar Error]:", error);
    }
}

module.exports = { processRadarAlert };

