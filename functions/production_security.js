const crypto = require("node:crypto");
const admin = require("firebase-admin");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");

const REGION = "us-central1";
const sensitiveCallableOptions = { region: REGION, enforceAppCheck: true };
const db = () => admin.firestore();

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

function optionalString(value, max = 500) {
  if (value == null || value === "") return "";
  if (typeof value !== "string" || value.length > max) {
    throw new HttpsError("invalid-argument", "Text value is invalid.");
  }
  return value.trim();
}

async function membershipForUser(organizationId, userId, database = db()) {
  const organization = database.collection("organizations").doc(organizationId);
  const direct = await organization.collection("memberships").doc(userId).get();
  if (direct.exists && (direct.get("userId") || direct.id) === userId) return direct;
  const query = await organization.collection("memberships")
    .where("userId", "==", userId).limit(2).get();
  if (query.size > 1) {
    throw new HttpsError("failed-precondition", "Duplicate council memberships require review.");
  }
  return query.empty ? null : query.docs[0];
}

async function isPlatformSystemOwner(userId, database = db()) {
  const platform = await database.collection("platform_admins").doc(userId).get();
  if (!platform.exists || platform.get("status") !== "active") return false;
  return platform.get("role") === "system_owner" ||
    (platform.get("role") === "superAdmin" && platform.get("fullAccess") === true);
}

function isPrimaryCouncilOwner(data = {}) {
  return data.isPrimaryOwner === true ||
    ["owner", "council_owner", "system_owner"].includes(data.roleId) ||
    ["owner", "council_owner", "system_owner"].includes(data.role);
}

function canManageBookings(data = {}) {
  const permissions = Array.isArray(data.permissionsSnapshot) ? data.permissionsSnapshot : [];
  return ["owner", "council_owner", "chairman", "adminManager"].includes(data.roleId) ||
    ["owner", "council_owner", "chairman", "adminManager"].includes(data.role) ||
    permissions.some((permission) =>
      ["fullAccess", "bookings.manage", "bookings.approve"].includes(permission));
}

async function requireBookingManager(organizationId, userId, database = db()) {
  if (await isPlatformSystemOwner(userId, database)) return;
  const membership = await membershipForUser(organizationId, userId, database);
  if (!membership || membership.get("status") !== "active" ||
      !canManageBookings(membership.data())) {
    throw new HttpsError("permission-denied", "Booking management permission is required.");
  }
}

function serverNotification({
  userId, organizationId, notificationId, title, body, type,
  relatedEntityType, relatedEntityId, actorUserId,
}) {
  return {
    notificationId,
    userId,
    organizationId,
    title,
    body,
    type,
    relatedEntityType,
    relatedEntityId,
    status: "unread",
    readAt: null,
    createdAt: Timestamp.now(),
    createdByUserId: actorUserId || "server",
    deliverySource: "server",
  };
}

async function writeServerNotification(payload, database = db()) {
  if (!payload || payload.deliverySource !== "server" ||
      typeof payload.userId !== "string" || typeof payload.notificationId !== "string") {
    throw new Error("Trusted server notification payload is invalid.");
  }
  await database.collection("users").doc(payload.userId)
    .collection("notifications").doc(payload.notificationId)
    .set(payload, { merge: false });
}

async function bookingReviewerUserIds(organization, excludedUserId = "") {
  const memberships = await organization.collection("memberships")
    .where("status", "==", "active").get();
  return [...new Set(memberships.docs
    .filter((membership) => canManageBookings(membership.data()))
    .map((membership) => membership.get("userId") || membership.id)
    .filter((userId) => typeof userId === "string" && userId && userId !== excludedUserId))];
}

async function membershipReviewerUserIds(organization, excludedUserId = "") {
  const memberships = await organization.collection("memberships")
    .where("status", "==", "active").get();
  return [...new Set(memberships.docs.filter((membership) => {
    const data = membership.data();
    const permissions = Array.isArray(data.permissionsSnapshot) ? data.permissionsSnapshot : [];
    return isPrimaryCouncilOwner(data) || permissions.some((permission) => [
      "fullAccess", "members.approve", "members.manage",
      "membershipRequests.review", "membership_requests.review", "memberships.review",
    ].includes(permission));
  }).map((membership) => membership.get("userId") || membership.id)
    .filter((userId) => typeof userId === "string" && userId && userId !== excludedUserId))];
}

