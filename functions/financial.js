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

const db = () => admin.firestore();
const timestamp = () => Timestamp.now();
const payableChargePageSize = 50;
const payableChargeTokenVersion = 1;
const financialNotificationOutbox = "financial_notification_outbox";

async function membershipForUser(organizationId, userId) {
  const organization = db().collection("organizations").doc(organizationId);
  const direct = await organization.collection("memberships").doc(userId).get();
  if (direct.exists && direct.get("userId") === userId) return direct;
  const query = await organization.collection("memberships").where("userId", "==", userId).limit(1).get();
  return query.empty ? null : query.docs[0];
}

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
    throw new HttpsError("invalid-argument", `${name} must be a positive integer in baisa.`);
  }
  return value;
}

function requireNonNegativeBaisa(value, name) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new HttpsError("invalid-argument", `${name} must be a non-negative integer in baisa.`);
  }
  return value;
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

function notification(userId, organizationId, id, title, body, type, transactionId, actorId, relatedEntityType = "receipt") {
  return {
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
  };
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
    const now = timestamp();
    if (status === "pending") {
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
exports.requestBookingCancellation = onCall({ region: "us-central1" }, requestBookingCancellationHandler);

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
    const charge = chargeRef ? await transaction.get(chargeRef) : null;
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
exports.reviewBookingCancellation = onCall({ region: "us-central1" }, reviewBookingCancellationHandler);

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
  const snapshot = await organization.collection("bookings")
    .where("bookingDate", ">=", Timestamp.fromDate(start))
    .where("bookingDate", "<", Timestamp.fromDate(end))
    .where("status", "in", ["pending", "approved", "cancellationRequested"])
    .limit(100).get();
  return {
    days: snapshot.docs.map((doc) => ({
      date: doc.get("bookingDate").toDate().toISOString(),
      status: doc.get("status") === "approved" || doc.get("status") === "cancellationRequested" ? "approved" : "pending",
    })),
  };
}
exports.getBookingAvailability = onCall({ region: "us-central1" }, getBookingAvailabilityHandler);

async function generateSubscriptionChargesHandler(_event, options = {}) {
  const database = options.database || db();
  const nowDate = options.nowDate || new Date();
  const processAccount = options.processAccount ||
    ((snapshot) => ensureSubscriptionCharge(snapshot, { nowDate }));
  const log = options.log || console;
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
  log.info ? log.info("Daily subscription charge generation", stats) : log.log("Daily subscription charge generation", stats);
  return stats;
}

exports.generateSubscriptionChargesDaily = onSchedule(
  {
    schedule: "every day 02:00", timeZone: "Asia/Muscat", region: "us-central1",
    timeoutSeconds: 540, memory: "512MiB", maxInstances: 1,
  },
  generateSubscriptionChargesHandler
);

async function markFinancialChargesOverdueHandler(_event, options = {}) {
  const database = options.database || db();
  const nowDate = options.nowDate || new Date();
  const log = options.log || console;
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
  log.info ? log.info("Financial overdue scan", stats) : log.log("Financial overdue scan", stats);
  return stats;
}

exports.markFinancialChargesOverdue = onSchedule(
  {
    schedule: "every day 02:30", timeZone: "Asia/Muscat", region: "us-central1",
    timeoutSeconds: 540, memory: "512MiB", maxInstances: 1,
  },
  markFinancialChargesOverdueHandler
);

exports.updateFinancialSettings = onCall({ region: "us-central1" }, async (request) => {
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

exports.saveFinancialPlan = onCall({ region: "us-central1" }, async (request) => {
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

exports.updateMemberFinancialAccount = onCall({ region: "us-central1" }, async (request) => {
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

exports.createManualFinancialCharge = onCall({ region: "us-central1" }, async (request) => {
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
  const snapshot = await db().collection("organizations").doc(organizationId)
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
exports.searchCouncilMembers = onCall({ region: "us-central1" }, searchCouncilMembersHandler);

exports.listFinancialMembers = onCall({ region: "us-central1" }, async (request) => {
  const userId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  await requireReviewer(organizationId, userId);
  const snapshot = await db().collection("organizations").doc(organizationId)
    .collection("member_directory").where("active", "==", true)
    .orderBy("fullName").limit(50).get();
  return {
    members: snapshot.docs.map((doc) => {
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
});

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
  const hasMore = uniqueMembershipIds.some((membershipId) => nextCursors[membershipId] !== null);
  return {
    charges,
    nextPageToken: hasMore
      ? encodePayableChargePageToken(organizationId, uniqueMembershipIds, nextCursors)
      : null,
  };
}
exports.getPayableCharges = onCall({ region: "us-central1" }, getPayableChargesHandler);

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
exports.getGuestBookingCharge = onCall({ region: "us-central1" }, getGuestBookingChargeHandler);

async function submitGuestBookingReceiptHandler(request) {
  const payerUserId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const bookingId = requireString(request.data.bookingId, "bookingId", 128);
  const chargeId = requireString(request.data.chargeId, "chargeId", 128);
  const receiptId = requireString(request.data.receiptId, "receiptId", 128);
  const amountDeclaredBaisa = requireBaisa(request.data.amountDeclaredBaisa, "amountDeclaredBaisa");
  const balanceBeforeBaisa = requireBaisa(request.data.balanceBeforeBaisa, "balanceBeforeBaisa");
  const receiptUrl = requireString(request.data.receiptUrl, "receiptUrl", 2048);
  const receiptStoragePath = requireString(request.data.receiptStoragePath, "receiptStoragePath", 1024);
  const fileName = requireString(request.data.fileName, "fileName", 255);
  const fileType = requireString(request.data.fileType, "fileType", 100);
  const identity = receiptStorageIdentity(receiptStoragePath);
  if (!identity || identity.organizationId !== organizationId || identity.userId !== payerUserId || identity.receiptId !== receiptId) {
    throw new HttpsError("permission-denied", "Receipt path ownership mismatch.");
  }
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
        "إيصال الحجز قيد المراجعة.", "receiptReceived", receiptId, payerUserId));
    reviewerUserIds.forEach((reviewerId) => enqueueFinancialNotification(transaction, organization,
      notification(reviewerId, organizationId, `receiptSubmitted_${receiptId}`, "إيصال حجز للمراجعة",
        "يوجد إيصال حجز جديد للمراجعة.", "receiptSubmitted", receiptId, payerUserId)));
    return { idempotent: false };
  });
  return { transactionId: receiptId, idempotent: result.idempotent };
}
exports.submitGuestBookingReceipt = onCall({ region: "us-central1" }, submitGuestBookingReceiptHandler);

async function submitFinancialReceiptHandler(request) {
  const payerUserId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const payerMembershipId = requireString(request.data.payerMembershipId, "payerMembershipId", 128);
  const paymentScope = requireString(request.data.paymentScope, "paymentScope", 20);
  if (!["self", "others", "mixed"].includes(paymentScope)) throw new HttpsError("invalid-argument", "Invalid payment scope.");
  const amountDeclaredBaisa = requireBaisa(request.data.amountDeclaredBaisa, "amountDeclaredBaisa");
  const receiptUrl = requireString(request.data.receiptUrl, "receiptUrl", 2048);
  const receiptStoragePath = requireString(request.data.receiptStoragePath, "receiptStoragePath", 1024);
  const fileName = requireString(request.data.fileName, "fileName", 255);
  const fileType = requireString(request.data.fileType, "fileType", 100);
  const receiptId = requireString(request.data.receiptId, "receiptId", 128);
  const storageIdentity = receiptStorageIdentity(receiptStoragePath);
  if (!storageIdentity || storageIdentity.organizationId !== organizationId ||
      storageIdentity.userId !== payerUserId || storageIdentity.receiptId !== receiptId) {
    throw new HttpsError("permission-denied", "Receipt storage path does not belong to the payer.");
  }
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
        "إيصال التحويل قيد مراجعة المسؤول المالي.", "receiptReceived", transactionRef.id, payerUserId));
    reviewerUserIds.forEach((reviewerId) => enqueueFinancialNotification(transaction, organization,
      notification(reviewerId, organizationId, `receiptSubmitted_${transactionRef.id}`, "إيصال جديد للمراجعة",
        `أرسل ${profile.fullName || "عضو"} إيصالًا بقيمة ${amountDeclaredBaisa} بيسة.`,
        "receiptSubmitted", transactionRef.id, payerUserId)));
    return { alreadyExists: false, allocations: verified };
  });

  if (submission.alreadyExists) {
    return { transactionId: transactionRef.id, allocations: submission.allocations.length, idempotent: true };
  }

  return { transactionId: transactionRef.id, allocations: submission.allocations.length, idempotent: false };
}
exports.submitFinancialReceipt = onCall({ region: "us-central1" }, submitFinancialReceiptHandler);

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
        transactionId, reviewerId));
    if (decision === "approve") {
      const beneficiaries = new Map();
      allocations.forEach((item) => {
        if (item.beneficiaryUserId !== data.payerUserId) {
          beneficiaries.set(item.beneficiaryUserId, item.beneficiaryName);
        }
      });
      beneficiaries.forEach((_, beneficiaryUserId) => enqueueFinancialNotification(transaction, organization,
        notification(beneficiaryUserId, organizationId, `paidForYou_${transactionId}`, "تم الدفع عنك",
          `تم اعتماد دفعة عنك بواسطة: ${data.payerName}`, "paidForYou", transactionId, reviewerId)));
    }
    return { payerUserId: data.payerUserId, payerName: data.payerName, allocations };
  });
  return { status: decision === "approve" ? "approved" : "rejected" };
}
exports.reviewFinancialReceipt = onCall({ region: "us-central1" }, reviewFinancialReceiptHandler);

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
  const createDownloadUrl = options.createDownloadUrl || createFinancialReceiptDownloadUrl;
  return {
    url: await createDownloadUrl(storagePath),
    expiresInSeconds: 300,
  };
}

