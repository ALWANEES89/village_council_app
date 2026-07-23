const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const { FieldPath, FieldValue, Timestamp } = require("firebase-admin/firestore");
const {
  canonicalChargeKey,
  isOverdueInMuscat,
  normalizeArabic,
  processPaginated,
  receiptStorageIdentity,
  searchPrefixes,
  subscriptionPeriod,
} = require("./financial_core");
const {
  formatOmaniRialForSystemNotification,
} = require("./omr_currency");
const { membershipForUser } = require("./production_security")._test;

const db = () => admin.firestore();
const timestamp = () => Timestamp.now();
const payableChargePageSize = 50;
const payableChargeTokenVersion = 1;
const financialNotificationOutbox = "financial_notification_outbox";
const approvedReceiptEmulatorProjectId = "demo-financial-prestaging";
const receiptDownloadMaxBytes = 10 * 1024 * 1024;
const receiptContentTypes = new Map([
  ["application/pdf", ".pdf"],
  ["image/jpeg", ".jpg"],
  ["image/png", ".png"],
  ["image/webp", ".webp"],
]);
const financialMemberPageSize = 50;
const financialMemberPageTokenVersion = 1;
const sensitiveCallableOptions = { region: "us-central1", enforceAppCheck: true };

async function requireActiveMembership(organizationId, userId) {
  const membership = await membershipForUser(organizationId, userId);
  if (!membership || membership.get("status") !== "active") {
    throw new HttpsError("permission-denied", "Active council membership is required.");
  }
  return membership;
}

function canReview(data) {
  const permissions = Array.isArray(data.permissionsSnapshot) ? data.permissionsSnapshot : [];
  return ["system_owner", "owner", "council_owner", "chairman", "financialManager", "financialReviewer"].includes(data.roleId) ||
    permissions.some((permission) => ["fullAccess", "payments.manage", "receipts.review", "payments.approve", "payments.reject"].includes(permission));
}

function canManageFinancialConfig(data) {
  const permissions = Array.isArray(data.permissionsSnapshot) ? data.permissionsSnapshot : [];
  return ["system_owner", "owner", "council_owner", "chairman", "financialManager"].includes(data.roleId) ||
    permissions.some((permission) => ["fullAccess", "payments.manage"].includes(permission));
}

async function requireReviewer(organizationId, userId) {
  const platform = await db().collection("platform_admins").doc(userId).get();
  if (platform.exists && platform.get("status") === "active" && platform.get("fullAccess") === true) return;
  const membership = await requireActiveMembership(organizationId, userId);
  if (!canReview(membership.data())) throw new HttpsError("permission-denied", "Financial review permission is required.");
}

async function requireFinanceManager(organizationId, userId) {
  const platform = await db().collection("platform_admins").doc(userId).get();
  if (platform.exists && platform.get("status") === "active" &&
      (platform.get("role") === "system_owner" || platform.get("fullAccess") === true)) return;
  const membership = await requireActiveMembership(organizationId, userId);
  if (!canManageFinancialConfig(membership.data())) {
    throw new HttpsError("permission-denied", "Financial management permission is required.");
  }
}

async function requireBookingManager(organizationId, userId) {
  const platform = await db().collection("platform_admins").doc(userId).get();
  if (platform.exists && platform.get("status") === "active" && platform.get("fullAccess") === true) return;
  const membership = await requireActiveMembership(organizationId, userId);
  const data = membership.data();
  const permissions = Array.isArray(data.permissionsSnapshot) ? data.permissionsSnapshot : [];
  if (!["system_owner", "owner", "council_owner", "chairman", "adminManager"].includes(data.roleId) &&
      !permissions.some((permission) => ["fullAccess", "bookings.manage", "bookings.approve"].includes(permission))) {
    throw new HttpsError("permission-denied", "Booking management permission is required.");
  }
}

function requireAuth(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Authentication is required.");
  return request.auth.uid;
}

function requireString(value, name, max = 500) {
  if (typeof value !== "string" || !value.trim() || value.length > max) {
    throw new HttpsError("invalid-argument", `${name} is invalid.`);
  }
  return value.trim();
}

function requireBaisa(value, name) {
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new HttpsError("invalid-argument", "Invalid monetary amount.");
  }
  return value;
}

function requireNonNegativeBaisa(value, name) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new HttpsError("invalid-argument", "Invalid monetary amount.");
  }
  return value;
}

function serverReceiptReference(storagePath, bucket = admin.storage().bucket()) {
  const bucketName = bucket && typeof bucket.name === "string" ? bucket.name.trim() : "";
  if (!bucketName || bucketName.includes("/") || bucketName.includes("?")) {
    throw new HttpsError("internal", "The receipt Storage bucket is not configured.");
  }
  return `gs://${bucketName}/${storagePath}`;
}

function financialRateLimitId(operation, userId) {
  return `${operation}_${Buffer.from(userId, "utf8").toString("base64url")}`;
}

async function consumeFinancialRateLimitInTransaction(transaction, organization, userId, operation,
  { maxCount, windowMs }) {
  const reference = organization.collection("financial_rate_limits")
    .doc(financialRateLimitId(operation, userId));
  const snapshot = await transaction.get(reference);
  const nowDate = new Date();
  const cutoff = new Date(nowDate.getTime() - windowMs);
  const windowStartedAt = snapshot.exists ? snapshot.get("windowStartedAt") : null;
  const inWindow = Boolean(windowStartedAt && typeof windowStartedAt.toDate === "function" &&
    windowStartedAt.toDate() > cutoff);
  const currentCount = inWindow ? Number(snapshot.get("count") || 0) : 0;
  if (!Number.isSafeInteger(currentCount) || currentCount < 0 || currentCount >= maxCount) {
    throw new HttpsError("resource-exhausted", "Financial operation limit reached. Try again later.");
  }
  const now = timestamp();
  transaction.set(reference, {
    userId,
    operation,
    windowStartedAt: inWindow ? windowStartedAt : now,
    count: currentCount + 1,
    updatedAt: now,
  });
}

async function consumeFinancialRateLimit(organization, userId, operation, options) {
  return db().runTransaction((transaction) =>
    consumeFinancialRateLimitInTransaction(transaction, organization, userId, operation, options));
}

function setAudit(transaction, organization, requestId, actorUserId, action, targetType, targetId, changes) {
  const reference = organization.collection("audit_logs").doc(`${action.replace(/[^a-z0-9]+/gi, "_")}_${requestId}`);
  transaction.set(reference, {
    actorUserId,
    actorName: null,
    actorRole: null,
    action,
    targetType,
    targetId,
    organizationId: organization.id,
    oldValue: changes.oldValue || null,
    newValue: changes.newValue || null,
    createdAt: timestamp(),
    source: "financial_callable",
  });
}

function notification(userId, organizationId, id, title, body, type, transactionId, actorId,
  relatedEntityType = "receipt", money = null) {
  const payload = {
    notificationId: id,
    title,
    body,
    type,
    userId,
    organizationId,
    relatedEntityType,
    relatedEntityId: transactionId,
    status: "unread",
    createdAt: timestamp(),
    readAt: null,
    createdByUserId: actorId,
    deliverySource: "server",
  };
  if (money && Number.isSafeInteger(money.amountBaisa) && money.currencyCode === "OMR" &&
      typeof money.bodyTemplate === "string" && money.bodyTemplate.includes("{amount}")) {
    payload.amountBaisa = money.amountBaisa;
    payload.currencyCode = "OMR";
    payload.bodyTemplate = money.bodyTemplate;
    payload.body = money.bodyTemplate.replaceAll(
      "{amount}",
      formatOmaniRialForSystemNotification(money.amountBaisa)
    ).replaceAll("ر.ع..", "ر.ع.");
  }
  return payload;
}

function financialNotificationOutboxId(userId, notificationId) {
  return Buffer.from(`${userId}\n${notificationId}`, "utf8").toString("base64url");
}

function enqueueFinancialNotification(transaction, organization, payload) {
  const reference = organization.collection(financialNotificationOutbox)
    .doc(financialNotificationOutboxId(payload.userId, payload.notificationId));
  transaction.set(reference, {
    organizationId: organization.id,
    userId: payload.userId,
    notificationId: payload.notificationId,
    payload,
    status: "pending",
    createdAt: payload.createdAt,
    updatedAt: payload.createdAt,
    deliveredAt: null,
    attemptCount: 0,
  });
}

async function activeFinancialReviewerUserIds(organization) {
  const memberships = await organization.collection("memberships").where("status", "==", "active").get();
  return [...new Set(memberships.docs
    .filter((membership) => canReview(membership.data()))
    .map((membership) => membership.get("userId"))
    .filter((userId) => typeof userId === "string" && userId.length > 0))];
}

function encodePayableChargePageToken(organizationId, membershipIds, cursors) {
  return Buffer.from(JSON.stringify({
    version: payableChargeTokenVersion,
    organizationId,
    membershipIds,
    cursors,
  }), "utf8").toString("base64url");
}

function decodePayableChargePageToken(value, organizationId, membershipIds) {
  if (value == null) return {};
  if (typeof value !== "string" || value.length < 1 || value.length > 8192) {
    throw new HttpsError("invalid-argument", "Payable charge page token is invalid.");
  }
  try {
    const decoded = JSON.parse(Buffer.from(value, "base64url").toString("utf8"));
    if (decoded.version !== payableChargeTokenVersion || decoded.organizationId !== organizationId ||
        !Array.isArray(decoded.membershipIds) || decoded.membershipIds.length !== membershipIds.length ||
        decoded.membershipIds.some((id, index) => id !== membershipIds[index]) ||
        !decoded.cursors || typeof decoded.cursors !== "object" || Array.isArray(decoded.cursors)) {
      throw new Error("token scope mismatch");
    }
    const cursorMembershipIds = Object.keys(decoded.cursors).sort();
    if (cursorMembershipIds.length !== membershipIds.length ||
        cursorMembershipIds.some((id, index) => id !== membershipIds[index])) {
      throw new Error("token cursor scope mismatch");
    }
    const cursors = {};
    for (const [membershipId, cursor] of Object.entries(decoded.cursors)) {
      if (!membershipIds.includes(membershipId) ||
          (cursor !== null && (typeof cursor !== "string" || cursor.length < 1 || cursor.length > 128))) {
        throw new Error("token cursor invalid");
      }
      cursors[membershipId] = cursor;
    }
    return cursors;
  } catch (_) {
    throw new HttpsError("invalid-argument", "Payable charge page token is invalid.");
  }
}

async function userPublicProfile(userId) {
  const [user, legacy] = await Promise.all([
    db().collection("users").doc(userId).get(),
    db().collection("members").doc(userId).get(),
  ]);
  const source = user.exists ? user.data() : legacy.exists ? legacy.data() : {};
  return {
    fullName: String(source.fullName || source.name || ""),
    photoUrl: source.photoUrl || null,
  };
}