function parseBookingDay(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new HttpsError("invalid-argument", "bookingDate must use YYYY-MM-DD.");
  }
  const [year, month, day] = value.split("-").map(Number);
  const calendarCheck = new Date(Date.UTC(year, month - 1, day, 12));
  if (calendarCheck.getUTCFullYear() !== year ||
      calendarCheck.getUTCMonth() !== month - 1 ||
      calendarCheck.getUTCDate() !== day) {
    throw new HttpsError("invalid-argument", "bookingDate is invalid.");
  }
  const instant = new Date(Date.UTC(year, month - 1, day, -4));
  return { dayKey: value, timestamp: Timestamp.fromDate(instant) };
}

function normalizeTime(value) {
  if (value == null || value === "") return "";
  if (typeof value !== "string" || !/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(value)) {
    throw new HttpsError("invalid-argument", "Booking time is invalid.");
  }
  return value;
}

function bookingSlotIdentity({ resourceId = "council_hall", dayKey, startTime = "", endTime = "" }) {
  if ((startTime && !endTime) || (!startTime && endTime) ||
      (startTime && startTime >= endTime)) {
    throw new HttpsError("invalid-argument", "Booking time range is invalid.");
  }
  const raw = `${resourceId}|${dayKey}|${startTime || "full_day"}|${endTime || "full_day"}`;
  return {
    resourceId,
    slotKey: crypto.createHash("sha256").update(raw).digest("hex"),
  };
}

function bookingDayFromTimestamp(value) {
  const date = value && typeof value.toDate === "function" ? value.toDate() : null;
  if (!date || !Number.isFinite(date.valueOf())) {
    throw new HttpsError("failed-precondition", "Booking date is missing.");
  }
  const muscat = new Date(date.getTime() + 4 * 60 * 60 * 1000);
  return `${muscat.getUTCFullYear().toString().padStart(4, "0")}-` +
    `${(muscat.getUTCMonth() + 1).toString().padStart(2, "0")}-` +
    `${muscat.getUTCDate().toString().padStart(2, "0")}`;
}

async function assertNoLegacyBookingConflict({
  organization, bookingId, bookingDay, bookingDate, resourceId,
  startTime, endTime, includePending = true,
}) {
  const [byDay, byTimestamp] = await Promise.all([
    organization.collection("bookings").where("bookingDay", "==", bookingDay).get(),
    organization.collection("bookings").where("bookingDate", "==", bookingDate).get(),
  ]);
  const candidates = new Map();
  for (const snapshot of [byDay, byTimestamp]) {
    for (const document of snapshot.docs) candidates.set(document.id, document);
  }
  const blockingStatuses = includePending ?
    ["pending", "approved", "cancellationRequested"] :
    ["approved", "cancellationRequested"];
  const conflict = [...candidates.values()].some((document) => {
    if (document.id === bookingId || document.get("slotKey")) return false;
    return blockingStatuses.includes(document.get("status")) &&
      (document.get("resourceId") || "council_hall") === resourceId &&
      (document.get("startTime") || "") === startTime &&
      (document.get("endTime") || "") === endTime;
  });
  if (conflict) {
    throw new HttpsError("already-exists", "The requested booking slot is unavailable.");
  }
}

