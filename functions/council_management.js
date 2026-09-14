"use strict";

const crypto = require("node:crypto");
const admin = require("firebase-admin");
const { FieldPath, Timestamp } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { hasAnyMembershipPermission } = require("./permission_policy");

const REGION = "us-central1";
const sensitiveCallableOptions = {
  region: REGION,
  enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
};

const db = () => admin.firestore();

function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  return request.auth.uid;
}

function requireString(value, name, maxLength) {
  if (typeof value !== "string" || !value.trim() || value.length > maxLength) {
    throw new HttpsError("invalid-argument", `${name} is invalid.`);
  }
  return value.trim();
}

function optionalString(value, name, maxLength) {
  if (value == null || value === "") return "";
  if (typeof value !== "string" || value.length > maxLength) {
    throw new HttpsError("invalid-argument", `${name} is invalid.`);
  }
  return value.trim();
}

function requireIdentifier(value, name) {
  const result = requireString(value, name, 128);
  if (!/^[A-Za-z0-9_-]+$/.test(result)) {
    throw new HttpsError("invalid-argument", `${name} is invalid.`);
  }
  return result;
}

function isCouncilOwner(data = {}) {
  return data.isPrimaryOwner === true ||
    ["owner", "council_owner"].includes(data.roleId) ||
    ["owner", "council_owner"].includes(data.role) ||
    hasAnyMembershipPermission(data, ["fullAccess"]);
}

function hasRole(data = {}, roles) {
  return roles.includes(data.roleId) || roles.includes(data.role);
}

async function isPlatformOwner(userId, database) {
  const snapshot = await database.collection("platform_admins").doc(userId).get();
  if (!snapshot.exists || snapshot.get("status") !== "active") return false;
  return snapshot.get("role") === "system_owner" ||
    (snapshot.get("role") === "superAdmin" && snapshot.get("fullAccess") === true);
}

async function membershipForUser(organizationId, userId, database) {
  const memberships = database.collection("organizations").doc(organizationId)
    .collection("memberships");
  const direct = await memberships.doc(userId).get();
  if (direct.exists && (direct.get("userId") || direct.id) === userId) return direct;
  const snapshot = await memberships.where("userId", "==", userId).limit(2).get();
  if (snapshot.size > 1) {
    throw new HttpsError(
      "failed-precondition",
      "Duplicate council memberships require review.",
    );
  }
  return snapshot.empty ? null : snapshot.docs[0];
}

async function requireCouncilAccess(organizationId, userId, database) {
  const organization = database.collection("organizations").doc(organizationId);
  const [organizationSnapshot, platformOwner, membership] = await Promise.all([
    organization.get(),
    isPlatformOwner(userId, database),
    membershipForUser(organizationId, userId, database),
  ]);
  if (!organizationSnapshot.exists) {
    throw new HttpsError("not-found", "Organization not found.");
  }
  if (platformOwner) {
    return { organization, organizationData: organizationSnapshot.data(), platformOwner, membership: null };
  }
  if (!membership || membership.get("status") !== "active" ||
      membership.get("organizationId") !== organizationId ||
      membership.get("userId") !== userId) {
    throw new HttpsError("permission-denied", "Active council membership is required.");
  }
  return {
    organization,
    organizationData: organizationSnapshot.data(),
    platformOwner,
    membership: membership.data(),
  };
}

function canManageAnnouncements(access) {
  return access.platformOwner || isCouncilOwner(access.membership) ||
    hasRole(access.membership, ["chairman", "secretary"]) ||
    hasAnyMembershipPermission(access.membership, ["announcements.manage"]);
}

function canSendNotifications(access) {
  return access.platformOwner || isCouncilOwner(access.membership) ||
    hasRole(access.membership, ["chairman", "secretary"]) ||
    hasAnyMembershipPermission(access.membership, [
      "notifications.send", "announcements.manage",
    ]);
}

function canEditCouncilProfile(access) {
  return access.platformOwner || isCouncilOwner(access.membership) ||
    hasRole(access.membership, ["chairman", "adminManager"]) ||
    hasAnyMembershipPermission(access.membership, [
      "organization.manage", "settings.manage",
    ]);
}