async function ensureSubscriptionCharge(accountSnapshot, { nowDate = new Date() } = {}) {
  if (!accountSnapshot.exists) return "missing";
  const account = accountSnapshot.data();
  const organization = accountSnapshot.ref.parent.parent;
  if (!organization || !account.planId || !account.membershipId || !account.userId) return "incomplete";
  const [settings, plan] = await Promise.all([
    organization.collection("financial_settings").doc("main").get(),
    organization.collection("subscription_plans").doc(account.planId).get(),
  ]);
  if (!settings.exists || !plan.exists || plan.get("active") !== true) return "disabled";
  if (!["subscription", "subscriptionAndBooking"].includes(settings.get("feeMode"))) return "not-subscription";
  if (account.feeOverrideType === "exempt") {
    const existing = await organization.collection("charges").where("membershipId", "==", account.membershipId).get();
    const batch = db().batch();
    existing.docs.filter((doc) => doc.get("chargeType") === "subscription" && ["unpaid", "partial", "overdue", "rejected"].includes(doc.get("status"))).forEach((doc) => batch.update(doc.ref, {
      status: "waived",
      waiverReason: account.exemptionReason || "إعفاء موثق في حساب العضو",
      updatedAt: timestamp(),
      updatedBy: account.updatedBy || "financial-account-trigger",
    }));
    await batch.commit();
    return "exempt";
  }
  const planData = plan.data();
  const amountBaisa = account.feeOverrideType === "custom" ? account.customAmountBaisa : planData.amountBaisa;
  if (!Number.isSafeInteger(amountBaisa) || amountBaisa <= 0) return "invalid-amount";
  const period = subscriptionPeriod(planData.billingCycle, nowDate);
  const idempotencyKey = canonicalChargeKey({
    organizationId: organization.id,
    membershipId: account.membershipId,
    chargeType: "subscription",
    periodKey: period.periodKey,
    sourceId: account.planId,
  });
  const chargeRef = organization.collection("charges").doc(idempotencyKey);
  const matching = await organization.collection("charges")
    .where("membershipId", "==", account.membershipId)
    .where("chargeType", "==", "subscription")
    .where("periodKey", "==", period.periodKey)
    .limit(1)
    .get();
  if (!matching.empty) return "exists";
  try {
    await chargeRef.create({
      chargeId: idempotencyKey,
      organizationId: organization.id,
      membershipId: account.membershipId,
      userId: account.userId,
      chargeType: "subscription",
      sourceId: account.planId,
      periodKey: period.periodKey,
      idempotencyKey,
      titleArabic: `${planData.nameArabic || "اشتراك"} - ${period.periodKey}`,
      descriptionArabic: planData.descriptionArabic || null,
      amountDueBaisa: amountBaisa,
      amountPaidBaisa: 0,
      balanceBaisa: amountBaisa,
      dueDate: Timestamp.fromDate(period.dueDate),
      status: "unpaid",
      lastTransactionId: null,
      createdAt: timestamp(),
      updatedAt: timestamp(),
      createdBy: account.updatedBy || "financial-account-trigger",
    });
    return "created";
  } catch (error) {
    if (error.code === 6 || error.code === "already-exists") return "exists";
    throw error;
  }
}

exports.syncMemberDirectory = onDocumentWritten(
  { document: "organizations/{organizationId}/memberships/{membershipId}", region: "us-central1" },
  async (event) => {
    const { organizationId, membershipId } = event.params;
    const after = event.data.after;
    const reference = db().collection("organizations").doc(organizationId).collection("member_directory").doc(membershipId);
    if (!after.exists || after.get("status") !== "active") {
      await reference.delete().catch(() => {});
      return;
    }
    const membership = after.data();
    const profile = await userPublicProfile(membership.userId);
    if (!profile.fullName) {
      console.warn(`Missing public name for membership ${organizationId}/${membershipId}`);
      return;
    }
    await reference.set({
      membershipId,
      userId: membership.userId,
      fullName: profile.fullName,
      memberNumber: String(membership.memberNumber || ""),
      photoUrl: profile.photoUrl,
      active: true,
      searchNameNormalized: normalizeArabic(profile.fullName),
      searchPrefixes: searchPrefixes(profile.fullName),
      updatedAt: timestamp(),
    });
  }
);

exports.syncMemberDirectoryProfile = onDocumentWritten(
  { document: "users/{userId}", region: "us-central1" },
  async (event) => {
    if (!event.data.after.exists) return;
    const { userId } = event.params;
    const profile = event.data.after.data();
    const fullName = String(profile.fullName || profile.name || "");
    if (!fullName) return;
    const memberships = await db().collectionGroup("memberships").where("userId", "==", userId).where("status", "==", "active").get();
    const batch = db().batch();
    memberships.docs.forEach((membership) => {
      const organization = membership.ref.parent.parent;
      if (!organization) return;
      batch.set(organization.collection("member_directory").doc(membership.id), {
        membershipId: membership.id,
        userId,
        fullName,
        memberNumber: String(membership.get("memberNumber") || ""),
        photoUrl: profile.photoUrl || null,
        active: true,
        searchNameNormalized: normalizeArabic(fullName),
        searchPrefixes: searchPrefixes(fullName),
        updatedAt: timestamp(),
      });
    });
    await batch.commit();
  }
);

exports.onMemberFinancialAccountWritten = onDocumentWritten(
  { document: "organizations/{organizationId}/member_accounts/{membershipId}", region: "us-central1" },
  async (event) => {
    if (!event.data.after.exists) return;
    const result = await ensureSubscriptionCharge(event.data.after);
    console.log(`Financial account ${event.params.organizationId}/${event.params.membershipId}: ${result}`);
  }
);

async function bookingFinancialLifecycleHandler(event) {
    if (!event.data.after.exists) return;
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.data();
    if (before && before.status === after.status) return;
    const { organizationId, bookingId } = event.params;
    const organization = db().collection("organizations").doc(organizationId);
    if (!after.userId) return;
    const candidateMembership = await membershipForUser(organizationId, after.userId);
    const result = await db().runTransaction(async (transaction) => {
      const settingsRef = organization.collection("financial_settings").doc("main");
      const settings = await transaction.get(settingsRef);
      if (!settings.exists || !["booking", "subscriptionAndBooking"].includes(settings.get("feeMode"))) return "disabled";
      let activeMembership = null;
      if (candidateMembership) {
        const currentMembership = await transaction.get(candidateMembership.ref);
        if (currentMembership.exists && currentMembership.get("status") === "active" &&
            currentMembership.get("userId") === after.userId) activeMembership = currentMembership;
      }
      const accountType = activeMembership ? "member" : "guest";
      const membershipId = activeMembership ? activeMembership.id : null;
      const chargeId = after.financialChargeId || canonicalChargeKey({
        organizationId,
        membershipId,
        userId: after.userId,
        accountType,
        chargeType: "booking",
        sourceId: bookingId,
      });
      const chargeRef = organization.collection("charges").doc(chargeId);
      const existing = await transaction.get(chargeRef);
      const amountBaisa = Number(settings.get(accountType === "member" ? "memberBookingFeeBaisa" : "nonMemberBookingFeeBaisa"));
      const now = timestamp();
      if (after.status === "approved") {
        if (existing.exists) return "exists";
        if (!Number.isSafeInteger(amountBaisa) || amountBaisa <= 0) return "zero-fee";
        const dueDate = after.bookingDate && typeof after.bookingDate.toDate === "function" ? after.bookingDate : now;
        const data = {
          chargeId, organizationId, accountType, membershipId, userId: after.userId,
          bookingId, chargeType: "booking", sourceId: bookingId, periodKey: null,
          idempotencyKey: chargeId,
          titleArabic: "رسوم حجز المجلس",
          descriptionArabic: `مرجع الحجز: ${bookingId}`,
          amountDueBaisa: amountBaisa, amountPaidBaisa: 0, balanceBaisa: amountBaisa,
          dueDate, status: "unpaid", lastTransactionId: null,
          createdAt: now, updatedAt: now, createdBy: after.approvedBy || "booking-financial-trigger",
        };
        transaction.create(chargeRef, data);
        transaction.set(event.data.after.ref, {
          financialChargeId: chargeId,
          financialAccountType: accountType,
          financialMembershipId: membershipId,
          updatedAt: now,
        }, { merge: true });
        setAudit(transaction, organization, event.id, after.approvedBy || after.userId,
          "financial.booking_charge.created", "charge", chargeId, { newValue: data });
        return "created";
      }
      if (["rejected", "cancelled"].includes(after.status) && existing.exists) {
        const charge = existing.data();
        const nextStatus = Number(charge.amountPaidBaisa || 0) > 0 ? "refundRequired" : "cancelled";
        transaction.update(chargeRef, {
          status: nextStatus,
          cancellationReason: after.rejectionReason || after.cancellationReason || after.status,
          updatedAt: now,
          updatedBy: after.rejectedBy || after.cancelledBy || "booking-financial-trigger",
        });
        setAudit(transaction, organization, event.id, after.rejectedBy || after.cancelledBy || after.userId,
          "financial.booking_charge.cancelled", "charge", chargeId, {
            oldValue: { status: charge.status }, newValue: { status: nextStatus },
          });
        return nextStatus;
      }
      return "ignored";
    });
    if (["created", "cancelled", "refundRequired"].includes(result)) {
      const message = result === "created" ? "تم إنشاء رسم الحجز في ملخص حسابك."
        : result === "refundRequired" ? "يتطلب رسم الحجز مراجعة استرداد مالي."
          : "تم إلغاء رسم الحجز غير المدفوع.";
      await db().collection("users").doc(after.userId).collection("notifications")
        .doc(`bookingFinancial_${bookingId}_${after.status}`).set(
          notification(after.userId, organizationId, `bookingFinancial_${bookingId}_${after.status}`,
            "تحديث رسوم الحجز", message, "bookingFinancial", bookingId,
            after.approvedBy || after.rejectedBy || after.cancelledBy || after.userId)
        );
    }
    console.log("Booking financial lifecycle", { organizationId, bookingId, result });
}
exports.onBookingFinancialLifecycle = onDocumentWritten(
  { document: "organizations/{organizationId}/bookings/{bookingId}", region: "us-central1" },
  bookingFinancialLifecycleHandler
);

async function requestBookingCancellationHandler(request) {
  const userId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const bookingId = requireString(request.data.bookingId, "bookingId", 128);
  const reason = typeof request.data.reason === "string" ? request.data.reason.trim().slice(0, 500) : "";
  const organization = db().collection("organizations").doc(organizationId);
  const bookingRef = organization.collection("bookings").doc(bookingId);
  const result = await db().runTransaction(async (transaction) => {
    const booking = await transaction.get(bookingRef);
    if (!booking.exists) throw new HttpsError("not-found", "Booking not found.");
    if (booking.get("userId") !== userId || booking.get("organizationId") !== organizationId) {
      throw new HttpsError("permission-denied", "Only the booking owner can cancel it.");
    }
    const status = booking.get("status");
    const slotKey = booking.get("slotKey");
    const slotRef = typeof slotKey === "string" && slotKey
      ? organization.collection("booking_slots").doc(slotKey) : null;
    const slot = slotRef ? await transaction.get(slotRef) : null;
    const now = timestamp();
    if (status === "pending") {
      if (slot && slot.exists && slot.get("bookingId") === bookingId) {
        transaction.delete(slotRef);
      }
      transaction.update(bookingRef, {
        status: "cancelled", cancellationReason: reason || null, cancelledBy: userId,
        cancelledAt: now, updatedAt: now,
      });
      setAudit(transaction, organization, request.rawRequest && request.rawRequest.headers["x-request-id"] || bookingId,
        userId, "booking.cancelled_by_owner", "booking", bookingId,
        { oldValue: { status }, newValue: { status: "cancelled" } });
      return { status: "cancelled" };
    }
    if (status === "approved") {
      transaction.update(bookingRef, {
        status: "cancellationRequested", cancellationReason: reason || null,
        cancellationRequestedBy: userId, cancellationRequestedAt: now, updatedAt: now,
      });
      setAudit(transaction, organization, request.rawRequest && request.rawRequest.headers["x-request-id"] || bookingId,
        userId, "booking.cancellation_requested", "booking", bookingId,
        { oldValue: { status }, newValue: { status: "cancellationRequested" } });
      return { status: "cancellationRequested" };
    }
    throw new HttpsError("failed-precondition", "This booking cannot be cancelled in its current state.");
  });
  await db().collection("users").doc(userId).collection("notifications")
    .doc(`bookingCancellation_${bookingId}_${result.status}`).set(notification(
      userId, organizationId, `bookingCancellation_${bookingId}_${result.status}`,
      result.status === "cancelled" ? "تم إلغاء الحجز" : "تم إرسال طلب الإلغاء",
      result.status === "cancelled" ? "أُلغي طلب الحجز قبل اعتماده." : "طلب الإلغاء بانتظار مراجعة الإدارة.",
      "bookingCancellation", bookingId, userId, "booking"
    ));
  return result;
}
exports.requestBookingCancellation = onCall(sensitiveCallableOptions, requestBookingCancellationHandler);