async function createBookingHandler(request, options = {}) {
  const database = options.database || db();
  const userId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const bookingId = requireString(request.data.bookingId, "bookingId", 128);
  if (!/^[A-Za-z0-9_-]+$/.test(bookingId)) {
    throw new HttpsError("invalid-argument", "bookingId is invalid.");
  }
  const membershipId = optionalString(request.data.membershipId, 128);
  const requesterName = requireString(request.data.requesterName, "requesterName", 160);
  const requesterPhone = requireString(request.data.requesterPhone, "requesterPhone", 40);
  const occasionType = requireString(request.data.occasionType, "occasionType", 120);
  const notes = optionalString(request.data.notes, 1000);
  const startTime = normalizeTime(request.data.startTime);
  const endTime = normalizeTime(request.data.endTime);
  const { dayKey, timestamp: bookingDate } = parseBookingDay(request.data.bookingDate);
  const { resourceId, slotKey } = bookingSlotIdentity({ dayKey, startTime, endTime });
  const organization = database.collection("organizations").doc(organizationId);
  const [membership, settings] = await Promise.all([
    membershipForUser(organizationId, userId, database),
    organization.collection("settings").doc("organization").get(),
  ]);
  if (membershipId) {
    if (!membership || membership.id !== membershipId || membership.get("status") !== "active") {
      throw new HttpsError("permission-denied", "Active council membership is required.");
    }
  } else if (!settings.exists || settings.get("allowHallRental") !== true) {
    throw new HttpsError("permission-denied", "Guest booking is not enabled for this council.");
  }

  const bookingRef = organization.collection("bookings").doc(bookingId);
  const slotRef = organization.collection("booking_slots").doc(slotKey);
  await assertNoLegacyBookingConflict({
    organization, bookingId, bookingDay: dayKey, bookingDate,
    resourceId, startTime, endTime,
  });
  const result = await database.runTransaction(async (transaction) => {
    const [existingBooking, existingSlot] = await Promise.all([
      transaction.get(bookingRef), transaction.get(slotRef),
    ]);
    if (existingBooking.exists) {
      if (existingBooking.get("userId") === userId && existingBooking.get("slotKey") === slotKey) {
        return { idempotent: true };
      }
      throw new HttpsError("already-exists", "Booking request already exists.");
    }
    if (existingSlot.exists && existingSlot.get("bookingId") !== bookingId &&
        ["pending", "approved", "cancellationRequested"].includes(existingSlot.get("status"))) {
      throw new HttpsError("already-exists", "The requested booking slot is unavailable.");
    }
    const now = Timestamp.now();
    transaction.set(bookingRef, {
      bookingId, organizationId, userId,
      ...(membershipId ? { membershipId } : {}),
      requesterName, requesterPhone, bookingDate, bookingDay: dayKey,
      resourceId, slotKey,
      ...(startTime ? { startTime, endTime } : {}),
      occasionType, notes, status: "pending", createdAt: now, updatedAt: now,
      createdVia: "createBookingCallable",
    });
    transaction.set(slotRef, {
      organizationId, bookingId, userId, resourceId, slotKey,
      bookingDate, bookingDay: dayKey, startTime: startTime || null,
      endTime: endTime || null, status: "pending", createdAt: now, updatedAt: now,
    });
    return { idempotent: false };
  });

  if (!result.idempotent) {
    await writeServerNotification(serverNotification({
      userId, organizationId, notificationId: `bookingReceived_${bookingId}`,
      title: "تم إرسال طلب الحجز", body: "طلب حجز المجلس قيد المراجعة.",
      type: "bookingReceived", relatedEntityType: "booking",
      relatedEntityId: bookingId, actorUserId: userId,
    }), database);
    const reviewers = await bookingReviewerUserIds(organization, userId);
    await Promise.all(reviewers.map((reviewerUserId) => writeServerNotification(serverNotification({
      userId: reviewerUserId, organizationId,
      notificationId: `bookingSubmitted_${bookingId}`,
      title: "طلب حجز جديد", body: "يوجد طلب جديد لحجز المجلس.",
      type: "bookingSubmitted", relatedEntityType: "booking",
      relatedEntityId: bookingId, actorUserId: userId,
    }), database)));
  }
  return { bookingId, status: "pending", idempotent: result.idempotent };
}

