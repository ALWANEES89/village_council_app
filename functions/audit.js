/**
 * سجل الأحداث الخادمي (Server-side Audit Trail)
 * ------------------------------------------------------------------
 * Firestore triggers تُنشئ سجلّات audit_logs تلقائيًا عند العمليات الحسّاسة.
 * السجل يُكتب بواسطة Admin SDK فقط (يتجاوز Firestore Rules)، والعميل ممنوع
 * من الإنشاء/التعديل/الحذف — مما يجعل السجل append-only ومقاومًا للتلاعب.
 *
 * كل سجل يحتوي على:
 *   actorUserId, actorName, actorRole, action, targetType, targetId,
 *   organizationId, oldValue, newValue, createdAt, source='cloud_function',
 *   platform (إن توفّر في المستند).
 *
 * ملاحظة عن الفاعل (actor): مشغّلات الخلفية لا تحمل هوية المستخدم الذي نفّذ
 * الكتابة، لذلك يُشتقّ الفاعل من حقول المستند نفسه (approvedBy / reviewedBy /
 * updatedBy / removedBy / cancelledBy / userId ...) ثم يُستكمل الاسم والدور من
 * قاعدة البيانات. إن غاب الحقل يُسجَّل actorRole='unknown'.
 */

const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const { FieldValue } = require("firebase-admin/firestore");

const REGION = "us-central1";
const db = () => admin.firestore();

// ── أدوات مساعدة ────────────────────────────────────────────────────────────

/** يُعيد نسخة تحتوي فقط المفاتيح المطلوبة (لتقليل الضجيج وحجم السجل). */
function pick(obj, keys) {
  if (!obj) return null;
  const out = {};
  for (const key of keys) {
    if (obj[key] !== undefined) out[key] = obj[key];
  }
  return Object.keys(out).length > 0 ? out : null;
}

/** مقارنة قيمتين (مصفوفات/كائنات) بشكل مستقر. */
function equal(a, b) {
  return JSON.stringify(a === undefined ? null : a) ===
    JSON.stringify(b === undefined ? null : b);
}

/** أول قيمة نصية غير فارغة من قائمة مرشّحين. */
function firstDefined(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim() !== "") return value;
  }
  return null;
}

/**
 * يستكمل اسم ودور الفاعل من قاعدة البيانات.
 * أولوية الدور: superAdmin (منصّة) ← roleId داخل المجلس ← legacyAdmin ← unknown.
 */
async function resolveActor(actorUserId, organizationId) {
  if (!actorUserId) {
    return { actorUserId: null, actorName: "غير معروف", actorRole: "unknown" };
  }

  let actorName = null;
  let actorRole = "unknown";

  // الاسم من users ثم members
  try {
    const userSnap = await db().collection("users").doc(actorUserId).get();
    if (userSnap.exists) actorName = firstDefined(userSnap.get("fullName"), actorName);
  } catch (err) {
    console.warn(`[audit] users lookup failed for ${actorUserId}: ${err.message}`);
  }
  if (!actorName) {
    try {
      const memberSnap = await db().collection("members").doc(actorUserId).get();
      if (memberSnap.exists) actorName = firstDefined(memberSnap.get("fullName"), actorName);
    } catch (err) {
      console.warn(`[audit] members lookup failed for ${actorUserId}: ${err.message}`);
    }
  }

  // الدور: مشرف منصّة؟
  try {
    const paSnap = await db().collection("platform_admins").doc(actorUserId).get();
    if (paSnap.exists && paSnap.get("status") === "active" &&
        (paSnap.get("role") === "system_owner" ||
         (paSnap.get("role") === "superAdmin" && paSnap.get("fullAccess") === true))) {
      actorRole = paSnap.get("role");
    }
  } catch (err) {
    console.warn(`[audit] platform_admins lookup failed for ${actorUserId}: ${err.message}`);
  }

  // الدور داخل المجلس
  if (actorRole === "unknown" && organizationId) {
    try {
      const membershipSnap = await db()
        .collection("organizations")
        .doc(organizationId)
        .collection("memberships")
        .doc(actorUserId)
        .get();
      if (membershipSnap.exists) {
        actorRole = firstDefined(membershipSnap.get("roleId"), actorRole) || actorRole;
        if (!actorName) actorName = firstDefined(membershipSnap.get("fullName"), actorName);
      }
    } catch (err) {
      console.warn(`[audit] membership lookup failed for ${actorUserId}: ${err.message}`);
    }
  }

  // احتياط: أدمن قديم
  if (actorRole === "unknown") {
    try {
      const memberSnap = await db().collection("members").doc(actorUserId).get();
      if (memberSnap.exists && memberSnap.get("isAdmin") === true) actorRole = "legacyAdmin";
    } catch (err) {
      // مُتجاهَل عمدًا
    }
  }

  return { actorUserId, actorName: actorName || "غير معروف", actorRole };
}

