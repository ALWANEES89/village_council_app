const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const { FieldValue } = require("firebase-admin/firestore");
const { renderStructuredNotificationBody } = require("./omr_currency");

admin.initializeApp();

// سجل الأحداث الخادمي: مشغّلات تُنشئ audit_logs تلقائيًا عند العمليات الحسّاسة.
// تُصدَّر أدناه بعد تهيئة admin حتى تستخدم نفس التطبيق.
const auditTriggers = require("./audit");
for (const [name, handler] of Object.entries(auditTriggers)) {
  exports[name] = handler;
}

const financialFunctions = require("./financial");
for (const [name, handler] of Object.entries(financialFunctions)) {
  if (name !== "_test") exports[name] = handler;
}

/**
 * Cloud Function: تُطلَق عند إنشاء أي إشعار داخلي للعضو
 * users/{userId}/notifications/{notificationId}
 * تقرأ توكنات الجهاز للمستلم وترسل إشعار Push، وتنظّف التوكنات غير الصالحة.
 */
exports.onNotificationCreated = onDocumentCreated(
  {
    document: "users/{userId}/notifications/{notificationId}",
    region: "us-central1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const notification = snapshot.data() || {};
    const { userId } = event.params;
    const db = admin.firestore();

    // اجمع كل توكنات المستلم (users.fcmTokens + users.fcmToken + members.fcmToken)
    const tokens = new Set();
    const userSnap = await db.collection("users").doc(userId).get();
    if (userSnap.exists) {
      const list = userSnap.get("fcmTokens");
      if (Array.isArray(list)) list.forEach((t) => t && tokens.add(t));
      const single = userSnap.get("fcmToken");
      if (single) tokens.add(single);
    }
    const memberSnap = await db.collection("members").doc(userId).get();
    if (memberSnap.exists) {
      const legacy = memberSnap.get("fcmToken");
      if (legacy) tokens.add(legacy);
    }
    if (tokens.size === 0) {
      console.log(`No FCM tokens for user ${userId} — skipping push`);
      return;
    }

    // تفضيلات المستخدم للصوت/الاهتزاز → اختيار القناة المطابقة (يجب أن تطابق
    // kNotificationChannels في التطبيق) حتى يحترم Push الخلفي اختيار المستخدم.
    const ns = userSnap.exists ? userSnap.get("notificationSettings") || {} : {};
    const soundOn = ns.soundEnabled !== false;
    const vibeOn = ns.vibrationEnabled !== false;
    const channelId =
      soundOn && vibeOn ? "vc_high_sv"
        : soundOn && !vibeOn ? "vc_high_s"
        : !soundOn && vibeOn ? "vc_silent_v"
        : "vc_silent";

    const tokenList = [...tokens];
    const message = {
      tokens: tokenList,
      notification: {
        title: notification.title || "إشعار جديد",
        body: renderStructuredNotificationBody(notification),
      },
      data: {
        type: String(notification.type || ""),
        relatedEntityType: String(notification.relatedEntityType || ""),
        relatedEntityId: String(notification.relatedEntityId || ""),
        organizationId: String(notification.organizationId || ""),
        amountBaisa: Number.isSafeInteger(notification.amountBaisa)
          ? String(notification.amountBaisa)
          : "",
        currencyCode: String(notification.currencyCode || ""),
        bodyTemplate: String(notification.bodyTemplate || ""),
      },
      android: {
        priority: "high",
        notification: {
          channelId,
          priority: "high",
          ...(soundOn ? { sound: "default" } : {}),
        },
      },
      apns: {
        payload: { aps: { ...(soundOn ? { sound: "default" } : {}), badge: 1 } },
      },
    };

    try {
      const response = await admin.messaging().sendEachForMulticast(message);
      console.log(
        `Push sent to ${userId}: success=${response.successCount} ` +
          `failure=${response.failureCount}`
      );

      // نظّف التوكنات غير الصالحة من users.fcmTokens
      const invalid = [];
      response.responses.forEach((result, index) => {
        if (!result.success) {
          const code = result.error && result.error.code;
          if (
            code === "messaging/registration-token-not-registered" ||
            code === "messaging/invalid-registration-token"
          ) {
            invalid.push(tokenList[index]);
          }
        }
      });
      if (invalid.length > 0) {
        await db
          .collection("users")
          .doc(userId)
          .update({
            fcmTokens: FieldValue.arrayRemove(...invalid),
          })
          .catch(() => {});
      }
    } catch (err) {
      console.error("Failed to send push notification:", err.message);
    }
  }
);

/**
 * Cloud Function: تراقب مجموعة notifications_queue
 * عند إضافة سجل جديد → ترسل FCM للعضو → تحذف السجل
 *
 * TODO(legacy): هذه الدالة قديمة ولم تعد المسارات الحالية تكتب في
 * notifications_queue (الاعتماد الآن على onNotificationCreated). تُركت مؤقتاً
 * لتفادي أي كسر، ويمكن حذفها لاحقاً بعد التأكد من عدم وجود كاتبين للطابور.
 */
exports.sendPushNotification = onDocumentCreated(
  {
    document: "notifications_queue/{docId}",
    region: "us-central1",
  },
  async (event) => {
    const data = event.data.data();
    const { token, title, body } = data;

    if (!token) {
      console.warn("No FCM token — skipping notification");
      await event.data.ref.delete();
      return;
    }

    const message = {
      token,
      notification: { title, body },
      android: {
        notification: {
          channelId: "village_council_high",
          priority: "high",
          sound: "default",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    try {
      const response = await admin.messaging().send(message);
      console.log("Notification sent:", response);
    } catch (err) {
      console.error("Failed to send notification:", err.message);
    } finally {
      // احذف السجل دائماً بعد المعالجة
      await event.data.ref.delete();
    }
  }
);