async function reviewBookingCancellationHandler(request) {
  const reviewerId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const bookingId = requireString(request.data.bookingId, "bookingId", 128);
  const decision = requireString(request.data.decision, "decision", 20);
  if (!["approve", "reject"].includes(decision)) throw new HttpsError("invalid-argument", "Invalid decision.");
  const reason = decision === "reject" ? requireString(request.data.reason, "reason", 500) :
    (typeof request.data.reason === "string" ? request.data.reason.trim().slice(0, 500) : "");
  await requireBookingManager(organizationId, reviewerId);
  const organization = db().collection("organizations").doc(organizationId);
  const bookingRef = organization.collection("bookings").doc(bookingId);
  const initial = await bookingRef.get();
  if (!initial.exists) throw new HttpsError("not-found", "Booking not found.");
  let chargeRef = null;
  const financialChargeId = initial.get("financialChargeId");
  if (typeof financialChargeId === "string" && financialChargeId) {
    chargeRef = organization.collection("charges").doc(financialChargeId);
  } else {
    const matches = await organization.collection("charges").where("bookingId", "==", bookingId).limit(1).get();
    if (!matches.empty) chargeRef = matches.docs[0].ref;
  }
  const result = await db().runTransaction(async (transaction) => {
    const booking = await transaction.get(bookingRef);
    if (!booking.exists || booking.get("status") !== "cancellationRequested") {
      throw new HttpsError("failed-precondition", "Cancellation request is no longer pending.");
    }
    const slotKey = booking.get("slotKey");
    const slotRef = typeof slotKey === "string" && slotKey
      ? organization.collection("booking_slots").doc(slotKey) : null;
    const [charge, slot] = await Promise.all([
      chargeRef ? transaction.get(chargeRef) : null,
      slotRef ? transaction.get(slotRef) : null,
    ]);
    const now = timestamp();
    if (decision === "reject") {
      transaction.update(bookingRef, {
        status: "approved", cancellationRequestStatus: "rejected", cancellationReviewedBy: reviewerId,
        cancellationReviewedAt: now, cancellationRejectionReason: reason, updatedAt: now,
      });
      setAudit(transaction, organization, bookingId, reviewerId, "booking.cancellation_rejected", "booking", bookingId,
        { oldValue: { status: "cancellationRequested" }, newValue: { status: "approved" } });
      return { status: "approved", userId: booking.get("userId"), chargeStatus: null };
    }
    let chargeStatus = null;
    if (charge && charge.exists) {
      const paid = Number(charge.get("amountPaidBaisa") || 0);
      chargeStatus = paid > 0 ? "refundRequired" : "cancelled";
      transaction.update(charge.ref, {
        status: chargeStatus, cancellationReason: reason || booking.get("cancellationReason") || "approved cancellation",
        updatedAt: now, updatedBy: reviewerId,
      });
    }
    if (slot && slot.exists && slot.get("bookingId") === bookingId) {
      transaction.delete(slotRef);
    }
    transaction.update(bookingRef, {
      status: "cancelled", cancellationRequestStatus: "approved", cancelledBy: reviewerId,
      cancelledAt: now, cancellationReviewedBy: reviewerId, cancellationReviewedAt: now, updatedAt: now,
    });
    setAudit(transaction, organization, bookingId, reviewerId, "booking.cancellation_approved", "booking", bookingId,
      { oldValue: { status: "cancellationRequested" }, newValue: { status: "cancelled", chargeStatus } });
    return { status: "cancelled", userId: booking.get("userId"), chargeStatus };
  });
  await db().collection("users").doc(result.userId).collection("notifications")
    .doc(`bookingCancellationReview_${bookingId}_${decision}`).set(notification(
      result.userId, organizationId, `bookingCancellationReview_${bookingId}_${decision}`,
      decision === "approve" ? "تم قبول إلغاء الحجز" : "تم رفض إلغاء الحجز",
      decision === "approve" ? "أُلغي الحجز، وأي مبلغ مدفوع سيخضع لمراجعة الاسترداد." : reason,
      "bookingCancellationReview", bookingId, reviewerId, "booking"
    ));
  return { status: result.status, chargeStatus: result.chargeStatus };
}
exports.reviewBookingCancellation = onCall(sensitiveCallableOptions, reviewBookingCancellationHandler);

async function getBookingAvailabilityHandler(request) {
  const userId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const year = Number(request.data.year);
  const month = Number(request.data.month);
  if (!Number.isInteger(year) || year < 2020 || year > 2100 || !Number.isInteger(month) || month < 1 || month > 12) {
    throw new HttpsError("invalid-argument", "A valid year and month are required.");
  }
  const organization = db().collection("organizations").doc(organizationId);
  const [membership, publicSettings] = await Promise.all([
    membershipForUser(organizationId, userId), organization.collection("settings").doc("organization").get(),
  ]);
  const allowed = (membership && membership.get("status") === "active") ||
    (publicSettings.exists && publicSettings.get("allowHallRental") === true);
  if (!allowed) throw new HttpsError("permission-denied", "Booking access is not enabled for this council.");
  // Oman is UTC+4 all year. Query exact Muscat month boundaries, not UTC month boundaries.
  const start = new Date(Date.UTC(year, month - 1, 1, -4));
  const end = new Date(Date.UTC(year, month, 1, -4));
  const bookings = [];
  let cursor = null;
  do {
    let query = organization.collection("bookings")
      .where("bookingDate", ">=", Timestamp.fromDate(start))
      .where("bookingDate", "<", Timestamp.fromDate(end))
      .orderBy("bookingDate")
      .orderBy(FieldPath.documentId())
      .limit(200);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    bookings.push(...page.docs.filter((document) =>
      ["pending", "approved", "cancellationRequested"].includes(document.get("status"))));
    cursor = page.size === 200 ? page.docs.at(-1) : null;
  } while (cursor);
  return {
    // Projection intentionally excludes owner identity, phone, notes, charge,
    // receipt, reviewer, and every financial field.
    days: bookings.map((doc) => ({
      date: doc.get("bookingDate").toDate().toISOString(),
      status: doc.get("status") === "approved" || doc.get("status") === "cancellationRequested" ? "approved" : "pending",
      resourceId: doc.get("resourceId") || "council_hall",
      startTime: doc.get("startTime") || null,
      endTime: doc.get("endTime") || null,
    })),
  };
}
exports.getBookingAvailability = onCall(sensitiveCallableOptions, getBookingAvailabilityHandler);

const scheduleEnvironmentKeys = {
  generateSubscriptionCharges: "FINANCIAL_SCHEDULE_GENERATE_SUBSCRIPTIONS_ENABLED",
  markFinancialChargesOverdue: "FINANCIAL_SCHEDULE_MARK_OVERDUE_ENABLED",
  cleanupOrphanFinancialReceipts: "FINANCIAL_SCHEDULE_CLEANUP_ORPHANS_ENABLED",
  expirePendingFinancialReceipts: "FINANCIAL_SCHEDULE_EXPIRE_RECEIPTS_ENABLED",
};

function scheduleGate(task, event, options = {}) {
  const environment = options.environment || process.env;
  const runId = String(options.runId || event && event.id || `${task}-local`);
  const globalEnabled = environment.FINANCIAL_SCHEDULES_ENABLED === "true";
  const taskEnabled = environment[scheduleEnvironmentKeys[task]] === "true";
  const dryRun = environment.FINANCIAL_SCHEDULE_DRY_RUN !== "false";
  if (!globalEnabled || !taskEnabled) {
    return { execute: false, result: { status: "disabled", task, runId, writes: 0 } };
  }
  if (dryRun) {
    return { execute: false, result: { status: "dry-run", task, runId, writes: 0 } };
  }
  return { execute: true, runId };
}

function logScheduleResult(log, result) {
  const method = log.info || log.log;
  method.call(log, "Financial schedule result", result);
}

async function generateSubscriptionChargesHandler(event, options = {}) {
  const database = options.database || db();
  const nowDate = options.nowDate || new Date();
  const processAccount = options.processAccount ||
    ((snapshot) => ensureSubscriptionCharge(snapshot, { nowDate }));
  const log = options.log || console;
  const gate = scheduleGate("generateSubscriptionCharges", event, options);
  if (!gate.execute) {
    logScheduleResult(log, gate.result);
    return gate.result;
  }
  const stats = await processPaginated({
    pageSize: options.pageSize || 200,
    concurrency: options.concurrency || 10,
    fetchPage: async ({ cursor, pageSize }) => {
      let query = database.collectionGroup("member_accounts")
        .orderBy(FieldPath.documentId()).limit(pageSize);
      if (cursor) query = query.startAfter(cursor);
      const snapshot = await query.get();
      return {
        items: snapshot.docs,
        nextCursor: snapshot.size === pageSize ? snapshot.docs[snapshot.docs.length - 1] : null,
      };
    },
    processItem: processAccount,
  });
  const result = { status: "completed", task: "generateSubscriptionCharges", runId: gate.runId, ...stats };
  logScheduleResult(log, result);
  return result;
}

exports.generateSubscriptionChargesDaily = onSchedule(
  {
    schedule: "every day 02:00", timeZone: "Asia/Muscat", region: "us-central1",
    timeoutSeconds: 540, memory: "512MiB", maxInstances: 1,
  },
  generateSubscriptionChargesHandler
);

async function markFinancialChargesOverdueHandler(event, options = {}) {
  const database = options.database || db();
  const nowDate = options.nowDate || new Date();
  const log = options.log || console;
  const gate = scheduleGate("markFinancialChargesOverdue", event, options);
  if (!gate.execute) {
    logScheduleResult(log, gate.result);
    return gate.result;
  }
  const stats = await processPaginated({
    pageSize: options.pageSize || 200,
    concurrency: options.concurrency || 20,
    fetchPage: async ({ cursor, pageSize }) => {
      let query = database.collectionGroup("charges")
        .where("status", "in", ["unpaid", "partial"])
        .orderBy(FieldPath.documentId()).limit(pageSize);
      if (cursor) query = query.startAfter(cursor);
      const snapshot = await query.get();
      return { items: snapshot.docs, nextCursor: snapshot.size === pageSize ? snapshot.docs.at(-1) : null };
    },
    processItem: async (doc) => {
      const dueTimestamp = doc.get("dueDate");
      const dueDate = dueTimestamp && typeof dueTimestamp.toDate === "function" ? dueTimestamp.toDate() : null;
      if (!dueDate || !isOverdueInMuscat(dueDate, nowDate)) return "not-due";
      await doc.ref.update({ status: "overdue", updatedAt: timestamp(), updatedBy: "daily-overdue-scheduler" });
      return "overdue";
    },
  });
  const result = { status: "completed", task: "markFinancialChargesOverdue", runId: gate.runId, ...stats };
  logScheduleResult(log, result);
  return result;
}