function canViewFinancialReports(access) {
  return access.platformOwner || isCouncilOwner(access.membership) ||
    hasRole(access.membership, ["chairman", "financialManager", "financialReviewer"]) ||
    hasAnyMembershipPermission(access.membership, [
      "reports.view", "payments.manage", "receipts.review", "payments.read",
    ]);
}

function canManageExpenses(access) {
  return access.platformOwner || isCouncilOwner(access.membership) ||
    hasRole(access.membership, ["chairman", "financialManager"]) ||
    hasAnyMembershipPermission(access.membership, ["expenses.manage", "payments.manage"]);
}

function requireCapability(access, predicate, message) {
  if (!predicate(access)) throw new HttpsError("permission-denied", message);
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
    createdByUserId: actorUserId,
    deliverySource: "server",
  };
}

async function readAllDocuments(collection, pageSize = 400) {
  const documents = [];
  let last = null;
  do {
    let query = collection.orderBy(FieldPath.documentId()).limit(pageSize);
    if (last) query = query.startAfter(last);
    const snapshot = await query.get();
    documents.push(...snapshot.docs);
    last = snapshot.size === pageSize ? snapshot.docs[snapshot.docs.length - 1] : null;
  } while (last);
  return documents;
}

async function activeCouncilUserIds(organization) {
  const memberships = await readAllDocuments(
    organization.collection("memberships").where("status", "==", "active"),
  );
  return [...new Set(memberships
    .map((membership) => membership.get("userId") || membership.id)
    .filter((userId) => typeof userId === "string" && userId.trim()))];
}

async function fanOutCouncilNotification({
  organization, organizationId, notificationId, title, body, type,
  relatedEntityType, relatedEntityId, actorUserId, database,
}) {
  const userIds = await activeCouncilUserIds(organization);
  for (let offset = 0; offset < userIds.length; offset += 400) {
    const batch = database.batch();
    for (const userId of userIds.slice(offset, offset + 400)) {
      const reference = database.collection("users").doc(userId)
        .collection("notifications").doc(notificationId);
      batch.set(reference, serverNotification({
        userId,
        organizationId,
        notificationId,
        title,
        body,
        type,
        relatedEntityType,
        relatedEntityId,
        actorUserId,
      }));
    }
    await batch.commit();
  }
  return userIds.length;
}

async function createAnnouncementHandler(request, options = {}) {
  const database = options.database || db();
  const actorUserId = requireAuth(request);
  const organizationId = requireIdentifier(request.data.organizationId, "organizationId");
  const requestId = requireIdentifier(request.data.requestId, "requestId");
  const title = requireString(request.data.title, "title", 120);
  const content = requireString(request.data.content, "content", 2000);
  const access = await requireCouncilAccess(organizationId, actorUserId, database);
  requireCapability(
    access,
    canManageAnnouncements,
    "Announcement management permission is required.",
  );
  const reference = access.organization.collection("announcements").doc(requestId);
  let created = false;
  const announcement = await database.runTransaction(async (transaction) => {
    const existing = await transaction.get(reference);
    if (existing.exists) {
      if (existing.get("organizationId") !== organizationId ||
          existing.get("createdBy") !== actorUserId) {
        throw new HttpsError("already-exists", "Announcement request ID is already used.");
      }
      return existing.data();
    }
    const now = Timestamp.now();
    const data = {
      announcementId: requestId,
      organizationId,
      title,
      content,
      status: "published",
      createdBy: actorUserId,
      updatedBy: actorUserId,
      createdAt: now,
      updatedAt: now,
    };
    transaction.create(reference, data);
    created = true;
    return data;
  });
  const deliveredCount = await fanOutCouncilNotification({
    organization: access.organization,
    organizationId,
    notificationId: `announcement_${requestId}`,
    title: `إعلان جديد: ${announcement.title}`,
    body: announcement.content,
    type: "announcementPublished",
    relatedEntityType: "announcement",
    relatedEntityId: requestId,
    actorUserId,
    database,
  });
  return { announcementId: requestId, deliveredCount, idempotent: !created };
}