async function reviewBookingHandler(request, options = {}) {
  const database = options.database || db();
  const reviewerId = requireAuth(request);
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const bookingId = requireString(request.data.bookingId, "bookingId", 128);
  const decision = requireString(request.data.decision, "decision", 20);
  if (!["approve", "reject"].includes(decision)) {
    throw new HttpsError("invalid-argument", "Invalid booking decision.");
  }
  const reason = optionalString(request.data.reason, 500);
  await requireBookingManager(organizationId, reviewerId, database);
  const organization = database.collection("organizations").doc(organizationId);
  const bookingRef = organization.collection("bookings").doc(bookingId);
  if (decision === "approve") {
    const pendingBooking = await bookingRef.get();
    if (!pendingBooking.exists || pendingBooking.get("organizationId") !== organizationId) {
      throw new HttpsError("not-found", "Booking not found.");
    }
    const bookingDay = pendingBooking.get("bookingDay") ||
      bookingDayFromTimestamp(pendingBooking.get("bookingDate"));
    const identity = bookingSlotIdentity({
      resourceId: pendingBooking.get("resourceId") || "council_hall",
      dayKey: bookingDay,
      startTime: pendingBooking.get("startTime") || "",
      endTime: pendingBooking.get("endTime") || "",
    });
    await assertNoLegacyBookingConflict({
      organization, bookingId, bookingDay,
      bookingDate: pendingBooking.get("bookingDate"),
      resourceId: identity.resourceId,
      startTime: pendingBooking.get("startTime") || "",
      endTime: pendingBooking.get("endTime") || "",
      includePending: false,
    });
  }
  const result = await database.runTransaction(async (transaction) => {
    const booking = await transaction.get(bookingRef);
    if (!booking.exists || booking.get("organizationId") !== organizationId) {
      throw new HttpsError("not-found", "Booking not found.");
    }
    if (booking.get("status") !== "pending") {
      throw new HttpsError("failed-precondition", "Booking is no longer pending.");
    }
    const bookingDay = booking.get("bookingDay") || bookingDayFromTimestamp(booking.get("bookingDate"));
    const slotIdentity = bookingSlotIdentity({
      resourceId: booking.get("resourceId") || "council_hall",
      dayKey: bookingDay,
      startTime: booking.get("startTime") || "",
      endTime: booking.get("endTime") || "",
    });
    const slotKey = booking.get("slotKey") || slotIdentity.slotKey;
    const slotRef = organization.collection("booking_slots").doc(slotKey);
    const slot = await transaction.get(slotRef);
    const now = Timestamp.now();
    if (decision === "approve") {
      if (slot.exists && slot.get("bookingId") !== bookingId &&
          ["pending", "approved", "cancellationRequested"].includes(slot.get("status"))) {
        throw new HttpsError("already-exists", "The requested booking slot is unavailable.");
      }
      transaction.set(slotRef, {
        organizationId, bookingId, userId: booking.get("userId"),
        resourceId: booking.get("resourceId") || "council_hall", slotKey,
        bookingDate: booking.get("bookingDate"), bookingDay,
        startTime: booking.get("startTime") || null, endTime: booking.get("endTime") || null,
        status: "approved", updatedAt: now,
        ...(slot.exists ? {} : { createdAt: now }),
      }, { merge: true });
      transaction.update(bookingRef, {
        status: "approved", approvedBy: reviewerId, approvedAt: now,
        rejectionReason: null, resourceId: slotIdentity.resourceId, slotKey,
        bookingDay, updatedAt: now,
      });
    } else {
      if (slot.exists && slot.get("bookingId") === bookingId) transaction.delete(slotRef);
      transaction.update(bookingRef, {
        status: "rejected", rejectedBy: reviewerId, rejectedAt: now,
        rejectionReason: reason || null, updatedAt: now,
      });
    }
    return { userId: booking.get("userId"), status: decision === "approve" ? "approved" : "rejected" };
  });
  await writeServerNotification(serverNotification({
    userId: result.userId, organizationId,
    notificationId: `booking${decision === "approve" ? "Approved" : "Rejected"}_${bookingId}`,
    title: decision === "approve" ? "تم قبول طلب الحجز" : "تم رفض طلب الحجز",
    body: decision === "approve" ? "تمت الموافقة على حجز المجلس." : "رُفض طلب الحجز؛ راجع تفاصيل الطلب.",
    type: decision === "approve" ? "bookingApproved" : "bookingRejected",
    relatedEntityType: "booking", relatedEntityId: bookingId, actorUserId: reviewerId,
  }), database);
  return { bookingId, status: result.status };
}