exports.markFinancialChargesOverdue = onSchedule(
  {
    schedule: "every day 02:30", timeZone: "Asia/Muscat", region: "us-central1",
    timeoutSeconds: 540, memory: "512MiB", maxInstances: 1,
  },
  markFinancialChargesOverdueHandler
);

exports.updateFinancialSettings = onCall(sensitiveCallableOptions, async (request) => {
  const actorUserId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const requestId = requireString(request.data.requestId, "requestId", 128);
  await requireFinanceManager(organizationId, actorUserId);
  const feeMode = requireString(request.data.feeMode, "feeMode", 40);
  if (!["free", "subscription", "booking", "subscriptionAndBooking"].includes(feeMode)) {
    throw new HttpsError("invalid-argument", "Invalid financial fee mode.");
  }
  const organization = db().collection("organizations").doc(organizationId);
  const reference = organization.collection("financial_settings").doc("main");
  await db().runTransaction(async (transaction) => {
    const current = await transaction.get(reference);
    const now = timestamp();
    const data = {
      organizationId,
      currency: "OMR",
      feeMode,
      receiptPaymentsEnabled: request.data.receiptPaymentsEnabled !== false,
      onlinePaymentsEnabled: false,
      onlinePaymentProvider: null,
      allowMonthlyPlans: request.data.allowMonthlyPlans !== false,
      allowAnnualPlans: request.data.allowAnnualPlans !== false,
      memberBookingFeeBaisa: requireNonNegativeBaisa(request.data.memberBookingFeeBaisa, "memberBookingFeeBaisa"),
      nonMemberBookingFeeBaisa: requireNonNegativeBaisa(request.data.nonMemberBookingFeeBaisa, "nonMemberBookingFeeBaisa"),
      eventBookingFeeBaisa: requireNonNegativeBaisa(request.data.eventBookingFeeBaisa, "eventBookingFeeBaisa"),
      updatedAt: now,
      updatedBy: actorUserId,
      ...(current.exists ? {} : { createdAt: now }),
    };
    transaction.set(reference, data, { merge: true });
    setAudit(transaction, organization, requestId, actorUserId, "financial.settings.updated", "financial_settings", "main", {
      oldValue: current.exists ? current.data() : null,
      newValue: data,
    });
  });
  return { status: "updated" };
});

exports.saveFinancialPlan = onCall(sensitiveCallableOptions, async (request) => {
  const actorUserId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const requestId = requireString(request.data.requestId, "requestId", 128);
  await requireFinanceManager(organizationId, actorUserId);
  const billingCycle = requireString(request.data.billingCycle, "billingCycle", 20);
  if (!["monthly", "annual", "oneTime"].includes(billingCycle)) throw new HttpsError("invalid-argument", "Invalid billing cycle.");
  const organization = db().collection("organizations").doc(organizationId);
  const planId = request.data.planId ? requireString(request.data.planId, "planId", 128) : requestId;
  const reference = organization.collection("subscription_plans").doc(planId);
  await db().runTransaction(async (transaction) => {
    const current = await transaction.get(reference);
    const now = timestamp();
    const data = {
      planId,
      organizationId,
      nameArabic: requireString(request.data.nameArabic, "nameArabic", 120),
      descriptionArabic: String(request.data.descriptionArabic || "").trim().slice(0, 500),
      billingCycle,
      amountBaisa: requireNonNegativeBaisa(request.data.amountBaisa, "amountBaisa"),
      active: request.data.active === true,
      startDate: current.exists ? current.get("startDate") || now : now,
      endDate: null,
      createdAt: current.exists ? current.get("createdAt") || now : now,
      updatedAt: now,
      createdBy: current.exists ? current.get("createdBy") || actorUserId : actorUserId,
      updatedBy: actorUserId,
    };
    transaction.set(reference, data, { merge: true });
    setAudit(transaction, organization, requestId, actorUserId, "financial.plan.saved", "subscription_plan", planId, {
      oldValue: current.exists ? current.data() : null, newValue: data,
    });
  });
  return { planId };
});

exports.updateMemberFinancialAccount = onCall(sensitiveCallableOptions, async (request) => {
  const actorUserId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const requestId = requireString(request.data.requestId, "requestId", 128);
  const membershipId = requireString(request.data.membershipId, "membershipId", 128);
  await requireFinanceManager(organizationId, actorUserId);
  const overrideType = requireString(request.data.feeOverrideType, "feeOverrideType", 20);
  if (!["default", "custom", "exempt"].includes(overrideType)) throw new HttpsError("invalid-argument", "Invalid fee override type.");
  const organization = db().collection("organizations").doc(organizationId);
  const membershipRef = organization.collection("memberships").doc(membershipId);
  const accountRef = organization.collection("member_accounts").doc(membershipId);
  const planId = request.data.planId ? requireString(request.data.planId, "planId", 128) : null;
  await db().runTransaction(async (transaction) => {
    const refs = [membershipRef, accountRef];
    if (planId) refs.push(organization.collection("subscription_plans").doc(planId));
    const docs = await Promise.all(refs.map((reference) => transaction.get(reference)));
    const membership = docs[0];
    const current = docs[1];
    if (!membership.exists || membership.get("status") !== "active") throw new HttpsError("failed-precondition", "Member is not active.");
    if (planId && !docs[2].exists) throw new HttpsError("not-found", "Subscription plan not found.");
    const customAmountBaisa = overrideType === "custom"
      ? requireNonNegativeBaisa(request.data.customAmountBaisa, "customAmountBaisa") : null;
    const exemptionReason = overrideType === "exempt"
      ? requireString(request.data.exemptionReason, "exemptionReason", 500) : null;
    const now = timestamp();
    const data = {
      organizationId, membershipId, userId: membership.get("userId"), planId,
      planNameArabic: planId ? docs[2].get("nameArabic") || null : null,
      subscriptionStatus: planId ? "active" : "inactive",
      subscriptionStartDate: planId ? current.exists && current.get("subscriptionStartDate") || now : null,
      subscriptionEndDate: null,
      feeOverrideType: overrideType,
      customAmountBaisa,
      exemptionReason,
      createdAt: current.exists ? current.get("createdAt") || now : now,
      updatedAt: now,
      updatedBy: actorUserId,
    };
    transaction.set(accountRef, data, { merge: true });
    setAudit(transaction, organization, requestId, actorUserId, "financial.member_account.updated", "member_account", membershipId, {
      oldValue: current.exists ? current.data() : null, newValue: data,
    });
  });
  return { status: "updated" };
});

exports.createManualFinancialCharge = onCall(sensitiveCallableOptions, async (request) => {
  const actorUserId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const requestId = requireString(request.data.requestId, "requestId", 128);
  const membershipId = requireString(request.data.membershipId, "membershipId", 128);
  await requireFinanceManager(organizationId, actorUserId);
  const organization = db().collection("organizations").doc(organizationId);
  const chargeId = canonicalChargeKey({ organizationId, membershipId, chargeType: "other", sourceId: requestId });
  const membershipRef = organization.collection("memberships").doc(membershipId);
  const chargeRef = organization.collection("charges").doc(chargeId);
  const dueDate = new Date(requireString(request.data.dueDate, "dueDate", 50));
  if (Number.isNaN(dueDate.valueOf())) throw new HttpsError("invalid-argument", "Invalid due date.");
  await db().runTransaction(async (transaction) => {
    const [membership, existing] = await Promise.all([transaction.get(membershipRef), transaction.get(chargeRef)]);
    if (!membership.exists || membership.get("status") !== "active") throw new HttpsError("failed-precondition", "Member is not active.");
    if (existing.exists) return;
    const amountBaisa = requireBaisa(request.data.amountBaisa, "amountBaisa");
    const now = timestamp();
    const data = {
      chargeId, organizationId, membershipId, userId: membership.get("userId"),
      chargeType: "other", sourceId: requestId, periodKey: null,
      idempotencyKey: chargeId,
      titleArabic: requireString(request.data.titleArabic, "titleArabic", 160),
      descriptionArabic: String(request.data.descriptionArabic || "").trim().slice(0, 500),
      amountDueBaisa: amountBaisa, amountPaidBaisa: 0, balanceBaisa: amountBaisa,
      dueDate: Timestamp.fromDate(dueDate), status: "unpaid",
      lastTransactionId: null, createdAt: now, updatedAt: now, createdBy: actorUserId,
    };
    transaction.create(chargeRef, data);
    setAudit(transaction, organization, requestId, actorUserId, "financial.charge.created", "charge", chargeId, { newValue: data });
  });
  return { chargeId };
});

async function searchCouncilMembersHandler(request) {
  const userId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const normalized = normalizeArabic(requireString(request.data.query, "query", 100));
  if (normalized.length < 3) throw new HttpsError("invalid-argument", "Search requires at least three normalized characters.");
  await requireActiveMembership(organizationId, userId);
  const organization = db().collection("organizations").doc(organizationId);
  await consumeFinancialRateLimit(organization, userId, "member_search", {
    maxCount: 30,
    windowMs: 60 * 1000,
  });
  const snapshot = await organization
    .collection("member_directory")
    .where("active", "==", true)
    .where("searchPrefixes", "array-contains", normalized)
    .limit(10)
    .get();
  return {
    members: snapshot.docs.slice(0, 10).map((doc) => {
      const data = doc.data();
      return {
        membershipId: doc.id,
        userId: data.userId,
        fullName: data.fullName,
        memberNumber: data.memberNumber || "",
        photoUrl: data.photoUrl || null,
      };
    }),
  };
}
exports.searchCouncilMembers = onCall(sensitiveCallableOptions, searchCouncilMembersHandler);

function encodeFinancialMemberPageToken(organizationId, fullName, documentId) {
  return Buffer.from(JSON.stringify({
    version: financialMemberPageTokenVersion,
    organizationId,
    fullName,
    documentId,
  }), "utf8").toString("base64url");
}

function decodeFinancialMemberPageToken(value, organizationId) {
  if (value == null) return null;
  if (typeof value !== "string" || value.length < 1 || value.length > 4096) {
    throw new HttpsError("invalid-argument", "Financial member page token is invalid.");
  }
  try {
    const decoded = JSON.parse(Buffer.from(value, "base64url").toString("utf8"));
    if (decoded.version !== financialMemberPageTokenVersion || decoded.organizationId !== organizationId ||
        typeof decoded.fullName !== "string" || decoded.fullName.length > 500 ||
        typeof decoded.documentId !== "string" || !decoded.documentId || decoded.documentId.length > 128) {
      throw new Error("invalid token payload");
    }
    return decoded;
  } catch (_) {
    throw new HttpsError("invalid-argument", "Financial member page token is invalid.");
  }
}