/**
 * يكتب سجل تدقيق واحد. معرّف المستند = معرّف الحدث لضمان idempotency
 * (إعادة تشغيل نفس الحدث لا تُنشئ سجلًا مكررًا).
 */
async function writeAudit(eventId, entry) {
  const { organizationId, action, targetId } = entry;
  if (!organizationId) {
    console.warn(`[audit] skipped: missing organizationId action=${action} target=${targetId}`);
    return;
  }
  const actor = await resolveActor(entry.actorUserId, organizationId);
  const record = {
    actorUserId: actor.actorUserId,
    actorName: actor.actorName,
    actorRole: actor.actorRole,
    action,
    targetType: entry.targetType,
    targetId: targetId || null,
    organizationId,
    oldValue: entry.oldValue === undefined ? null : entry.oldValue,
    newValue: entry.newValue === undefined ? null : entry.newValue,
    createdAt: FieldValue.serverTimestamp(),
    source: "cloud_function",
    platform: entry.platform || null,
  };
  const docId = eventId || db().collection("_").doc().id;
  await db()
    .collection("organizations")
    .doc(organizationId)
    .collection("audit_logs")
    .doc(docId)
    .set(record);
  console.log(`[audit] ${action} org=${organizationId} target=${targetId} actor=${actor.actorUserId}`);
}

function beforeAfter(event) {
  const before = event.data && event.data.before && event.data.before.exists
    ? event.data.before.data()
    : null;
  const after = event.data && event.data.after && event.data.after.exists
    ? event.data.after.data()
    : null;
  return { before, after };
}

// ── العضويات: إنشاء/تعديل/حذف + تغيير الدور والصلاحيات ───────────────────────
exports.auditMembershipWrite = onDocumentWritten(
  { document: "organizations/{organizationId}/memberships/{membershipId}", region: REGION },
  async (event) => {
    const { organizationId, membershipId } = event.params;
    if (membershipId === "_meta") return;
    const { before, after } = beforeAfter(event);
    const FIELDS = ["roleId", "status", "permissionsSnapshot", "memberNumber", "isPrimary"];

    if (!before && after) {
      return writeAudit(event.id, {
        organizationId,
        action: "membership.created",
        targetType: "membership",
        targetId: membershipId,
        actorUserId: firstDefined(after.approvedBy, after.invitedBy, after.updatedBy),
        oldValue: null,
        newValue: pick(after, FIELDS),
      });
    }

    if (before && !after) {
      return writeAudit(event.id, {
        organizationId,
        action: "membership.deleted",
        targetType: "membership",
        targetId: membershipId,
        actorUserId: firstDefined(before.removedBy, before.updatedBy),
        oldValue: pick(before, FIELDS),
        newValue: null,
      });
    }

    if (before && after) {
      const roleChanged =
        before.roleId !== after.roleId ||
        !equal(before.permissionsSnapshot, after.permissionsSnapshot);
      const statusChanged = before.status !== after.status;
      if (!roleChanged && !statusChanged) return; // تجاهل ضجيج (updatedAt/fcm...)

      let action = "membership.updated";
      if (roleChanged && !statusChanged) action = "membership.role_changed";
      else if (statusChanged && !roleChanged) action = "membership.status_changed";

      return writeAudit(event.id, {
        organizationId,
        action,
        targetType: "membership",
        targetId: membershipId,
        actorUserId: firstDefined(after.updatedBy, after.removedBy, after.approvedBy),
        oldValue: pick(before, FIELDS),
        newValue: pick(after, FIELDS),
      });
    }
  }
);

// ── الأدوار: تغيير الصلاحيات ─────────────────────────────────────────────────
exports.auditRoleWrite = onDocumentWritten(
  { document: "organizations/{organizationId}/roles/{roleId}", region: REGION },
  async (event) => {
    const { organizationId, roleId } = event.params;
    const { before, after } = beforeAfter(event);
    const FIELDS = ["permissions", "roleName", "priority"];

    if (!before && after) {
      return writeAudit(event.id, {
        organizationId,
        action: "role.created",
        targetType: "role",
        targetId: roleId,
        actorUserId: firstDefined(after.updatedBy, after.createdBy),
        oldValue: null,
        newValue: pick(after, FIELDS),
      });
    }
    if (before && !after) {
      return writeAudit(event.id, {
        organizationId,
        action: "role.deleted",
        targetType: "role",
        targetId: roleId,
        actorUserId: firstDefined(before.updatedBy),
        oldValue: pick(before, FIELDS),
        newValue: null,
      });
    }
    if (before && after) {
      if (equal(before.permissions, after.permissions)) return; // نهتم بتغيّر الصلاحيات فقط
      return writeAudit(event.id, {
        organizationId,
        action: "role.permissions_changed",
        targetType: "role",
        targetId: roleId,
        actorUserId: firstDefined(after.updatedBy),
        oldValue: { permissions: before.permissions || [] },
        newValue: { permissions: after.permissions || [] },
      });
    }
  }
);