function accessProjection(membership, membershipId, organizationId) {
  const userId = membership.userId || membershipId;
  return {
    organizationId, membershipId, userId,
    status: membership.status || "inactive",
    roleId: membership.roleId || "member",
    role: membership.role || null,
    permissionsSnapshot: Array.isArray(membership.permissionsSnapshot)
      ? membership.permissionsSnapshot : [],
    isPrimaryOwner: isPrimaryCouncilOwner(membership),
    updatedAt: Timestamp.now(),
    source: "membershipProjection",
  };
}

async function syncMembershipAccessHandler(event, options = {}) {
  const database = options.database || db();
  const { organizationId, membershipId } = event.params;
  if (membershipId === "_meta") return { status: "ignored" };
  const before = event.data && event.data.before && event.data.before.exists
    ? event.data.before.data() : null;
  const after = event.data && event.data.after && event.data.after.exists
    ? event.data.after.data() : null;
  const oldUserId = before && (before.userId || membershipId);
  const newUserId = after && (after.userId || membershipId);
  const batch = database.batch();
  if (oldUserId && oldUserId !== newUserId) {
    batch.delete(database.doc(`organizations/${organizationId}/member_access/${oldUserId}`));
  }
  if (after) {
    batch.set(
      database.doc(`organizations/${organizationId}/member_access/${newUserId}`),
      accessProjection(after, membershipId, organizationId),
      { merge: false },
    );
  } else if (oldUserId) {
    batch.delete(database.doc(`organizations/${organizationId}/member_access/${oldUserId}`));
  }
  await batch.commit();
  if (after && (!before || before.status !== after.status || before.roleId !== after.roleId)) {
    await writeServerNotification(serverNotification({
      userId: newUserId, organizationId,
      notificationId: `membershipChanged_${membershipId}_${String(after.status || "updated")}`,
      title: "تحديث العضوية", body: "تم تحديث حالة عضويتك أو دورك في المجلس.",
      type: "membershipChanged", relatedEntityType: "membership",
      relatedEntityId: membershipId, actorUserId: after.updatedBy || after.approvedBy || "server",
    }), database);
  }
  return { status: after ? "projected" : "removed", userId: newUserId || oldUserId };
}

async function membershipRequestNotificationHandler(event, options = {}) {
  const database = options.database || db();
  const { organizationId, requestId } = event.params;
  const before = event.data && event.data.before && event.data.before.exists
    ? event.data.before.data() : null;
  const after = event.data && event.data.after && event.data.after.exists
    ? event.data.after.data() : null;
  if (!after) return { status: "ignored" };
  const userId = after.userId || requestId;
  const organization = database.collection("organizations").doc(organizationId);
  if (!before && after.status === "pending") {
    await writeServerNotification(serverNotification({
      userId, organizationId, notificationId: `membershipRequestReceived_${requestId}`,
      title: "تم استلام طلب الانضمام", body: "طلبك قيد مراجعة إدارة المجلس.",
      type: "membershipRequestReceived", relatedEntityType: "membershipRequest",
      relatedEntityId: requestId, actorUserId: userId,
    }), database);
    const reviewers = await membershipReviewerUserIds(organization, userId);
    await Promise.all(reviewers.map((reviewerUserId) => writeServerNotification(serverNotification({
      userId: reviewerUserId, organizationId,
      notificationId: `membershipRequestSubmitted_${requestId}`,
      title: "طلب انضمام جديد", body: "يوجد طلب جديد للانضمام إلى المجلس.",
      type: "membershipRequestSubmitted", relatedEntityType: "membershipRequest",
      relatedEntityId: requestId, actorUserId: userId,
    }), database)));
    return { status: "submitted" };
  }
  if (before && before.status !== after.status && ["approved", "rejected"].includes(after.status)) {
    await writeServerNotification(serverNotification({
      userId, organizationId,
      notificationId: `membership${after.status === "approved" ? "Approved" : "Rejected"}_${requestId}`,
      title: after.status === "approved" ? "تم قبول طلب الانضمام" : "تم رفض طلب الانضمام",
      body: after.status === "approved"
        ? "تمت الموافقة على انضمامك إلى المجلس."
        : "رُفض طلب الانضمام؛ راجع تفاصيل الطلب.",
      type: after.status === "approved" ? "membershipApproved" : "membershipRejected",
      relatedEntityType: "membershipRequest", relatedEntityId: requestId,
      actorUserId: after.reviewedBy || "server",
    }), database);
    return { status: after.status };
  }
  return { status: "unchanged" };
}