async function listFinancialMembersHandler(request) {
  const userId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  await requireReviewer(organizationId, userId);
  const requestedPageSize = request.data.pageSize == null ? financialMemberPageSize : request.data.pageSize;
  if (!Number.isSafeInteger(requestedPageSize) || requestedPageSize < 1 || requestedPageSize > financialMemberPageSize) {
    throw new HttpsError("invalid-argument", `pageSize must be between 1 and ${financialMemberPageSize}.`);
  }
  const cursor = decodeFinancialMemberPageToken(request.data.pageToken, organizationId);
  let memberQuery = db().collection("organizations").doc(organizationId)
    .collection("member_directory").where("active", "==", true)
    .orderBy("fullName").orderBy(FieldPath.documentId()).limit(requestedPageSize + 1);
  if (cursor) memberQuery = memberQuery.startAfter(cursor.fullName, cursor.documentId);
  const snapshot = await memberQuery.get();
  const hasMore = snapshot.docs.length > requestedPageSize;
  const documents = snapshot.docs.slice(0, requestedPageSize);
  const last = documents.at(-1);
  return {
    members: documents.map((doc) => {
      const data = doc.data();
      return {
        membershipId: doc.id,
        userId: data.userId,
        fullName: data.fullName,
        memberNumber: data.memberNumber || "",
        photoUrl: data.photoUrl || null,
      };
    }),
    nextPageToken: hasMore && last
      ? encodeFinancialMemberPageToken(organizationId, String(last.get("fullName") || ""), last.id)
      : null,
  };
}
exports.listFinancialMembers = onCall(sensitiveCallableOptions, listFinancialMembersHandler);

async function getPayableChargesHandler(request) {
  const userId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const membershipIds = request.data.membershipIds;
  if (!Array.isArray(membershipIds) || membershipIds.length < 1 || membershipIds.length > 10) {
    throw new HttpsError("invalid-argument", "One to ten memberships are required.");
  }
  await requireActiveMembership(organizationId, userId);
  const organization = db().collection("organizations").doc(organizationId);
  const uniqueMembershipIds = [...new Set(membershipIds.map((value) => requireString(value, "membershipId", 128)))].sort();
  const memberships = await Promise.all(uniqueMembershipIds.map((id) => organization.collection("memberships").doc(id).get()));
  if (memberships.some((item) => !item.exists || item.get("status") !== "active")) {
    throw new HttpsError("failed-precondition", "A beneficiary is not an active council member.");
  }
  const requestedPageSize = request.data.pageSize == null ? payableChargePageSize : request.data.pageSize;
  if (!Number.isSafeInteger(requestedPageSize) || requestedPageSize < 1 || requestedPageSize > payableChargePageSize) {
    throw new HttpsError("invalid-argument", `pageSize must be between 1 and ${payableChargePageSize}.`);
  }
  const cursors = decodePayableChargePageToken(
    request.data.pageToken,
    organizationId,
    uniqueMembershipIds
  );
  const chargePages = await Promise.all(uniqueMembershipIds.map(async (membershipId) => {
    if (cursors[membershipId] === null) return { membershipId, docs: [], nextCursor: null };
    let query = organization.collection("charges")
      .where("membershipId", "==", membershipId)
      .orderBy(FieldPath.documentId())
      .limit(requestedPageSize + 1);
    if (typeof cursors[membershipId] === "string") query = query.startAfter(cursors[membershipId]);
    const snapshot = await query.get();
    const hasMore = snapshot.docs.length > requestedPageSize;
    const docs = snapshot.docs.slice(0, requestedPageSize);
    return {
      membershipId,
      docs,
      nextCursor: hasMore ? docs[docs.length - 1].id : null,
    };
  }));
  const payableStatuses = new Set(["unpaid", "partial", "overdue", "rejected"]);
  const charges = [];
  const nextCursors = { ...cursors };
  chargePages.forEach((page) => {
    nextCursors[page.membershipId] = page.nextCursor;
    page.docs.forEach((doc) => {
    const data = doc.data();
    if (!payableStatuses.has(data.status) || !Number.isSafeInteger(data.balanceBaisa) || data.balanceBaisa <= 0) return;
    charges.push({
      chargeId: doc.id,
      organizationId,
      membershipId: data.membershipId,
      userId: data.userId,
      chargeType: data.chargeType,
      periodKey: data.periodKey || null,
      titleArabic: data.titleArabic || "رسم",
      descriptionArabic: data.descriptionArabic || null,
      amountDueBaisa: data.amountDueBaisa,
      amountPaidBaisa: data.amountPaidBaisa,
      balanceBaisa: data.balanceBaisa,
      dueDate: data.dueDate ? data.dueDate.toDate().toISOString() : null,
      status: data.status,
    });
    });
  });
  const now = Date.now();
  const lockSnapshots = await Promise.all(charges.map((charge) => organization
    .collection("pending_receipt_locks").doc(`${userId}_${charge.chargeId}`).get()));
  charges.forEach((charge, index) => {
    const lock = lockSnapshots[index];
    const expiresAt = lock.exists && lock.get("expiresAt");
    const hasPendingReceipt = Boolean(expiresAt && expiresAt.toMillis() > now);
    charge.hasPendingReceipt = hasPendingReceipt;
    charge.pendingTransactionId = hasPendingReceipt ? String(lock.get("transactionId") || "") : null;
  });
  const hasMore = uniqueMembershipIds.some((membershipId) => nextCursors[membershipId] !== null);
  return {
    charges,
    nextPageToken: hasMore
      ? encodePayableChargePageToken(organizationId, uniqueMembershipIds, nextCursors)
      : null,
  };
}
exports.getPayableCharges = onCall(sensitiveCallableOptions, getPayableChargesHandler);

async function getGuestBookingChargeHandler(request) {
  const userId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const bookingId = requireString(request.data.bookingId, "bookingId", 128);
  const organization = db().collection("organizations").doc(organizationId);
  const booking = await organization.collection("bookings").doc(bookingId).get();
  if (!booking.exists || booking.get("organizationId") !== organizationId || booking.get("userId") !== userId) {
    throw new HttpsError("permission-denied", "Booking ownership mismatch.");
  }
  const chargeId = booking.get("financialChargeId");
  if (typeof chargeId !== "string" || !chargeId) return { charge: null };
  const charge = await organization.collection("charges").doc(chargeId).get();
  if (!charge.exists || charge.get("accountType") !== "guest" || charge.get("userId") !== userId || charge.get("bookingId") !== bookingId) {
    throw new HttpsError("permission-denied", "Guest booking charge mismatch.");
  }
  const data = charge.data();
  return { charge: {
    chargeId: charge.id, bookingId, organizationId, accountType: "guest", chargeType: "booking",
    titleArabic: data.titleArabic || "رسم حجز", amountDueBaisa: data.amountDueBaisa,
    amountPaidBaisa: data.amountPaidBaisa, balanceBaisa: data.balanceBaisa, status: data.status,
    lastTransactionId: data.lastTransactionId || null,
  } };
}
exports.getGuestBookingCharge = onCall(sensitiveCallableOptions, getGuestBookingChargeHandler);

async function submitGuestBookingReceiptHandler(request) {
  const payerUserId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const bookingId = requireString(request.data.bookingId, "bookingId", 128);
  const chargeId = requireString(request.data.chargeId, "chargeId", 128);
  const receiptId = requireString(request.data.receiptId, "receiptId", 128);
  const amountDeclaredBaisa = requireBaisa(request.data.amountDeclaredBaisa, "amountDeclaredBaisa");
  const balanceBeforeBaisa = requireBaisa(request.data.balanceBeforeBaisa, "balanceBeforeBaisa");
  const receiptStoragePath = requireString(request.data.receiptStoragePath, "receiptStoragePath", 1024);
  const fileName = requireString(request.data.fileName, "fileName", 255);
  const fileType = requireString(request.data.fileType, "fileType", 100).toLowerCase();
  const identity = receiptStorageIdentity(receiptStoragePath);
  if (!identity || identity.organizationId !== organizationId || identity.userId !== payerUserId || identity.receiptId !== receiptId) {
    throw new HttpsError("permission-denied", "Receipt path ownership mismatch.");
  }
  validateReceiptFileName(fileName, receiptStoragePath, fileType);
  const receiptUrl = serverReceiptReference(receiptStoragePath);
  const organization = db().collection("organizations").doc(organizationId);
  const bookingRef = organization.collection("bookings").doc(bookingId);
  const chargeRef = organization.collection("charges").doc(chargeId);
  const transactionRef = organization.collection("transactions").doc(receiptId);
  const profile = await userPublicProfile(payerUserId);
  const reviewerUserIds = await activeFinancialReviewerUserIds(organization);
  const result = await db().runTransaction(async (transaction) => {
    const [booking, charge, existing] = await Promise.all([
      transaction.get(bookingRef), transaction.get(chargeRef), transaction.get(transactionRef),
    ]);
    if (existing.exists) {
      if (existing.get("payerUserId") !== payerUserId || existing.get("receiptStoragePath") !== receiptStoragePath) {
        throw new HttpsError("already-exists", "Receipt identifier is already in use.");
      }
      return { idempotent: true };
    }
    if (!booking.exists || booking.get("userId") !== payerUserId || booking.get("organizationId") !== organizationId) {
      throw new HttpsError("permission-denied", "Booking ownership mismatch.");
    }
    if (!charge.exists || charge.get("organizationId") !== organizationId || charge.get("accountType") !== "guest" ||
        charge.get("userId") !== payerUserId || charge.get("bookingId") !== bookingId || booking.get("financialChargeId") !== chargeId) {
      throw new HttpsError("permission-denied", "Only your own guest booking charge can be paid.");
    }
    if (!["unpaid", "partial", "overdue", "rejected"].includes(charge.get("status")) ||
        charge.get("balanceBaisa") !== balanceBeforeBaisa || amountDeclaredBaisa > balanceBeforeBaisa) {
      throw new HttpsError("failed-precondition", "Charge balance changed or was overpaid.");
    }
    const lockRef = organization.collection("pending_receipt_locks").doc(`${payerUserId}_${chargeId}`);
    const lock = await transaction.get(lockRef);
    await consumeFinancialRateLimitInTransaction(
      transaction,
      organization,
      payerUserId,
      "guest_receipt",
      { maxCount: 10, windowMs: 60 * 60 * 1000 }
    );
    const nowDate = new Date();
    if (lock.exists && lock.get("expiresAt") && lock.get("expiresAt").toDate() > nowDate) {
      throw new HttpsError("already-exists", "A receipt for this charge is already pending.");
    }
    const now = timestamp();
    const expiresAt = Timestamp.fromMillis(now.toMillis() + 48 * 60 * 60 * 1000);
    const allocation = {
      beneficiaryUserId: payerUserId, beneficiaryMembershipId: null,
      beneficiaryName: profile.fullName || "مستأجر المجلس", chargeId,
      chargeTitle: String(charge.get("titleArabic") || "رسم حجز"),
      amountAllocatedBaisa: amountDeclaredBaisa, balanceBeforeBaisa, statusBefore: charge.get("status"),
    };
    transaction.set(lockRef, { payerUserId, chargeId, transactionId: receiptId, expiresAt, createdAt: now });
    transaction.set(transactionRef, {
      transactionId: receiptId, organizationId, payerUserId, payerMembershipId: null,
      payerName: profile.fullName || "مستأجر المجلس", payerMemberNumber: "", paymentScope: "self",
      amountDeclaredBaisa, allocationTotalBaisa: amountDeclaredBaisa, differenceBaisa: 0,
      receiptUrl, receiptStoragePath, fileName, fileType,
      reviewStatus: "pending", status: "pendingReview", currentStatus: "submitted",
      submittedAt: now, expiresAt, reviewedAt: null, reviewedBy: null, rejectionReason: null,
      allocations: [allocation], beneficiaryMembershipIds: [], beneficiaryUserIds: [payerUserId],
      allocationChargeIds: [chargeId], bookingId, accountType: "guest", createdAt: now, updatedAt: now,
    });
    enqueueFinancialNotification(transaction, organization,
      notification(payerUserId, organizationId, `receiptReceived_${receiptId}`, "تم إرسال الإيصال",
        `إيصال الحجز بقيمة ${formatOmaniRialForSystemNotification(amountDeclaredBaisa)} قيد المراجعة.`,
        "receiptReceived", receiptId, payerUserId, "receipt", {
          amountBaisa: amountDeclaredBaisa,
          currencyCode: "OMR",
          bodyTemplate: "إيصال الحجز بقيمة {amount} قيد المراجعة.",
        }));
    reviewerUserIds.forEach((reviewerId) => enqueueFinancialNotification(transaction, organization,
      notification(reviewerId, organizationId, `receiptSubmitted_${receiptId}`, "إيصال حجز للمراجعة",
        `يوجد إيصال حجز بقيمة ${formatOmaniRialForSystemNotification(amountDeclaredBaisa)} للمراجعة.`,
        "receiptSubmitted", receiptId, payerUserId, "receipt", {
          amountBaisa: amountDeclaredBaisa,
          currencyCode: "OMR",
          bodyTemplate: "يوجد إيصال حجز بقيمة {amount} للمراجعة.",
        })));
    return { idempotent: false };
  });
  return { transactionId: receiptId, idempotent: result.idempotent };
}
exports.submitGuestBookingReceipt = onCall(sensitiveCallableOptions, submitGuestBookingReceiptHandler);