async function sendCouncilNotificationHandler(request, options = {}) {
  const database = options.database || db();
  const actorUserId = requireAuth(request);
  const organizationId = requireIdentifier(request.data.organizationId, "organizationId");
  const requestId = requireIdentifier(request.data.requestId, "requestId");
  const title = requireString(request.data.title, "title", 120);
  const body = requireString(request.data.body, "body", 1000);
  const access = await requireCouncilAccess(organizationId, actorUserId, database);
  requireCapability(
    access,
    canSendNotifications,
    "Notification sending permission is required.",
  );
  const reference = access.organization.collection("broadcasts").doc(requestId);
  let created = false;
  const broadcast = await database.runTransaction(async (transaction) => {
    const existing = await transaction.get(reference);
    if (existing.exists) {
      if (existing.get("organizationId") !== organizationId ||
          existing.get("createdBy") !== actorUserId) {
        throw new HttpsError("already-exists", "Notification request ID is already used.");
      }
      return existing.data();
    }
    const now = Timestamp.now();
    const data = {
      broadcastId: requestId,
      organizationId,
      title,
      body,
      createdBy: actorUserId,
      createdAt: now,
      updatedAt: now,
    };
    transaction.create(reference, data);
    created = true;
    return data;
  });
  const deliveredCount = await fanOutCouncilNotification({
    organization: access.organization,
    organizationId,
    notificationId: `broadcast_${requestId}`,
    title: broadcast.title,
    body: broadcast.body,
    type: "councilBroadcast",
    relatedEntityType: "broadcast",
    relatedEntityId: requestId,
    actorUserId,
    database,
  });
  return { broadcastId: requestId, deliveredCount, idempotent: !created };
}

function parseDateOnly(value, fieldName, { allowFuture = true } = {}) {
  if (value == null || value === "") return null;
  const text = requireString(value, fieldName, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) {
    throw new HttpsError("invalid-argument", `${fieldName} is invalid.`);
  }
  const [year, month, day] = text.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day, 8));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 ||
      date.getUTCDate() !== day || (!allowFuture && date > new Date())) {
    throw new HttpsError("invalid-argument", `${fieldName} is invalid.`);
  }
  return Timestamp.fromDate(date);
}

async function updateCouncilProfileHandler(request, options = {}) {
  const database = options.database || db();
  const actorUserId = requireAuth(request);
  const organizationId = requireIdentifier(request.data.organizationId, "organizationId");
  const access = await requireCouncilAccess(organizationId, actorUserId, database);
  requireCapability(
    access,
    canEditCouncilProfile,
    "Council profile management permission is required.",
  );
  const description = optionalString(request.data.description, "description", 1500);
  const vision = optionalString(request.data.vision, "vision", 1000);
  const mission = optionalString(request.data.mission, "mission", 1000);
  const phone = optionalString(request.data.phone, "phone", 40);
  const email = optionalString(request.data.email, "email", 160);
  const address = optionalString(request.data.address, "address", 500);
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpsError("invalid-argument", "email is invalid.");
  }
  const foundedAt = parseDateOnly(request.data.foundedOn, "foundedOn", { allowFuture: false });
  await database.runTransaction(async (transaction) => {
    const current = await transaction.get(access.organization);
    if (!current.exists) throw new HttpsError("not-found", "Organization not found.");
    const currentDescription = current.get("description");
    const currentProfile = current.get("councilProfile");
    transaction.set(access.organization, {
      description: {
        ...(currentDescription && typeof currentDescription === "object" ? currentDescription : {}),
        ar: description,
      },
      councilProfile: {
        ...(currentProfile && typeof currentProfile === "object" ? currentProfile : {}),
        foundedAt,
        vision,
        mission,
      },
      phone,
      email,
      address,
      updatedBy: actorUserId,
      updatedAt: Timestamp.now(),
    }, { merge: true });
  });
  return { organizationId, status: "updated" };
}

const expenseCategories = new Set([
  "bills", "electricity", "water", "communications", "supplies",
  "maintenance", "cleaning", "equipment", "hospitality", "other",
]);

