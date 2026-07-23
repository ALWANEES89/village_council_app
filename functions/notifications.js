const admin = require("firebase-admin");
const { FieldValue } = require("firebase-admin/firestore");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { renderStructuredNotificationBody } = require("./omr_currency");

const REGION = "us-central1";

function isTrustedNotification(notification, params) {
  return notification && notification.deliverySource === "server" &&
    notification.userId === params.userId &&
    notification.notificationId === params.notificationId &&
    notification.status === "unread" &&
    typeof notification.organizationId === "string" && notification.organizationId.length > 0 &&
    typeof notification.title === "string" && notification.title.length > 0 &&
    typeof notification.body === "string" &&
    typeof notification.type === "string" && notification.type.length > 0 &&
    typeof notification.relatedEntityType === "string" &&
    typeof notification.relatedEntityId === "string";
}

async function onNotificationCreatedHandler(event, options = {}) {
  const snapshot = event.data;
  if (!snapshot || !snapshot.exists) return { status: "missing" };
  const notification = snapshot.data() || {};
  const { userId, notificationId } = event.params;
  if (!isTrustedNotification(notification, { userId, notificationId })) {
    (options.log || console).warn("Rejected untrusted notification document", {
      notificationId,
      reason: "invalid-server-provenance-or-routing",
    });
    return { status: "rejected" };
  }
  const database = options.database || admin.firestore();
  const messaging = options.messaging || admin.messaging();
  const tokens = new Set();
  const [userSnap, memberSnap] = await Promise.all([
    database.collection("users").doc(userId).get(),
    database.collection("members").doc(userId).get(),
  ]);
  if (userSnap.exists) {
    const list = userSnap.get("fcmTokens");
    if (Array.isArray(list)) list.forEach((token) => token && tokens.add(token));
    const single = userSnap.get("fcmToken");
    if (single) tokens.add(single);
  }
  if (memberSnap.exists) {
    const legacy = memberSnap.get("fcmToken");
    if (legacy) tokens.add(legacy);
  }
  if (tokens.size === 0) return { status: "no-tokens" };

  const settings = userSnap.exists ? userSnap.get("notificationSettings") || {} : {};
  const soundOn = settings.soundEnabled !== false;
  const vibeOn = settings.vibrationEnabled !== false;
  const channelId = soundOn && vibeOn ? "vc_high_sv"
    : soundOn ? "vc_high_s" : vibeOn ? "vc_silent_v" : "vc_silent";
  const tokenList = [...tokens];
  const response = await messaging.sendEachForMulticast({
    tokens: tokenList,
    notification: {
      title: notification.title,
      body: renderStructuredNotificationBody(notification),
    },
    data: {
      type: notification.type,
      relatedEntityType: notification.relatedEntityType,
      relatedEntityId: notification.relatedEntityId,
      organizationId: notification.organizationId,
      amountBaisa: Number.isSafeInteger(notification.amountBaisa)
        ? String(notification.amountBaisa) : "",
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
    apns: { payload: { aps: { ...(soundOn ? { sound: "default" } : {}), badge: 1 } } },
  });
  const invalid = [];
  response.responses.forEach((result, index) => {
    const code = !result.success && result.error && result.error.code;
    if (code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token") invalid.push(tokenList[index]);
  });
  if (invalid.length > 0) {
    await database.collection("users").doc(userId).update({
      fcmTokens: FieldValue.arrayRemove(...invalid),
    }).catch(() => {});
  }
  (options.log || console).info("Trusted push delivery completed", {
    notificationId,
    successCount: response.successCount,
    failureCount: response.failureCount,
  });
  return {
    status: "sent",
    successCount: response.successCount,
    failureCount: response.failureCount,
  };
}

async function legacyQueueHandler(event, options = {}) {
  const snapshot = event.data;
  if (!snapshot || !snapshot.exists) return { status: "missing" };
  const data = snapshot.data() || {};
  // Firestore Rules deny all client writes. The marker also prevents an old
  // malformed server writer from turning arbitrary queue content into FCM.
  if (data.deliverySource !== "server" || typeof data.token !== "string" ||
      typeof data.title !== "string" || typeof data.body !== "string") {
    return { status: "rejected" };
  }
  const messaging = options.messaging || admin.messaging();
  try {
    await messaging.send({
      token: data.token,
      notification: { title: data.title, body: data.body },
      android: { notification: { channelId: "vc_high_sv", priority: "high", sound: "default" } },
      apns: { payload: { aps: { sound: "default", badge: 1 } } },
    });
    return { status: "sent" };
  } finally {
    await snapshot.ref.delete();
  }
}

exports.onNotificationCreated = onDocumentCreated(
  { document: "users/{userId}/notifications/{notificationId}", region: REGION },
  onNotificationCreatedHandler,
);
exports.sendPushNotification = onDocumentCreated(
  { document: "notifications_queue/{docId}", region: REGION },
  legacyQueueHandler,
);

exports._test = { isTrustedNotification, legacyQueueHandler, onNotificationCreatedHandler };