const defaultRoles = {
  chairman: ["fullAccess"],
  adminManager: ["members.manage", "members.read", "members.approve", "membershipRequests.review", "organization.manage", "settings.manage", "bookings.read", "bookings.approve", "bookings.reject", "bookings.manage"],
  financialManager: ["payments.manage", "transactions.review", "reports.view", "receipts.review", "payments.approve", "payments.reject", "payments.read"],
  financialReviewer: ["transactions.review", "reports.view", "receipts.review", "payments.approve", "payments.reject", "payments.read"],
  secretary: ["membershipRequests.review", "announcements.manage", "notifications.send", "audit.read"],
  member: ["profile.read", "payments.read", "rentals.create", "bookings.read", "bookings.create"],
};

async function bootstrapOrganizationHandler(request, options = {}) {
  const database = options.database || db();
  const actorUserId = requireAuth(request);
  if (!await isPlatformSystemOwner(actorUserId, database)) {
    throw new HttpsError("permission-denied", "Platform system owner permission is required.");
  }
  const requestId = requireString(request.data.requestId, "requestId", 128);
  if (!/^[A-Za-z0-9_-]+$/.test(requestId)) throw new HttpsError("invalid-argument", "requestId is invalid.");
  const requestedOrganizationId = optionalString(request.data.organizationId, 128);
  if (requestedOrganizationId && !/^[A-Za-z0-9_-]+$/.test(requestedOrganizationId)) {
    throw new HttpsError("invalid-argument", "organizationId is invalid.");
  }
  const organizationId = requestedOrganizationId || `org_${crypto.randomUUID().replaceAll("-", "")}`;
  const organization = database.collection("organizations").doc(organizationId);
  const requestRef = database.collection("organization_bootstrap_requests").doc(requestId);
  const chairmanUserId = optionalString(request.data.chairmanUserId, 128);
  const officialNameArabic = requireString(request.data.officialNameArabic, "officialNameArabic", 200);
  const officialNameEnglish = optionalString(request.data.officialNameEnglish, 200);
  const now = Timestamp.now();
  const result = await database.runTransaction(async (transaction) => {
    const [existingRequest, existingOrganization] = await Promise.all([
      transaction.get(requestRef), transaction.get(organization),
    ]);
    if (existingRequest.exists) {
      if (existingRequest.get("createdBy") !== actorUserId) {
        throw new HttpsError("already-exists", "Bootstrap request is owned by another actor.");
      }
      return { organizationId: existingRequest.get("organizationId"), idempotent: true };
    }
    if (existingOrganization.exists) throw new HttpsError("already-exists", "Organization already exists.");
    transaction.set(organization, {
      organizationId, officialNameArabic, officialNameEnglish,
      shortName: optionalString(request.data.shortName, 100),
      phone: optionalString(request.data.phone, 40),
      email: optionalString(request.data.email, 200),
      address: optionalString(request.data.address, 500),
      status: "active", profilePublished: true, schemaVersion: 1,
      navigationEnabled: true, createdAt: now, updatedAt: now, createdBy: actorUserId,
      bootstrapRequestId: requestId,
    });
    transaction.set(organization.collection("financial_profile").doc("banking"), {
      bankName: "", accountName: "", accountNumber: "", iban: "", swiftCode: "",
      enabled: false, updatedAt: now, updatedBy: actorUserId,
    });
    transaction.set(organization.collection("settings").doc("organization"), {
      locale: "ar", timezone: "Asia/Muscat", currency: "OMR", countryCode: "OM",
      navigationEnabled: true, allowHallRental: false, updatedAt: now, updatedBy: actorUserId,
    });
    transaction.set(organization.collection("settings").doc("location_maps"), {
      latitude: null, longitude: null, googleMapsUrl: optionalString(request.data.googleMapsUrl, 1000),
      appleMapsUrl: "", enabled: false, updatedAt: now, updatedBy: actorUserId,
    });
    for (const [roleId, permissions] of Object.entries(defaultRoles)) {
      transaction.set(organization.collection("roles").doc(roleId), {
        roleId, permissions, systemRole: true, isSystemRole: true,
        createdAt: now, updatedAt: now, createdBy: actorUserId, updatedBy: actorUserId,
      });
    }
    for (const collectionName of ["memberships", "membership_requests", "announcements", "events", "rentals", "rental_resources"]) {
      transaction.set(organization.collection(collectionName).doc("_meta"), {
        initialized: true, schemaVersion: 1, createdAt: now, updatedAt: now,
      });
    }
    if (chairmanUserId) {
      transaction.set(organization.collection("memberships").doc(`owner_${chairmanUserId}`), {
        userId: chairmanUserId, organizationId, roleId: "council_owner",
        status: "active", permissionsSnapshot: ["fullAccess"], isPrimaryOwner: true,
        memberNumber: "001", approvedBy: actorUserId, approvedAt: now,
        joinedAt: now, joinedReason: "organizationBootstrap",
      });
    }
    transaction.set(requestRef, {
      requestId, organizationId, createdBy: actorUserId, status: "completed", createdAt: now,
    });
    return { organizationId, idempotent: false };
  });
  return result;
}