// ── طلبات العضوية: تقديم/اعتماد/رفض/إلغاء ────────────────────────────────────
exports.auditMembershipRequestWrite = onDocumentWritten(
  { document: "organizations/{organizationId}/membership_requests/{requestId}", region: REGION },
  async (event) => {
    const { organizationId, requestId } = event.params;
    if (requestId === "_meta") return;
    const { before, after } = beforeAfter(event);
    const FIELDS = ["status", "requestedRole", "reviewedBy", "rejectionReason"];

    if (!before && after) {
      return writeAudit(event.id, {
        organizationId,
        action: "membership_request.submitted",
        targetType: "membership_request",
        targetId: requestId,
        actorUserId: firstDefined(after.userId),
        oldValue: null,
        newValue: pick(after, FIELDS),
      });
    }
    if (before && after) {
      if (before.status === after.status) return;
      const actionByStatus = {
        approved: "membership_request.approved",
        rejected: "membership_request.rejected",
        cancelled: "membership_request.cancelled",
        pending: "membership_request.reopened",
      };
      return writeAudit(event.id, {
        organizationId,
        action: actionByStatus[after.status] || "membership_request.updated",
        targetType: "membership_request",
        targetId: requestId,
        actorUserId: firstDefined(after.reviewedBy, after.cancelledBy, after.userId),
        oldValue: { status: before.status },
        newValue: pick(after, FIELDS),
      });
    }
  }
);

// ── الإيصالات/المعاملات المالية: رفع/اعتماد/رفض ──────────────────────────────
exports.auditTransactionWrite = onDocumentWritten(
  { document: "organizations/{organizationId}/transactions/{transactionId}", region: REGION },
  async (event) => {
    const { organizationId, transactionId } = event.params;
    if (transactionId === "_meta") return;
    const { before, after } = beforeAfter(event);
    const FIELDS = [
      "status", "reviewStatus", "amountDeclaredBaisa",
      "allocationTotalBaisa", "differenceBaisa", "paymentScope",
      "reviewedBy", "rejectionReason", "payerMembershipId",
    ];

    if (!before && after) {
      return writeAudit(event.id, {
        organizationId,
        action: "receipt.submitted",
        targetType: "transaction",
        targetId: transactionId,
        actorUserId: firstDefined(after.payerUserId, after.uploadedByUserId, after.userId),
        oldValue: null,
        newValue: pick(after, FIELDS),
        platform: after.platform || null,
      });
    }
    if (before && after) {
      if (before.reviewStatus === after.reviewStatus) return;
      const actionByStatus = {
        approved: "receipt.approved",
        rejected: "receipt.rejected",
      };
      return writeAudit(event.id, {
        organizationId,
        action: actionByStatus[after.reviewStatus] || "receipt.reviewed",
        targetType: "transaction",
        targetId: transactionId,
        actorUserId: firstDefined(after.reviewedBy),
        oldValue: { reviewStatus: before.reviewStatus, status: before.status },
        newValue: pick(after, FIELDS),
      });
    }
  }
);

// ── الحجوزات: إنشاء/اعتماد/رفض ───────────────────────────────────────────────
exports.auditBookingWrite = onDocumentWritten(
  { document: "organizations/{organizationId}/bookings/{bookingId}", region: REGION },
  async (event) => {
    const { organizationId, bookingId } = event.params;
    if (bookingId === "_meta") return;
    const { before, after } = beforeAfter(event);
    const FIELDS = [
      "status", "approvedBy", "rejectedBy", "resourceId",
      "startAt", "endAt", "purpose",
    ];

    if (!before && after) {
      return writeAudit(event.id, {
        organizationId,
        action: "booking.created",
        targetType: "booking",
        targetId: bookingId,
        actorUserId: firstDefined(after.userId, after.membershipId),
        oldValue: null,
        newValue: pick(after, FIELDS),
      });
    }
    if (before && after) {
      if (before.status === after.status) return;
      const actionByStatus = {
        approved: "booking.approved",
        rejected: "booking.rejected",
        cancelled: "booking.cancelled",
      };
      return writeAudit(event.id, {
        organizationId,
        action: actionByStatus[after.status] || "booking.updated",
        targetType: "booking",
        targetId: bookingId,
        actorUserId: firstDefined(after.approvedBy, after.rejectedBy, after.cancelledBy),
        oldValue: { status: before.status },
        newValue: pick(after, FIELDS),
      });
    }
  }
);