exports.getFinancialReceiptDownloadUrl = onCall(
  { region: "us-central1" },
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

async function cleanupOrphanReceiptsHandler(_event, options = {}) {
  const database = options.database || db();
  const bucket = options.bucket || admin.storage().bucket();
  const nowDate = options.nowDate || new Date();
  const minimumAgeHours = options.minimumAgeHours || receiptSweepAgeHours();
  const pageSize = options.pageSize || 100;
  const log = options.log || console;
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
  log.info ? log.info("Temporary financial receipt cleanup", stats) : log.log("Temporary financial receipt cleanup", stats);
  return stats;
}

exports.cleanupOrphanFinancialReceipts = onSchedule(
  {
    schedule: "every day 03:15", timeZone: "Asia/Muscat", region: "us-central1",
    timeoutSeconds: 540, memory: "512MiB", maxInstances: 1,
  },
  cleanupOrphanReceiptsHandler
);

exports.cleanupOrphanReceipt = onCall({ region: "us-central1" }, async (request) => {
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

exports.expirePendingFinancialReceipts = onSchedule(
  {
    schedule: "every 60 minutes", timeZone: "Asia/Muscat", region: "us-central1",
    timeoutSeconds: 540, memory: "512MiB", maxInstances: 1,
  },
  async () => {
    const now = timestamp();
    const stats = await processPaginated({
      pageSize: 200,
      concurrency: 10,
      fetchPage: async ({ cursor, pageSize }) => {
        let query = db().collectionGroup("transactions")
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
        await db().runTransaction(async (transaction) => {
          const current = await transaction.get(doc.ref);
          if (!current.exists || current.get("reviewStatus") !== "pending" || current.get("expiresAt").toMillis() > now.toMillis()) return;
          transaction.update(doc.ref, {
            reviewStatus: "expired", status: "expired", currentStatus: "expired",
            updatedAt: now, expiredAt: now,
          });
          for (const chargeId of data.allocationChargeIds || []) {
            transaction.delete(organization.collection("pending_receipt_locks").doc(`${data.payerUserId}_${chargeId}`));
          }
        });
        return "expired";
      },
    });
    console.log("Pending receipt expiration", stats);
  }
);

exports._test = {
  bookingFinancialLifecycleHandler,
  cleanupOrphanReceiptsHandler,
  deliverFinancialNotificationOutboxHandler,
  ensureSubscriptionCharge,
  generateSubscriptionChargesHandler,
  getFinancialReceiptDownloadUrlHandler,
  getGuestBookingChargeHandler,
  getPayableChargesHandler,
  markFinancialChargesOverdueHandler,
  receiptIsLinked,
  requestBookingCancellationHandler,
  reviewFinancialReceiptHandler,
  reviewBookingCancellationHandler,
  searchCouncilMembersHandler,
  submitGuestBookingReceiptHandler,
  submitFinancialReceiptHandler,
};