async function repairOrganizationStructureHandler(request, options = {}) {
  const database = options.database || db();
  const actorUserId = requireAuth(request);
  if (!await isPlatformSystemOwner(actorUserId, database)) {
    throw new HttpsError("permission-denied", "Platform system owner permission is required.");
  }
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  if (!/^[A-Za-z0-9_-]+$/.test(organizationId)) {
    throw new HttpsError("invalid-argument", "organizationId is invalid.");
  }
  const organization = database.collection("organizations").doc(organizationId);
  const now = Timestamp.now();
  const requiredDocuments = [
    [organization.collection("financial_profile").doc("banking"), {
      bankName: "", accountName: "", accountNumber: "", iban: "", swiftCode: "",
      enabled: false, updatedAt: now, updatedBy: actorUserId,
    }],
    [organization.collection("settings").doc("organization"), {
      locale: "ar", timezone: "Asia/Muscat", currency: "OMR", countryCode: "OM",
      navigationEnabled: true, allowHallRental: false, updatedAt: now, updatedBy: actorUserId,
    }],
    [organization.collection("settings").doc("location_maps"), {
      latitude: null, longitude: null, googleMapsUrl: "", appleMapsUrl: "",
      enabled: false, updatedAt: now, updatedBy: actorUserId,
    }],
    ...Object.entries(defaultRoles).map(([roleId, permissions]) => [
      organization.collection("roles").doc(roleId),
      { roleId, permissions, systemRole: true, isSystemRole: true,
        createdAt: now, updatedAt: now, createdBy: actorUserId, updatedBy: actorUserId },
    ]),
    ...["memberships", "membership_requests", "announcements", "events", "rentals", "rental_resources"]
      .map((collectionName) => [
        organization.collection(collectionName).doc("_meta"),
        { initialized: true, schemaVersion: 1, createdAt: now, updatedAt: now },
      ]),
  ];
  const createdCount = await database.runTransaction(async (transaction) => {
    const organizationSnapshot = await transaction.get(organization);
    if (!organizationSnapshot.exists) {
      throw new HttpsError("not-found", "Organization not found.");
    }
    const snapshots = await Promise.all(requiredDocuments.map(([reference]) =>
      transaction.get(reference)));
    let count = 0;
    snapshots.forEach((snapshot, index) => {
      if (!snapshot.exists) {
        transaction.set(requiredDocuments[index][0], requiredDocuments[index][1]);
        count += 1;
      }
    });
    return count;
  });
  return { organizationId, createdCount, idempotent: createdCount === 0 };
}