async function createCouncilExpenseHandler(request, options = {}) {
  const database = options.database || db();
  const actorUserId = requireAuth(request);
  const organizationId = requireIdentifier(request.data.organizationId, "organizationId");
  const requestId = requireIdentifier(request.data.requestId, "requestId");
  const title = requireString(request.data.title, "title", 160);
  const note = optionalString(request.data.note, "note", 1000);
  const supplier = optionalString(request.data.supplier, "supplier", 160);
  const invoiceNumber = optionalString(request.data.invoiceNumber, "invoiceNumber", 100);
  const attachmentStoragePath = optionalString(
    request.data.attachmentStoragePath,
    "attachmentStoragePath",
    500,
  );
  if (attachmentStoragePath &&
      !attachmentStoragePath.startsWith(`organizations/${organizationId}/expenses/${requestId}/`)) {
    throw new HttpsError("invalid-argument", "Expense attachment path is invalid.");
  }
  const category = requireString(request.data.category, "category", 40);
  const amountBaisa = request.data.amountBaisa;
  if (!Number.isSafeInteger(amountBaisa) || amountBaisa <= 0 || amountBaisa > 999999999999) {
    throw new HttpsError("invalid-argument", "amountBaisa must be a positive integer.");
  }
  if (!expenseCategories.has(category)) {
    throw new HttpsError("invalid-argument", "category is invalid.");
  }
  const expenseDate = parseDateOnly(request.data.expenseDate, "expenseDate");
  if (!expenseDate) throw new HttpsError("invalid-argument", "expenseDate is required.");
  const access = await requireCouncilAccess(organizationId, actorUserId, database);
  requireCapability(access, canManageExpenses, "Expense management permission is required.");
  const reference = access.organization.collection("expenses").doc(requestId);
  let created = false;
  await database.runTransaction(async (transaction) => {
    const existing = await transaction.get(reference);
    if (existing.exists) {
      if (existing.get("organizationId") !== organizationId ||
          existing.get("createdBy") !== actorUserId) {
        throw new HttpsError("already-exists", "Expense request ID is already used.");
      }
      return;
    }
    const now = Timestamp.now();
    transaction.create(reference, {
      expenseId: requestId,
      organizationId,
      title,
      note,
      supplier,
      invoiceNumber,
      attachmentStoragePath: attachmentStoragePath || null,
      category,
      amountBaisa,
      expenseDate,
      status: "posted",
      createdBy: actorUserId,
      createdAt: now,
      updatedAt: now,
    });
    created = true;
  });
  return { expenseId: requestId, idempotent: !created };
}

async function updateCouncilExpenseHandler(request, options = {}) {
  const database = options.database || db();
  const actorUserId = requireAuth(request);
  const organizationId = requireIdentifier(request.data.organizationId, "organizationId");
  const expenseId = requireIdentifier(request.data.expenseId, "expenseId");
  const action = requireString(request.data.action || "update", "action", 20);
  if (!["update", "cancel"].includes(action)) {
    throw new HttpsError("invalid-argument", "Expense action is invalid.");
  }
  const access = await requireCouncilAccess(organizationId, actorUserId, database);
  requireCapability(access, canManageExpenses, "Expense management permission is required.");
  const reference = access.organization.collection("expenses").doc(expenseId);
  await database.runTransaction(async (transaction) => {
    const current = await transaction.get(reference);
    if (!current.exists || current.get("organizationId") !== organizationId) {
      throw new HttpsError("not-found", "Expense not found.");
    }
    if (current.get("status") === "cancelled") {
      throw new HttpsError("failed-precondition", "Expense is already cancelled.");
    }
    const now = Timestamp.now();
    if (action === "cancel") {
      transaction.update(reference, {
        status: "cancelled", cancelledBy: actorUserId,
        cancelledAt: now, updatedBy: actorUserId, updatedAt: now,
      });
      return;
    }
    const title = requireString(request.data.title, "title", 160);
    const note = optionalString(request.data.note, "note", 1000);
    const supplier = optionalString(request.data.supplier, "supplier", 160);
    const invoiceNumber = optionalString(request.data.invoiceNumber, "invoiceNumber", 100);
    const category = requireString(request.data.category, "category", 40);
    const amountBaisa = request.data.amountBaisa;
    const expenseDate = parseDateOnly(request.data.expenseDate, "expenseDate");
    if (!expenseCategories.has(category) || !expenseDate ||
        !Number.isSafeInteger(amountBaisa) || amountBaisa <= 0 || amountBaisa > 999999999999) {
      throw new HttpsError("invalid-argument", "Expense data is invalid.");
    }
    const attachmentStoragePath = optionalString(
      request.data.attachmentStoragePath,
      "attachmentStoragePath",
      500,
    );
    if (attachmentStoragePath &&
        !attachmentStoragePath.startsWith(`organizations/${organizationId}/expenses/${expenseId}/`)) {
      throw new HttpsError("invalid-argument", "Expense attachment path is invalid.");
    }
    transaction.update(reference, {
      title, note, supplier, invoiceNumber, category, amountBaisa, expenseDate,
      attachmentStoragePath: attachmentStoragePath || current.get("attachmentStoragePath") || null,
      updatedBy: actorUserId, updatedAt: now,
    });
  });
  return { expenseId, status: action === "cancel" ? "cancelled" : "updated" };
}