// ── إعدادات المجلس ───────────────────────────────────────────────────────────
exports.auditSettingsWrite = onDocumentWritten(
  { document: "organizations/{organizationId}/settings/{settingId}", region: REGION },
  async (event) => {
    const { organizationId, settingId } = event.params;
    const { before, after } = beforeAfter(event);

    const strip = (data) => {
      if (!data) return null;
      const clone = { ...data };
      delete clone.updatedAt;
      return clone;
    };
    const beforeClean = strip(before);
    const afterClean = strip(after);

    if (!before && after) {
      return writeAudit(event.id, {
        organizationId,
        action: "settings.created",
        targetType: "settings",
        targetId: settingId,
        actorUserId: firstDefined(after.updatedBy, after.createdBy),
        oldValue: null,
        newValue: afterClean,
      });
    }
    if (before && after) {
      if (equal(beforeClean, afterClean)) return; // تغيّر updatedAt فقط
      return writeAudit(event.id, {
        organizationId,
        action: "settings.updated",
        targetType: "settings",
        targetId: settingId,
        actorUserId: firstDefined(after.updatedBy),
        oldValue: beforeClean,
        newValue: afterClean,
      });
    }
  }
);

// ── الملف المالي (بيانات البنك) — عملية مالية حسّاسة ─────────────────────────
// لا نخزّن القيم السرّية (رقم الحساب/IBAN) في السجل، بل قائمة الحقول المتغيّرة
// وحالة التفعيل فقط، حفاظًا على السرّية مع بقاء أثر التغيير.
exports.auditFinancialProfileWrite = onDocumentWritten(
  { document: "organizations/{organizationId}/financial_profile/{profileId}", region: REGION },
  async (event) => {
    const { organizationId, profileId } = event.params;
    const { before, after } = beforeAfter(event);
    if (!after) return; // لا حذف متوقع

    const trackedKeys = [
      "bankName", "accountName", "accountNumber", "iban", "swiftCode", "enabled",
    ];
    const changedFields = [];
    for (const key of trackedKeys) {
      if (!before || before[key] !== after[key]) changedFields.push(key);
    }
    if (before && changedFields.length === 0) return;

    return writeAudit(event.id, {
      organizationId,
      action: before ? "financial_profile.updated" : "financial_profile.created",
      targetType: "financial_profile",
      targetId: profileId,
      actorUserId: firstDefined(after.updatedBy),
      oldValue: before ? { enabled: before.enabled === true } : null,
      newValue: { enabled: after.enabled === true, changedFields },
    });
  }
);

// ── المجلس نفسه: إنشاء/تعديل/أرشفة ──────────────────────────────────────────
exports.auditOrganizationWrite = onDocumentWritten(
  { document: "organizations/{organizationId}", region: REGION },
  async (event) => {
    const { organizationId } = event.params;
    const { before, after } = beforeAfter(event);
    const FIELDS = ["status", "officialNameArabic", "shortName", "joinQrEnabled"];

    if (!before && after) {
      return writeAudit(event.id, {
        organizationId,
        action: "organization.created",
        targetType: "organization",
        targetId: organizationId,
        actorUserId: firstDefined(after.createdBy),
        oldValue: null,
        newValue: pick(after, FIELDS),
      });
    }
    if (before && !after) {
      return writeAudit(event.id, {
        organizationId,
        action: "organization.deleted",
        targetType: "organization",
        targetId: organizationId,
        actorUserId: firstDefined(before.updatedBy, before.createdBy),
        oldValue: pick(before, FIELDS),
        newValue: null,
      });
    }
    if (before && after) {
      const statusChanged = before.status !== after.status;
      const otherChanged = !equal(pick(before, FIELDS), pick(after, FIELDS));
      if (!statusChanged && !otherChanged) return;
      return writeAudit(event.id, {
        organizationId,
        action: statusChanged ? "organization.status_changed" : "organization.updated",
        targetType: "organization",
        targetId: organizationId,
        actorUserId: firstDefined(after.updatedBy, after.createdBy),
        oldValue: pick(before, FIELDS),
        newValue: pick(after, FIELDS),
      });
    }
  }
);