async function submitFinancialReceiptHandler(request) {
  const payerUserId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const payerMembershipId = requireString(request.data.payerMembershipId, "payerMembershipId", 128);
  const paymentScope = requireString(request.data.paymentScope, "paymentScope", 20);
  if (!["self", "others", "mixed"].includes(paymentScope)) throw new HttpsError("invalid-argument", "Invalid payment scope.");
  const amountDeclaredBaisa = requireBaisa(request.data.amountDeclaredBaisa, "amountDeclaredBaisa");
  const receiptStoragePath = requireString(request.data.receiptStoragePath, "receiptStoragePath", 1024);
  const fileName = requireString(request.data.fileName, "fileName", 255);
  const fileType = requireString(request.data.fileType, "fileType", 100).toLowerCase();
  const receiptId = requireString(request.data.receiptId, "receiptId", 128);
  const storageIdentity = receiptStorageIdentity(receiptStoragePath);
  if (!storageIdentity || storageIdentity.organizationId !== organizationId ||
      storageIdentity.userId !== payerUserId || storageIdentity.receiptId !== receiptId) {
    throw new HttpsError("permission-denied", "Receipt storage path does not belong to the payer.");
  }
  validateReceiptFileName(fileName, receiptStoragePath, fileType);
  const receiptUrl = serverReceiptReference(receiptStoragePath);
  const rawAllocations = request.data.allocations;
  if (!Array.isArray(rawAllocations) || rawAllocations.length < 1 || rawAllocations.length > 100) {
    throw new HttpsError("invalid-argument", "Receipt allocations are required.");
  }
  const payerMembership = await requireActiveMembership(organizationId, payerUserId);
  if (payerMembership.id !== payerMembershipId) throw new HttpsError("permission-denied", "Payer membership mismatch.");
  const profile = await userPublicProfile(payerUserId);
  const organization = db().collection("organizations").doc(organizationId);
  const transactionRef = organization.collection("transactions").doc(receiptId);
  const reviewerUserIds = await activeFinancialReviewerUserIds(organization);
  const seenCharges = new Set();
  const input = rawAllocations.map((item) => {
    const chargeId = requireString(item.chargeId, "chargeId", 128);
    if (seenCharges.has(chargeId)) throw new HttpsError("invalid-argument", "A charge cannot be allocated twice.");
    seenCharges.add(chargeId);
    return {
      chargeId,
      beneficiaryMembershipId: requireString(item.beneficiaryMembershipId, "beneficiaryMembershipId", 128),
      amountAllocatedBaisa: requireBaisa(item.amountAllocatedBaisa, "amountAllocatedBaisa"),
      balanceBeforeBaisa: requireBaisa(item.balanceBeforeBaisa, "balanceBeforeBaisa"),
    };
  });
  const allocationTotalBaisa = input.reduce((sum, item) => sum + item.amountAllocatedBaisa, 0);
  if (allocationTotalBaisa !== amountDeclaredBaisa) throw new HttpsError("failed-precondition", "Declared amount must equal allocation total.");

  const submission = await db().runTransaction(async (transaction) => {
    const existingReceipt = await transaction.get(transactionRef);
    if (existingReceipt.exists) {
      if (existingReceipt.get("payerUserId") !== payerUserId || existingReceipt.get("receiptStoragePath") !== receiptStoragePath) {
        throw new HttpsError("already-exists", "Receipt identifier is already in use.");
      }
      return { alreadyExists: true, allocations: existingReceipt.get("allocations") || [] };
    }
    const chargeRefs = input.map((item) => organization.collection("charges").doc(item.chargeId));
    const chargeDocs = await Promise.all(chargeRefs.map((reference) => transaction.get(reference)));
    const membershipIds = [...new Set(input.map((item) => item.beneficiaryMembershipId))];
    const memberRefs = membershipIds.map((id) => organization.collection("memberships").doc(id));
    const memberDocs = await Promise.all(memberRefs.map((reference) => transaction.get(reference)));
    if (memberDocs.some((doc) => !doc.exists || doc.get("status") !== "active")) {
      throw new HttpsError("failed-precondition", "All beneficiaries must be active council members.");
    }
    const memberMap = new Map(memberDocs.map((doc) => [doc.id, doc.data()]));
    const directoryDocs = await Promise.all(membershipIds.map((id) => transaction.get(organization.collection("member_directory").doc(id))));
    const lockRefs = input.map((item) => organization.collection("pending_receipt_locks").doc(`${payerUserId}_${item.chargeId}`));
    const lockDocs = await Promise.all(lockRefs.map((reference) => transaction.get(reference)));
    const rateRef = organization.collection("financial_rate_limits").doc(payerUserId);
    const rateDoc = await transaction.get(rateRef);
    const nowDate = new Date();
    const hourStart = new Date(nowDate.getTime() - 60 * 60 * 1000);
    const currentWindow = rateDoc.exists && rateDoc.get("windowStartedAt") && rateDoc.get("windowStartedAt").toDate() > hourStart;
    const currentCount = currentWindow ? Number(rateDoc.get("count") || 0) : 0;
    if (currentCount >= 10) throw new HttpsError("resource-exhausted", "Receipt submission limit reached. Try again later.");
    lockDocs.forEach((lock) => {
      if (lock.exists && lock.get("expiresAt") && lock.get("expiresAt").toDate() > nowDate) {
        throw new HttpsError("already-exists", "You already have a pending receipt for this charge.");
      }
    });
    const directoryMap = new Map(directoryDocs.map((doc) => [doc.id, doc.exists ? doc.data() : {}]));
    const verified = chargeDocs.map((charge, index) => {
      if (!charge.exists) throw new HttpsError("not-found", "A selected charge no longer exists.");
      const data = charge.data();
      const selected = input[index];
      if (data.organizationId !== organizationId || data.membershipId !== selected.beneficiaryMembershipId) {
        throw new HttpsError("permission-denied", "Charge council or beneficiary mismatch.");
      }
      if (!["unpaid", "partial", "overdue", "rejected"].includes(data.status)) {
        throw new HttpsError("failed-precondition", "A charge is no longer payable.");
      }
      if (!Number.isSafeInteger(data.balanceBaisa) || data.balanceBaisa !== selected.balanceBeforeBaisa || selected.amountAllocatedBaisa > data.balanceBaisa) {
        throw new HttpsError("failed-precondition", "A charge balance changed or was overpaid.");
      }
      const beneficiary = memberMap.get(selected.beneficiaryMembershipId);
      const directory = directoryMap.get(selected.beneficiaryMembershipId);
      return {
        beneficiaryUserId: beneficiary.userId,
        beneficiaryMembershipId: selected.beneficiaryMembershipId,
        beneficiaryName: String(directory.fullName || "عضو المجلس"),
        chargeId: charge.id,
        chargeTitle: String(data.titleArabic || "رسم"),
        amountAllocatedBaisa: selected.amountAllocatedBaisa,
        balanceBeforeBaisa: data.balanceBaisa,
        statusBefore: data.status,
      };
    });
    const includesSelf = verified.some((item) => item.beneficiaryMembershipId === payerMembershipId);
    const includesOthers = verified.some((item) => item.beneficiaryMembershipId !== payerMembershipId);
    if ((paymentScope === "self" && (!includesSelf || includesOthers)) ||
        (paymentScope === "others" && (includesSelf || !includesOthers)) ||
        (paymentScope === "mixed" && (!includesSelf || !includesOthers))) {
      throw new HttpsError("invalid-argument", "Payment scope does not match beneficiaries.");
    }
    const now = timestamp();
    const expiresAt = Timestamp.fromMillis(now.toMillis() + 48 * 60 * 60 * 1000);
    lockRefs.forEach((reference, index) => transaction.set(reference, {
      payerUserId,
      chargeId: input[index].chargeId,
      transactionId: transactionRef.id,
      expiresAt,
      createdAt: now,
    }));
    transaction.set(rateRef, {
      userId: payerUserId,
      windowStartedAt: currentWindow ? rateDoc.get("windowStartedAt") : now,
      count: currentCount + 1,
      updatedAt: now,
    });
    transaction.set(transactionRef, {
      transactionId: transactionRef.id,
      organizationId,
      payerUserId,
      payerMembershipId,
      payerName: profile.fullName || "عضو المجلس",
      payerMemberNumber: String(payerMembership.get("memberNumber") || ""),
      paymentScope,
      amountDeclaredBaisa,
      allocationTotalBaisa,
      differenceBaisa: 0,
      receiptUrl,
      receiptStoragePath,
      fileName,
      fileType,
      reviewStatus: "pending",
      status: "pendingReview",
      currentStatus: "submitted",
      submittedAt: now,
      expiresAt,
      reviewedAt: null,
      reviewedBy: null,
      rejectionReason: null,
      allocations: verified,
      beneficiaryMembershipIds: [...new Set(verified.map((item) => item.beneficiaryMembershipId))],
      beneficiaryUserIds: [...new Set(verified.map((item) => item.beneficiaryUserId))],
      allocationChargeIds: verified.map((item) => item.chargeId),
      createdAt: now,
      updatedAt: now,
    });
    enqueueFinancialNotification(transaction, organization,
      notification(payerUserId, organizationId, `receiptReceived_${transactionRef.id}`, "تم إرسال الإيصال",
        `إيصال التحويل بقيمة ${formatOmaniRialForSystemNotification(amountDeclaredBaisa)} قيد مراجعة المسؤول المالي.`,
        "receiptReceived", transactionRef.id, payerUserId, "receipt", {
          amountBaisa: amountDeclaredBaisa,
          currencyCode: "OMR",
          bodyTemplate: "إيصال التحويل بقيمة {amount} قيد مراجعة المسؤول المالي.",
        }));
    reviewerUserIds.forEach((reviewerId) => enqueueFinancialNotification(transaction, organization,
      notification(reviewerId, organizationId, `receiptSubmitted_${transactionRef.id}`, "إيصال جديد للمراجعة",
        `أرسل ${profile.fullName || "عضو"} إيصالًا بقيمة ${formatOmaniRialForSystemNotification(amountDeclaredBaisa)}.`,
        "receiptSubmitted", transactionRef.id, payerUserId, "receipt", {
          amountBaisa: amountDeclaredBaisa,
          currencyCode: "OMR",
          bodyTemplate: `أرسل ${profile.fullName || "عضو"} إيصالًا بقيمة {amount}.`,
        })));
    return { alreadyExists: false, allocations: verified };
  });

  if (submission.alreadyExists) {
    return { transactionId: transactionRef.id, allocations: submission.allocations.length, idempotent: true };
  }

  return { transactionId: transactionRef.id, allocations: submission.allocations.length, idempotent: false };
}
exports.submitFinancialReceipt = onCall(sensitiveCallableOptions, submitFinancialReceiptHandler);