function legacyBaisa(data, baisaKey, legacyKeys = []) {
  const value = data && data[baisaKey];
  if (Number.isSafeInteger(value)) return value;
  for (const key of legacyKeys) {
    const legacy = data && data[key];
    if (typeof legacy === "number" && Number.isFinite(legacy)) {
      // توافق قراءة فقط مع حقول الريال القديمة؛ كل كتابة حديثة تبقى integer baisa.
      return Math.round(legacy * 1000);
    }
  }
  return 0;
}

function safeSum(values) {
  const total = values.reduce((sum, value) => sum + value, 0);
  if (!Number.isSafeInteger(total)) {
    throw new HttpsError("failed-precondition", "Financial total exceeds safe integer range.");
  }
  return total;
}

function buildFinancialReport({ transactions, charges, bookings, expenses }) {
  const chargeById = new Map(charges.map((item) => [item.id, item.data]));
  const bookingById = new Map(bookings.map((item) => [item.id, item.data]));
  const revenueByCategory = {
    subscription: 0,
    bookingRegular: 0,
    bookingEvent: 0,
    packageAddOn: 0,
    other: 0,
  };
  const staff = new Map();
  const bump = (userId, field) => {
    if (typeof userId !== "string" || !userId) return;
    const value = staff.get(userId) || {
      userId, receiptsApproved: 0, receiptsRejected: 0,
      bookingsApproved: 0, bookingsRejected: 0,
    };
    value[field] += 1;
    staff.set(userId, value);
  };

  let totalCollectedBaisa = 0;
  for (const transaction of transactions) {
    const data = transaction.data;
    const status = data.reviewStatus || data.status;
    if (status === "approved") {
      const amount = legacyBaisa(data, "amountDeclaredBaisa", ["amountDeclared"]);
      totalCollectedBaisa = safeSum([totalCollectedBaisa, amount]);
      const allocations = Array.isArray(data.allocations) ? data.allocations : [];
      if (allocations.length === 0) {
        revenueByCategory.other = safeSum([revenueByCategory.other, amount]);
      }
      for (const allocation of allocations) {
        const allocated = legacyBaisa(
          allocation,
          "amountAllocatedBaisa",
          ["amountAllocated"],
        );
        const charge = chargeById.get(allocation.chargeId) || {};
        let category = "other";
        if (charge.chargeType === "subscription") category = "subscription";
        if (charge.chargeType === "booking") {
          const booking = bookingById.get(charge.sourceId || charge.bookingId) || {};
          category = booking.bookingCategory === "event" ? "bookingEvent" : "bookingRegular";
        }
        if (["package", "addOn", "addon"].includes(charge.chargeType)) {
          category = "packageAddOn";
        }
        revenueByCategory[category] = safeSum([revenueByCategory[category], allocated]);
      }
      bump(data.reviewedBy, "receiptsApproved");
    } else if (status === "rejected") {
      bump(data.reviewedBy, "receiptsRejected");
    }
  }

  let totalDueBaisa = 0;
  let totalPaidBaisa = 0;
  let totalOutstandingBaisa = 0;
  let paidChargeCount = 0;
  let openChargeCount = 0;
  const paidMembershipIds = new Set();
  const unpaidMembershipIds = new Set();
  for (const charge of charges) {
    const data = charge.data;
    const amountDue = legacyBaisa(data, "amountDueBaisa", ["amountDue", "amount"]);
    const amountPaid = legacyBaisa(data, "amountPaidBaisa", ["amountPaid"]);
    totalDueBaisa = safeSum([totalDueBaisa, amountDue]);
    totalPaidBaisa = safeSum([totalPaidBaisa, amountPaid]);
    const hasStoredBalance = Number.isSafeInteger(data.balanceBaisa) ||
      (typeof data.balance === "number" && Number.isFinite(data.balance));
    const balance = hasStoredBalance
      ? legacyBaisa(data, "balanceBaisa", ["balance"])
      : Math.max(0, amountDue - amountPaid);
    totalOutstandingBaisa = safeSum([totalOutstandingBaisa, Math.max(0, balance)]);
    const membershipId = data.membershipId || data.memberId;
    if (data.status === "paid") {
      paidChargeCount += 1;
      if (membershipId) paidMembershipIds.add(membershipId);
    } else if (!["cancelled", "waived"].includes(data.status)) {
      openChargeCount += 1;
      if (membershipId && Math.max(0, balance) > 0) unpaidMembershipIds.add(membershipId);
    }
  }

  const bookingCounts = {
    total: bookings.length,
    pending: 0,
    approved: 0,
    rejected: 0,
    cancelled: 0,
    regular: 0,
    event: 0,
  };
  for (const booking of bookings) {
    const data = booking.data;
    if (Object.hasOwn(bookingCounts, data.status)) bookingCounts[data.status] += 1;
    bookingCounts[data.bookingCategory === "event" ? "event" : "regular"] += 1;
    if (data.status === "approved") bump(data.approvedBy || data.reviewedBy, "bookingsApproved");
    if (data.status === "rejected") bump(data.reviewedBy || data.rejectedBy, "bookingsRejected");
  }

  const expenseByCategory = {};
  let totalExpensesBaisa = 0;
  let expenseCount = 0;
  for (const expense of expenses) {
    const data = expense.data;
    if (data.status && data.status !== "posted") continue;
    expenseCount += 1;
    const amount = legacyBaisa(data, "amountBaisa");
    totalExpensesBaisa = safeSum([totalExpensesBaisa, amount]);
    const category = expenseCategories.has(data.category) ? data.category : "other";
    expenseByCategory[category] = safeSum([expenseByCategory[category] || 0, amount]);
  }

  return {
    totalCollectedBaisa,
    totalExpensesBaisa,
    netBalanceBaisa: safeSum([totalCollectedBaisa, -totalExpensesBaisa]),
    totalDueBaisa,
    totalPaidBaisa,
    totalOutstandingBaisa,
    transactionCount: transactions.length,
    chargeCount: charges.length,
    paidChargeCount,
    openChargeCount,
    membersPaidCount: [...paidMembershipIds]
      .filter((membershipId) => !unpaidMembershipIds.has(membershipId)).length,
    membersUnpaidCount: unpaidMembershipIds.size,
    expenseCount,
    revenueByCategory,
    expenseByCategory,
    bookingCounts,
    staffPerformance: [...staff.values()],
  };
}