async function transferPrimaryCouncilOwnershipHandler(request, options = {}) {
  const database = options.database || db();
  const actorUserId = requireAuth(request);
  if (!await isPlatformSystemOwner(actorUserId, database)) {
    throw new HttpsError("permission-denied", "Platform system owner permission is required.");
  }
  const organizationId = requireString(request.data.organizationId, "organizationId", 128);
  const currentMembershipId = requireString(request.data.currentMembershipId, "currentMembershipId", 128);
  const targetMembershipId = requireString(request.data.targetMembershipId, "targetMembershipId", 128);
  const previousOwnerRoleId = requireString(request.data.previousOwnerRoleId, "previousOwnerRoleId", 40);
  if (!["member", "chairman", "adminManager", "financialManager", "financialReviewer", "secretary"].includes(previousOwnerRoleId)) {
    throw new HttpsError("invalid-argument", "Previous owner role is not allowed.");
  }
  const organization = database.collection("organizations").doc(organizationId);
  await database.runTransaction(async (transaction) => {
    const currentRef = organization.collection("memberships").doc(currentMembershipId);
    const targetRef = organization.collection("memberships").doc(targetMembershipId);
    const [current, target] = await Promise.all([transaction.get(currentRef), transaction.get(targetRef)]);
    if (!current.exists || !isPrimaryCouncilOwner(current.data())) {
      throw new HttpsError("failed-precondition", "Current primary owner is invalid.");
    }
    if (!target.exists || target.get("status") !== "active" || isPrimaryCouncilOwner(target.data())) {
      throw new HttpsError("failed-precondition", "Target membership is not eligible.");
    }
    const now = Timestamp.now();
    transaction.update(currentRef, {
      isPrimaryOwner: false, roleId: previousOwnerRoleId,
      updatedAt: now, updatedBy: actorUserId,
    });
    transaction.update(targetRef, {
      isPrimaryOwner: true, roleId: "council_owner", status: "active",
      permissionsSnapshot: FieldValue.arrayUnion("fullAccess"),
      updatedAt: now, updatedBy: actorUserId,
    });
  });
  return { status: "transferred" };
}

exports.createBooking = onCall(sensitiveCallableOptions, createBookingHandler);
exports.reviewBooking = onCall(sensitiveCallableOptions, reviewBookingHandler);
exports.bootstrapOrganization = onCall(sensitiveCallableOptions, bootstrapOrganizationHandler);
exports.repairOrganizationStructure = onCall(
  sensitiveCallableOptions, repairOrganizationStructureHandler,
);
exports.transferPrimaryCouncilOwnership = onCall(
  sensitiveCallableOptions, transferPrimaryCouncilOwnershipHandler,
);
exports.syncMembershipAccess = onDocumentWritten(
  { document: "organizations/{organizationId}/memberships/{membershipId}", region: REGION },
  syncMembershipAccessHandler,
);
exports.onMembershipRequestNotification = onDocumentWritten(
  { document: "organizations/{organizationId}/membership_requests/{requestId}", region: REGION },
  membershipRequestNotificationHandler,
);

exports._test = {
  accessProjection,
  bookingDayFromTimestamp,
  bookingSlotIdentity,
  assertNoLegacyBookingConflict,
  bootstrapOrganizationHandler,
  repairOrganizationStructureHandler,
  createBookingHandler,
  isPrimaryCouncilOwner,
  membershipForUser,
  membershipRequestNotificationHandler,
  reviewBookingHandler,
  serverNotification,
  syncMembershipAccessHandler,
  transferPrimaryCouncilOwnershipHandler,
  writeServerNotification,
};