async function reviewFinancialReceiptHandler(request) {
  const reviewerId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const transactionId = requireString(request.data.transactionId, "transactionId", 128);
  const decision = requireString(request.data.decision, "decision", 20);
  if (!["approve", "reject"].includes(decision)) throw new HttpsError("invalid-argument", "Invalid review decision.");
  const rejectionReason = decision === "reject" ? requireString(request.data.rejectionReason, "rejectionReason", 500) : null;
  await requireReviewer(organizationId, reviewerId);
  const organization = db().collection("organizations").doc(organizationId);
  const transactionRef = organization.collection("transactions").doc(transactionId);
  const result = await db().runTransaction(async (transaction) => {
    const receipt = await transaction.get(transactionRef);
    if (!receipt.exists) throw new HttpsError("not-found", "Receipt transaction not found.");
    const data = receipt.data();
    if (data.organizationId !== organizationId || data.reviewStatus !== "pending" || data.status !== "pendingReview") {
      throw new HttpsError("failed-precondition", "Receipt is no longer pending.");
    }
    if (!Number.isSafeInteger(data.amountDeclaredBaisa) || data.amountDeclaredBaisa !== data.allocationTotalBaisa || data.differenceBaisa !== 0) {
      throw new HttpsError("failed-precondition", "Receipt amounts do not match.");
    }
    const allocations = Array.isArray(data.allocations) ? data.allocations : [];
    if (!allocations.length) throw new HttpsError("failed-precondition", "Receipt has no allocations.");
    const chargeRefs = allocations.map((item) => organization.collection("charges").doc(item.chargeId));
    const charges = await Promise.all(chargeRefs.map((reference) => transaction.get(reference)));
    if (decision === "approve") {
      charges.forEach((charge, index) => {
        const allocation = allocations[index];
        if (!charge.exists) throw new HttpsError("failed-precondition", "An allocation charge is missing.");
        const chargeData = charge.data();
        const beneficiaryMatches = allocation.beneficiaryMembershipId == null
          ? chargeData.accountType === "guest" && chargeData.userId === allocation.beneficiaryUserId
          : chargeData.membershipId === allocation.beneficiaryMembershipId;
        if (chargeData.organizationId !== organizationId || !beneficiaryMatches) {
          throw new HttpsError("failed-precondition", "An allocation charge is invalid.");
        }
        if (!["unpaid", "partial", "overdue", "rejected"].includes(chargeData.status) ||
            chargeData.balanceBaisa !== allocation.balanceBeforeBaisa || allocation.amountAllocatedBaisa > chargeData.balanceBaisa) {
          throw new HttpsError("failed-precondition", "A charge balance changed after receipt submission.");
        }
      });
    }
    const now = timestamp();
    charges.forEach((charge, index) => {
      const allocation = allocations[index];
      const chargeData = charge.data();
      if (decision === "approve") {
        const amountPaidBaisa = chargeData.amountPaidBaisa + allocation.amountAllocatedBaisa;
        const balanceBaisa = chargeData.balanceBaisa - allocation.amountAllocatedBaisa;
        transaction.update(chargeRefs[index], {
          amountPaidBaisa,
          balanceBaisa,
          status: balanceBaisa === 0 ? "paid" : "partial",
          lastTransactionId: transactionId,
          lastPayerName: data.payerName,
          lastPayerUserId: data.payerUserId,
          updatedAt: now,
        });
      }
    });
    allocations.forEach((allocation) => {
      transaction.delete(organization.collection("pending_receipt_locks").doc(`${data.payerUserId}_${allocation.chargeId}`));
    });
    transaction.update(transactionRef, {
      reviewStatus: decision === "approve" ? "approved" : "rejected",
      status: decision === "approve" ? "approved" : "rejected",
      currentStatus: decision === "approve" ? "approved" : "rejected",
      reviewedAt: now,
      reviewedBy: reviewerId,
      rejectionReason,
      updatedAt: now,
      timeline: FieldValue.arrayUnion({
        status: decision === "approve" ? "approved" : "rejected",
        timestamp: now,
        adminName: reviewerId,
        note: rejectionReason,
      }),
    });
    const payerTitle = decision === "approve" ? "تم اعتماد الإيصال" : "تم رفض الإيصال";
    const payerBody = decision === "approve"
      ? "تم توزيع المبلغ على الرسوم المحددة بنجاح."
      : `سبب الرفض: ${rejectionReason}`;
    enqueueFinancialNotification(transaction, organization,
      notification(data.payerUserId, organizationId, `receipt_${decision}_${transactionId}`,
        payerTitle, payerBody, decision === "approve" ? "receiptApproved" : "receiptRejected",
        transactionId, reviewerId, "receipt", {
          amountBaisa: data.amountDeclaredBaisa,
          currencyCode: "OMR",
          bodyTemplate: decision === "approve"
            ? "تم اعتماد وتوزيع مبلغ {amount} على الرسوم المحددة بنجاح."
            : `رُفض إيصال بقيمة {amount}. سبب الرفض: ${rejectionReason}`,
        }));
    if (decision === "approve") {
      const beneficiaries = new Map();
      allocations.forEach((item) => {
        if (item.beneficiaryUserId !== data.payerUserId) {
          beneficiaries.set(
            item.beneficiaryUserId,
            (beneficiaries.get(item.beneficiaryUserId) || 0) + item.amountAllocatedBaisa
          );
        }
      });
      beneficiaries.forEach((amountBaisa, beneficiaryUserId) => enqueueFinancialNotification(transaction, organization,
        notification(beneficiaryUserId, organizationId, `paidForYou_${transactionId}`, "تم الدفع عنك",
          `تم اعتماد دفعة بقيمة ${formatOmaniRialForSystemNotification(amountBaisa)} عنك بواسطة: ${data.payerName}`,
          "paidForYou", transactionId, reviewerId, "receipt", {
            amountBaisa,
            currencyCode: "OMR",
            bodyTemplate: `تم اعتماد دفعة بقيمة {amount} عنك بواسطة: ${data.payerName}`,
          })));
    }
    return { payerUserId: data.payerUserId, payerName: data.payerName, allocations };
  });
  return { status: decision === "approve" ? "approved" : "rejected" };
}
exports.reviewFinancialReceipt = onCall(sensitiveCallableOptions, reviewFinancialReceiptHandler);

async function deliverFinancialNotificationOutboxHandler(event, options = {}) {
  const snapshot = event.data;
  if (!snapshot || !snapshot.exists) return { status: "missing" };
  const organization = snapshot.ref.parent.parent;
  if (!organization) throw new Error("Financial notification outbox is outside an organization.");
  const beforeCommit = options.beforeCommit;
  return db().runTransaction(async (transaction) => {
    const current = await transaction.get(snapshot.ref);
    if (!current.exists) return { status: "missing" };
    if (current.get("status") === "delivered") return { status: "delivered", idempotent: true };
    const data = current.data();
    const payload = data.payload;
    if (data.organizationId !== organization.id || typeof data.userId !== "string" ||
        typeof data.notificationId !== "string" || !payload ||
        payload.deliverySource !== "server" ||
        payload.userId !== data.userId || payload.notificationId !== data.notificationId ||
        payload.organizationId !== organization.id) {
      throw new Error("Financial notification outbox payload is invalid.");
    }
    const target = db().collection("users").doc(data.userId)
      .collection("notifications").doc(data.notificationId);
    const existingNotification = await transaction.get(target);
    if (typeof beforeCommit === "function") await beforeCommit({ current, existingNotification, target });
    if (!existingNotification.exists) transaction.set(target, payload);
    transaction.update(snapshot.ref, {
      status: "delivered",
      deliveredAt: timestamp(),
      updatedAt: timestamp(),
      attemptCount: Number(data.attemptCount || 0) + 1,
    });
    return { status: "delivered", idempotent: existingNotification.exists };
  });
}

exports.deliverFinancialNotificationOutbox = onDocumentCreated(
  {
    document: "organizations/{organizationId}/financial_notification_outbox/{outboxId}",
    region: "us-central1",
    retry: true,
  },
  deliverFinancialNotificationOutboxHandler
);

async function createFinancialReceiptDownloadUrl(storagePath) {
  const [url] = await admin.storage().bucket().file(storagePath).getSignedUrl({
    action: "read",
    expires: Date.now() + 5 * 60 * 1000,
  });
  return url;
}

function receiptDownloadRuntime(environment = process.env) {
  if (environment.FUNCTIONS_EMULATOR !== "true") return "production";
  const projectId = environment.GCLOUD_PROJECT || environment.GOOGLE_CLOUD_PROJECT;
  if (projectId !== approvedReceiptEmulatorProjectId) {
    throw new HttpsError(
      "failed-precondition",
      `Receipt Emulator access is restricted to ${approvedReceiptEmulatorProjectId}.`
    );
  }
  return "emulator";
}

function validateReceiptFileName(fileName, storagePath, contentType) {
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$/.test(fileName) ||
      storagePath.split("/").at(-1) !== fileName) {
    throw new HttpsError("failed-precondition", "Receipt file name is invalid.");
  }
  const expectedExtension = receiptContentTypes.get(contentType);
  if (!expectedExtension) {
    throw new HttpsError("failed-precondition", "Receipt content type is not allowed.");
  }
  const lowerName = fileName.toLowerCase();
  const extensionMatches = contentType === "image/jpeg"
    ? lowerName.endsWith(".jpg") || lowerName.endsWith(".jpeg")
    : Boolean(expectedExtension && lowerName.endsWith(expectedExtension));
  if (!extensionMatches) {
    throw new HttpsError("failed-precondition", "Receipt file extension does not match its content type.");
  }
}

function receiptBytesMatchContentType(bytes, contentType) {
  if (contentType === "application/pdf") return bytes.subarray(0, 5).toString("ascii") === "%PDF-";
  if (contentType === "image/jpeg") return bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  if (contentType === "image/png") {
    return bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  }
  if (contentType === "image/webp") {
    return bytes.length >= 12 && bytes.subarray(0, 4).toString("ascii") === "RIFF" &&
      bytes.subarray(8, 12).toString("ascii") === "WEBP";
  }
  return false;
}