async function resolveUserName(userId, database, organization) {
  if (!userId) return "غير معروف";
  const [user, member, membership] = await Promise.all([
    database.collection("users").doc(userId).get().catch(() => null),
    database.collection("members").doc(userId).get().catch(() => null),
    organization.collection("memberships").where("userId", "==", userId).limit(1).get()
      .catch(() => null),
  ]);
  const membershipData = membership && !membership.empty ? membership.docs[0].data() : null;
  for (const data of [user && user.exists ? user.data() : null,
    member && member.exists ? member.data() : null, membershipData]) {
    const name = data && (data.fullName || data.name || data.displayName);
    if (typeof name === "string" && name.trim()) return name.trim();
  }
  return "مستخدم إداري";
}

async function getCouncilFinancialReportHandler(request, options = {}) {
  const database = options.database || db();
  const userId = requireAuth(request);
  const organizationId = requireIdentifier(request.data.organizationId, "organizationId");
  const startDate = parseDateOnly(request.data.startDate, "startDate");
  const endDate = parseDateOnly(request.data.endDate, "endDate");
  if (startDate && endDate && startDate.toMillis() > endDate.toMillis()) {
    throw new HttpsError("invalid-argument", "Report date range is invalid.");
  }
  const access = await requireCouncilAccess(organizationId, userId, database);
  requireCapability(
    access,
    canViewFinancialReports,
    "Financial report permission is required.",
  );
  const [transactionsDocs, chargesDocs, bookingsDocs, expensesDocs] = await Promise.all([
    readAllDocuments(access.organization.collection("transactions")),
    readAllDocuments(access.organization.collection("charges")),
    readAllDocuments(access.organization.collection("bookings")),
    readAllDocuments(access.organization.collection("expenses")),
  ]);
  const inRange = (data, fields) => {
    const timestamp = fields.map((field) => data[field])
      .find((value) => value && typeof value.toMillis === "function");
    if (!timestamp) return !startDate && !endDate;
    const millis = timestamp.toMillis();
    return (!startDate || millis >= startDate.toMillis()) &&
      (!endDate || millis < endDate.toMillis() + 24 * 60 * 60 * 1000);
  };
  const report = buildFinancialReport({
    transactions: transactionsDocs.map((document) => ({ id: document.id, data: document.data() }))
      .filter((item) => inRange(item.data, ["reviewedAt", "submittedAt", "createdAt"])),
    charges: chargesDocs.map((document) => ({ id: document.id, data: document.data() }))
      .filter((item) => inRange(item.data, ["dueDate", "createdAt", "updatedAt"])),
    bookings: bookingsDocs.map((document) => ({ id: document.id, data: document.data() }))
      .filter((item) => inRange(item.data, ["bookingDate", "createdAt"])),
    expenses: expensesDocs.map((document) => ({ id: document.id, data: document.data() }))
      .filter((item) => inRange(item.data, ["expenseDate", "createdAt"])),
  });
  report.staffPerformance = await Promise.all(report.staffPerformance.map(async (item) => ({
    ...item,
    displayName: await resolveUserName(item.userId, database, access.organization),
  })));
  return { ...report, organizationId, generatedAtMillis: Date.now() };
}

function timestampMillis(value) {
  return value && typeof value.toMillis === "function" ? value.toMillis() : null;
}

async function getCouncilActivityDetailHandler(request, options = {}) {
  const database = options.database || db();
  const userId = requireAuth(request);
  const organizationId = requireIdentifier(request.data.organizationId, "organizationId");
  const entityType = requireString(request.data.entityType, "entityType", 40);
  const entityId = requireIdentifier(request.data.entityId, "entityId");
  const access = await requireCouncilAccess(organizationId, userId, database);
  const collectionName = {
    receipt: "transactions",
    booking: "bookings",
    announcement: "announcements",
    broadcast: "broadcasts",
  }[entityType];
  if (!collectionName) throw new HttpsError("invalid-argument", "entityType is invalid.");
  const snapshot = await access.organization.collection(collectionName).doc(entityId).get();
  if (!snapshot.exists) throw new HttpsError("not-found", "Activity not found.");
  const data = snapshot.data();
  if (entityType === "receipt") {
    const beneficiaryUserIds = Array.isArray(data.beneficiaryUserIds) ? data.beneficiaryUserIds : [];
    if (!canViewFinancialReports(access) && data.payerUserId !== userId &&
        data.userId !== userId && !beneficiaryUserIds.includes(userId)) {
      throw new HttpsError("permission-denied", "Receipt access is denied.");
    }
  }
  if (entityType === "booking" && data.userId !== userId &&
      !canViewFinancialReports(access) &&
      !(access.platformOwner || isCouncilOwner(access.membership) ||
        hasRole(access.membership, ["chairman", "adminManager"]) ||
        hasAnyMembershipPermission(access.membership, ["bookings.manage", "bookings.approve"]))) {
    throw new HttpsError("permission-denied", "Booking access is denied.");
  }
  if (entityType === "broadcast" && !canSendNotifications(access)) {
    throw new HttpsError("permission-denied", "Broadcast access is denied.");
  }
  const reviewedBy = data.reviewedBy || data.approvedBy || data.rejectedBy || "";
  const submittedBy = data.payerUserId || data.userId || data.createdBy || "";
  return {
    entityType,
    entityId,
    organizationId,
    title: data.title || data.titleArabic || data.occasionType ||
      (entityType === "receipt" ? "إيصال مالي" : "نشاط المجلس"),
    status: data.reviewStatus || data.status || "published",
    amountBaisa: entityType === "receipt"
      ? legacyBaisa(data, "amountDeclaredBaisa", ["amountDeclared"])
      : 0,
    submittedByName: data.payerName || data.requesterName ||
      await resolveUserName(submittedBy, database, access.organization),
    reviewedByName: reviewedBy
      ? await resolveUserName(reviewedBy, database, access.organization)
      : "",
    createdAtMillis: timestampMillis(data.submittedAt || data.createdAt || data.bookingDate),
    reviewedAtMillis: timestampMillis(data.reviewedAt || data.updatedAt),
    rejectionReason: data.rejectionReason || "",
    content: entityType === "announcement" ? data.content :
      entityType === "broadcast" ? data.body : "",
  };
}