async function readFinancialReceiptFromEmulator(storagePath, expectedFileName, expectedContentType, options = {}) {
  if (!receiptContentTypes.has(expectedContentType)) {
    throw new HttpsError("failed-precondition", "Receipt content type is not allowed.");
  }
  validateReceiptFileName(expectedFileName, storagePath, expectedContentType);
  const file = (options.bucket || admin.storage().bucket()).file(storagePath);
  let metadata;
  try {
    [metadata] = await file.getMetadata();
  } catch (error) {
    if (error && (error.code === 404 || error.code === "storage/object-not-found")) {
      throw new HttpsError("not-found", "Receipt file not found.");
    }
    throw error;
  }
  const sizeBytes = Number(metadata.size);
  const contentType = String(metadata.contentType || "").toLowerCase();
  if (!Number.isSafeInteger(sizeBytes) || sizeBytes <= 0 || sizeBytes > receiptDownloadMaxBytes) {
    throw new HttpsError("failed-precondition", "Receipt file size is invalid.");
  }
  if (!receiptContentTypes.has(contentType) || contentType !== expectedContentType) {
    throw new HttpsError("failed-precondition", "Receipt content type does not match the transaction.");
  }
  const [bytes] = await file.download();
  if (bytes.length !== sizeBytes || bytes.length > receiptDownloadMaxBytes ||
      !receiptBytesMatchContentType(bytes, contentType)) {
    throw new HttpsError("failed-precondition", "Receipt file content is invalid.");
  }
  return { bytesBase64: bytes.toString("base64"), sizeBytes, contentType, fileName: expectedFileName };
}

async function getFinancialReceiptDownloadUrlHandler(request, options = {}) {
  const requesterUserId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const transactionId = requireString(request.data.transactionId, "transactionId", 128);
  const receipt = await db().collection("organizations").doc(organizationId)
    .collection("transactions").doc(transactionId).get();
  if (!receipt.exists || receipt.get("organizationId") !== organizationId) {
    throw new HttpsError("not-found", "Receipt transaction not found.");
  }
  if (receipt.get("payerUserId") !== requesterUserId) {
    await requireReviewer(organizationId, requesterUserId);
  }
  const storagePath = requireString(receipt.get("receiptStoragePath"), "receiptStoragePath", 1024);
  const identity = receiptStorageIdentity(storagePath);
  if (!identity || identity.organizationId !== organizationId || identity.receiptId !== transactionId ||
      identity.userId !== receipt.get("payerUserId")) {
    throw new HttpsError("failed-precondition", "Receipt storage identity is invalid.");
  }
  const fileName = requireString(receipt.get("fileName"), "fileName", 255);
  const contentType = requireString(receipt.get("fileType"), "fileType", 100).toLowerCase();
  const runtime = receiptDownloadRuntime(options.environment || process.env);
  if (runtime === "emulator") {
    const readReceiptFile = options.readReceiptFile || readFinancialReceiptFromEmulator;
    return {
      kind: "bytes",
      ...(await readReceiptFile(storagePath, fileName, contentType, options)),
    };
  }
  const createDownloadUrl = options.createDownloadUrl || createFinancialReceiptDownloadUrl;
  return {
    kind: "url",
    url: await createDownloadUrl(storagePath),
    expiresInSeconds: 300,
    fileName,
    contentType,
  };
}

exports.getFinancialReceiptDownloadUrl = onCall(
  sensitiveCallableOptions,
  getFinancialReceiptDownloadUrlHandler
);

async function receiptIsLinked(identity, storagePath, database = db()) {
  const organization = database.collection("organizations").doc(identity.organizationId);
  const direct = await organization.collection("transactions").doc(identity.receiptId).get();
  if (direct.exists && direct.get("receiptStoragePath") === storagePath) return true;
  const query = await organization.collection("transactions")
    .where("receiptStoragePath", "==", storagePath).limit(1).get();
  return !query.empty;
}

function receiptSweepAgeHours() {
  const configured = Number(process.env.FINANCIAL_RECEIPT_ORPHAN_HOURS || 48);
  return Number.isFinite(configured) && configured >= 24 && configured <= 720 ? configured : 48;
}

async function cleanupOrphanReceiptsHandler(event, options = {}) {
  const database = options.database || db();
  const bucket = options.bucket || admin.storage().bucket();
  const nowDate = options.nowDate || new Date();
  const minimumAgeHours = options.minimumAgeHours || receiptSweepAgeHours();
  const pageSize = options.pageSize || 100;
  const log = options.log || console;
  const gate = scheduleGate("cleanupOrphanFinancialReceipts", event, options);
  if (!gate.execute) {
    logScheduleResult(log, gate.result);
    return gate.result;
  }
  const isLinked = options.isLinked || ((identity, path) => receiptIsLinked(identity, path, database));
  const stats = {
    scanned: 0,
    temporary: 0,
    deleted: 0,
    linked: 0,
    recent: 0,
    reviewRequired: 0,
    firestoreErrors: 0,
    deleteErrors: 0,
  };
  let pageToken;
  const seenTokens = new Set();
  do {
    const [files, nextQuery] = await bucket.getFiles({
      prefix: "organizations/",
      autoPaginate: false,
      maxResults: pageSize,
      ...(pageToken ? { pageToken } : {}),
    });
    for (const file of files) {
      stats.scanned += 1;
      const identity = receiptStorageIdentity(file.name);
      if (!identity) continue;
      let metadata;
      try {
        [metadata] = await file.getMetadata();
      } catch (_error) {
        stats.reviewRequired += 1;
        continue;
      }
      const custom = metadata.metadata || {};
      if (String(custom.temporaryUpload || "") !== "true") {
        stats.reviewRequired += 1;
        continue;
      }
      stats.temporary += 1;
      const uploadedAt = new Date(String(custom.uploadedAt || ""));
      const serverCreatedAt = new Date(String(metadata.timeCreated || ""));
      const metadataValid = custom.receiptId === identity.receiptId &&
        custom.uploaderUid === identity.userId && custom.organizationId === identity.organizationId &&
        Number.isFinite(uploadedAt.valueOf()) && Number.isFinite(serverCreatedAt.valueOf());
      if (!metadataValid) {
        stats.reviewRequired += 1;
        continue;
      }
      const minimumAgeMs = minimumAgeHours * 60 * 60 * 1000;
      if (nowDate.getTime() - uploadedAt.getTime() < minimumAgeMs ||
          nowDate.getTime() - serverCreatedAt.getTime() < minimumAgeMs) {
        stats.recent += 1;
        continue;
      }
      let linked;
      try {
        linked = await isLinked(identity, file.name);
      } catch (_error) {
        stats.firestoreErrors += 1;
        continue;
      }
      if (linked) {
        stats.linked += 1;
        continue;
      }
      try {
        await file.delete({ ignoreNotFound: true });
        stats.deleted += 1;
      } catch (_error) {
        stats.deleteErrors += 1;
      }
    }
    const nextToken = nextQuery && nextQuery.pageToken;
    if (nextToken && seenTokens.has(nextToken)) throw new Error("Storage pagination returned a repeated page token.");
    if (nextToken) seenTokens.add(nextToken);
    pageToken = nextToken;
  } while (pageToken);
  const result = { status: "completed", task: "cleanupOrphanFinancialReceipts", runId: gate.runId, ...stats };
  logScheduleResult(log, result);
  return result;
}

exports.cleanupOrphanFinancialReceipts = onSchedule(
  {
    schedule: "every day 03:15", timeZone: "Asia/Muscat", region: "us-central1",
    timeoutSeconds: 540, memory: "512MiB", maxInstances: 1,
  },
  cleanupOrphanReceiptsHandler
);

exports.cleanupOrphanReceipt = onCall(sensitiveCallableOptions, async (request) => {
  const userId = requireAuth(request);
  const storagePath = requireString(request.data.receiptStoragePath, "receiptStoragePath", 1024);
  const identity = receiptStorageIdentity(storagePath);
  if (!identity || identity.userId !== userId) throw new HttpsError("permission-denied", "Receipt path ownership mismatch.");
  await requireActiveMembership(identity.organizationId, userId);
  if (await receiptIsLinked(identity, storagePath)) return { status: "linked" };
  const file = admin.storage().bucket().file(storagePath);
  const [metadata] = await file.getMetadata().catch((error) => {
    if (error.code === 404) return [{ timeCreated: null }];
    throw error;
  });
  if (!metadata.timeCreated) return { status: "missing" };
  if (Date.now() - new Date(metadata.timeCreated).getTime() < 15 * 60 * 1000) {
    return { status: "grace-period" };
  }
  if (await receiptIsLinked(identity, storagePath)) return { status: "linked" };
  await file.delete({ ignoreNotFound: true });
  return { status: "deleted" };
});

async function expirePendingFinancialReceiptsHandler(event, options = {}) {
  const database = options.database || db();
  const log = options.log || console;
  const gate = scheduleGate("expirePendingFinancialReceipts", event, options);
  if (!gate.execute) {
    logScheduleResult(log, gate.result);
    return gate.result;
  }
  const now = options.now || timestamp();
  const stats = await processPaginated({
    pageSize: options.pageSize || 200,
    concurrency: options.concurrency || 10,
    fetchPage: async ({ cursor, pageSize }) => {
      let query = database.collectionGroup("transactions")
        .where("reviewStatus", "==", "pending")
        .where("expiresAt", "<", now)
        .orderBy("expiresAt")
        .orderBy(FieldPath.documentId())
        .limit(pageSize);
      if (cursor) query = query.startAfter(cursor);
      const snapshot = await query.get();
      return { items: snapshot.docs, nextCursor: snapshot.size === pageSize ? snapshot.docs.at(-1) : null };
    },
    processItem: async (doc) => {
      const data = doc.data();
      const organization = doc.ref.parent.parent;
      if (!organization) return "invalid";
      await database.runTransaction(async (transaction) => {
        const current = await transaction.get(doc.ref);
        if (!current.exists || current.get("reviewStatus") !== "pending" ||
            current.get("expiresAt").toMillis() > now.toMillis()) return;
        transaction.update(doc.ref, {
          reviewStatus: "expired", status: "expired", currentStatus: "expired",
          updatedAt: now, expiredAt: now,
        });
        for (const chargeId of data.allocationChargeIds || []) {
          transaction.delete(organization.collection("pending_receipt_locks")
            .doc(`${data.payerUserId}_${chargeId}`));
        }
      });
      return "expired";
    },
  });
  const result = { status: "completed", task: "expirePendingFinancialReceipts", runId: gate.runId, ...stats };
  logScheduleResult(log, result);
  return result;
}

exports.expirePendingFinancialReceipts = onSchedule(
  {
    schedule: "every 60 minutes", timeZone: "Asia/Muscat", region: "us-central1",
    timeoutSeconds: 540, memory: "512MiB", maxInstances: 1,
  },
  expirePendingFinancialReceiptsHandler
);

exports._test = {
  bookingFinancialLifecycleHandler,
  cleanupOrphanReceiptsHandler,
  deliverFinancialNotificationOutboxHandler,
  ensureSubscriptionCharge,
  expirePendingFinancialReceiptsHandler,
  generateSubscriptionChargesHandler,
  getBookingAvailabilityHandler,
  getFinancialReceiptDownloadUrlHandler,
  getGuestBookingChargeHandler,
  getPayableChargesHandler,
  listFinancialMembersHandler,
  markFinancialChargesOverdueHandler,
  scheduleGate,
  notification,
  receiptIsLinked,
  receiptBytesMatchContentType,
  receiptDownloadRuntime,
  readFinancialReceiptFromEmulator,
  requireBaisa,
  requireNonNegativeBaisa,
  requestBookingCancellationHandler,
  reviewFinancialReceiptHandler,
  reviewBookingCancellationHandler,
  searchCouncilMembersHandler,
  financialRateLimitId,
  serverReceiptReference,
  submitGuestBookingReceiptHandler,
  submitFinancialReceiptHandler,
};