function normalizeOmaniPhone(value) {
  if (typeof value !== "string") return "";
  const digits = value.replace(/\D/g, "");
  const local = digits.startsWith("968") ? digits.slice(3) : digits;
  return /^\d{8}$/.test(local) ? `+968${local}` : "";
}

async function resetPasswordWithVerifiedPhoneHandler(request, options = {}) {
  const auth = options.auth || admin.auth();
  const verifierUserId = requireAuth(request);
  const verifiedPhone = normalizeOmaniPhone(request.auth.token.phone_number);
  if (!verifiedPhone) {
    throw new HttpsError("permission-denied", "A verified Omani phone number is required.");
  }
  const newPassword = requireString(request.data.newPassword, "newPassword", 128);
  if (newPassword.length < 8 || !/[A-Za-z]/.test(newPassword) || !/\d/.test(newPassword)) {
    throw new HttpsError(
      "invalid-argument",
      "Password must be at least 8 characters and contain letters and digits.",
    );
  }
  const email = `${verifiedPhone.slice(1)}@alrahmat.local`;
  let target;
  try {
    target = await auth.getUserByEmail(email);
  } catch (error) {
    if (error && error.code === "auth/user-not-found") {
      throw new HttpsError("not-found", "No password account is linked to this phone number.");
    }
    throw error;
  }
  await auth.updateUser(target.uid, { password: newPassword });
  await auth.revokeRefreshTokens(target.uid);
  if (verifierUserId !== target.uid) {
    await auth.deleteUser(verifierUserId).catch(() => {});
  }
  return { status: "password-updated" };
}

exports.createCouncilAnnouncement = onCall(
  sensitiveCallableOptions,
  createAnnouncementHandler,
);
exports.sendCouncilNotification = onCall(
  sensitiveCallableOptions,
  sendCouncilNotificationHandler,
);
exports.updateCouncilProfile = onCall(
  sensitiveCallableOptions,
  updateCouncilProfileHandler,
);
exports.createCouncilExpense = onCall(
  sensitiveCallableOptions,
  createCouncilExpenseHandler,
);
exports.updateCouncilExpense = onCall(
  sensitiveCallableOptions,
  updateCouncilExpenseHandler,
);
exports.getCouncilFinancialReport = onCall(
  sensitiveCallableOptions,
  getCouncilFinancialReportHandler,
);
exports.getCouncilActivityDetail = onCall(
  sensitiveCallableOptions,
  getCouncilActivityDetailHandler,
);
exports.resetPasswordWithVerifiedPhone = onCall(
  sensitiveCallableOptions,
  resetPasswordWithVerifiedPhoneHandler,
);

exports._test = {
  buildFinancialReport,
  canEditCouncilProfile,
  canManageAnnouncements,
  canManageExpenses,
  canSendNotifications,
  canViewFinancialReports,
  createCouncilExpenseHandler,
  updateCouncilExpenseHandler,
  sendCouncilNotificationHandler,
  getCouncilActivityDetailHandler,
  getCouncilFinancialReportHandler,
  legacyBaisa,
  normalizeOmaniPhone,
  parseDateOnly,
  resetPasswordWithVerifiedPhoneHandler,
};
