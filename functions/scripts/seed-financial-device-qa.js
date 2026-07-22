"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const admin = require("firebase-admin");
const {
  canonicalChargeKey,
  subscriptionPeriod,
} = require("../financial_core");

const expectedProjectId = "demo-financial-prestaging";
const productionProjectId = "alrahmat-console";
const organizationId = "qa_financial_council";
const planId = "qa_monthly_12500";

function formatOmrSystem(amountBaisa) {
  return `${Math.floor(amountBaisa / 1000)}.${String(amountBaisa % 1000).padStart(3, "0")} ر.ع.`;
}

function requireEnvironment() {
  const projectId = process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT_ID;
  const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
  const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const storageHost = process.env.FIREBASE_STORAGE_EMULATOR_HOST;
  if (projectId === productionProjectId || projectId !== expectedProjectId) {
    throw new Error(`Refusing projectId=${projectId || "missing"}. Expected ${expectedProjectId}.`);
  }
  if (firestoreHost !== "127.0.0.1:8080" || authHost !== "127.0.0.1:9099" ||
      storageHost !== "127.0.0.1:9199") {
    throw new Error("Refusing to run without the approved loopback Firestore, Auth, and Storage Emulator hosts.");
  }
  const currentUid = String(process.env.QA_CURRENT_UID || "").trim();
  const currentPassword = String(process.env.QA_CURRENT_PASSWORD || "");
  const reviewerPassword = String(process.env.QA_REVIEWER_PASSWORD || "");
  const guestPassword = String(process.env.QA_GUEST_PASSWORD || "");
  if (!currentUid) throw new Error("QA_CURRENT_UID is required.");
  if (currentPassword.length < 6 || reviewerPassword.length < 6 || guestPassword.length < 6) {
    throw new Error("QA passwords must be provided at runtime and contain at least 6 characters.");
  }
  return { projectId, currentUid, currentPassword, reviewerPassword, guestPassword };
}

const { projectId, currentUid, currentPassword, reviewerPassword, guestPassword } = requireEnvironment();
const emulatorCredential = {
  getAccessToken: async () => ({ access_token: "owner", expires_in: 3600 }),
};
const { privateKey } = crypto.generateKeyPairSync("rsa", { modulusLength: 2048 });
const firestoreCredential = admin.credential.cert({
  projectId,
  clientEmail: `qa-emulator@${projectId}.iam.gserviceaccount.com`,
  privateKey: privateKey.export({ type: "pkcs8", format: "pem" }),
});
const authApp = admin.initializeApp({ projectId, credential: emulatorCredential }, "qa-auth-emulator");
const firestoreApp = admin.initializeApp({
  projectId,
  credential: firestoreCredential,
  storageBucket: `${projectId}.appspot.com`,
}, "qa-firestore-emulator");
const auth = authApp.auth();
const firestore = firestoreApp.firestore();
const storage = firestoreApp.storage().bucket();
firestore.settings({ ignoreUndefinedProperties: true });
const { FieldValue, Timestamp } = admin.firestore;

const reviewer = {
  uid: "qa-financial-reviewer",
  phone: "00000001",
  email: "96800000001@alrahmat.local",
  displayName: "مراجع مالي تجريبي",
};
const guest = {
  uid: "qa-booking-guest",
  phone: "00000002",
  email: "96800000002@alrahmat.local",
  displayName: "ضيف حجز تجريبي",
};
const currentMember = {
  uid: currentUid,
  phone: "00000000",
  email: "96800000000@alrahmat.local",
  displayName: "عضو الاختبار المالي",
};
const beneficiaries = [
  { uid: "qa-beneficiary-ahmed", fullName: "أحمد سالم", memberNumber: "QA-201", amountBaisa: 12500 },
  { uid: "qa-beneficiary-mohammed", fullName: "محمد علي", memberNumber: "QA-202", amountBaisa: 8000 },
  { uid: "qa-beneficiary-fatima", fullName: "فاطمة عبدالله", memberNumber: "QA-203", amountBaisa: 6250 },
];

async function upsertAuthUser({ uid, email, displayName, password }) {
  try {
    await auth.getUser(uid);
    await auth.updateUser(uid, { email, displayName, password, disabled: false });
    return "updated";
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
    await auth.createUser({ uid, email, displayName, password, emailVerified: true, disabled: false });
    return "created";
  }
}

function profile(uid, fullName, memberNumber, phone = "") {
  return {
    userId: uid,
    fullName,
    civilId: "",
    phone,
    email: "",
    address: "",
    photoUrl: null,
    qaOnly: true,
    updatedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
    memberNumber,
  };
}

function legacyMember(uid, fullName, memberNumber, phone = "") {
  return {
    userId: uid,
    fullName,
    civilId: "",
    phone,
    memberNumber,
    status: "active",
    isAdmin: false,
    joinDate: FieldValue.serverTimestamp(),
    fcmToken: null,
    qaOnly: true,
  };
}

function membership(uid, memberNumber, roleId = "member", permissionsSnapshot = []) {
  return {
    userId: uid,
    organizationId,
    memberNumber,
    roleId,
    role: roleId,
    status: "active",
    joinedAt: FieldValue.serverTimestamp(),
    approvedBy: reviewer.uid,
    approvedAt: FieldValue.serverTimestamp(),
    isPrimary: false,
    isPrimaryOwner: false,
    permissionsSnapshot,
    joinedReason: "financialDeviceQaSeed",
    invitedBy: reviewer.uid,
    leftReason: null,
    qaOnly: true,
  };
}

function role(roleId, arabicName, englishName, permissions, priority, color, icon) {
  return {
    roleId,
    arabicName,
    englishName,
    roleName: { ar: arabicName, en: englishName },
    description: { ar: `دور اختبار مطابق للدور النظامي: ${arabicName}`, en: `QA system role: ${englishName}` },
    permissions,
    systemRole: true,
    isSystemRole: true,
    color,
    icon,
    priority,
    qaOnly: true,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function charge({ membershipId, userId, chargeType, sourceId, periodKey = null, titleArabic, descriptionArabic, amountDueBaisa, amountPaidBaisa = 0, dueDate }) {
  const chargeId = canonicalChargeKey({
    organizationId,
    membershipId,
    chargeType,
    periodKey,
    sourceId,
  });
  return {
    chargeId,
    data: {
      chargeId,
      organizationId,
      accountType: "member",
      membershipId,
      userId,
      chargeType,
      sourceId,
      periodKey,
      idempotencyKey: chargeId,
      titleArabic,
      descriptionArabic,
      amountDueBaisa,
      amountPaidBaisa,
      balanceBaisa: amountDueBaisa - amountPaidBaisa,
      dueDate: Timestamp.fromDate(dueDate),
      status: amountPaidBaisa > 0 ? "partial" : "unpaid",
      lastTransactionId: null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      createdBy: "financial-device-qa-seed",
      qaOnly: true,
    },
  };
}

async function waitForDocument(reference, predicate, label, timeoutMs = 20000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const snapshot = await reference.get();
    if (snapshot.exists && predicate(snapshot)) return snapshot;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Timed out waiting for ${label}.`);
}

async function seed() {
  const currentAuthResult = await upsertAuthUser({ ...currentMember, password: currentPassword });
  const currentAuthUser = await auth.getUser(currentUid);
  const reviewerAuthResult = await upsertAuthUser({ ...reviewer, password: reviewerPassword });
  const guestAuthResult = await upsertAuthUser({ ...guest, password: guestPassword });
  const organization = firestore.collection("organizations").doc(organizationId);
  const now = new Date();
  const dueDate = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
  const bookingDate = Timestamp.fromDate(new Date(now.getTime() + 14 * 24 * 60 * 60 * 1000));
  const subscription = subscriptionPeriod("monthly", now);

  const batch = firestore.batch();
  batch.set(organization, {
    organizationId,
    officialNameArabic: "مجلس الاختبار المالي",
    officialNameEnglish: "Financial QA Council",
    shortName: "الاختبار المالي",
    status: "active",
    profilePublished: false,
    schemaVersion: 1,
    navigationEnabled: true,
    primaryColor: "#FF5722",
    secondaryColor: "#FF8A65",
    description: { ar: "مجلس وهمي لاختبارات النظام المالي داخل Firebase Emulator فقط.", en: "Emulator-only financial QA council." },
    logoUrl: null,
    qaOnly: true,
    createdBy: reviewer.uid,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  batch.set(organization.collection("settings").doc("organization"), {
    locale: "ar",
    timezone: "Asia/Muscat",
    currency: "OMR",
    countryCode: "OM",
    navigationEnabled: true,
    allowHallRental: true,
    qaOnly: true,
    updatedBy: reviewer.uid,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  batch.set(organization.collection("roles").doc("member"), role(
    "member", "عضو", "Member",
    ["profile.read", "payments.read", "rentals.create", "bookings.read", "bookings.create"],
    10, "#707070", "person"
  ), { merge: true });
  batch.set(organization.collection("roles").doc("financialReviewer"), role(
    "financialReviewer", "المراجع المالي", "Financial Reviewer",
    ["transactions.review", "reports.view", "receipts.review", "payments.approve", "payments.reject", "payments.read"],
    60, "#2878B5", "fact_check"
  ), { merge: true });
  batch.set(organization.collection("financial_settings").doc("main"), {
    organizationId,
    currency: "OMR",
    feeMode: "subscriptionAndBooking",
    receiptPaymentsEnabled: true,
    onlinePaymentsEnabled: false,
    onlinePaymentProvider: null,
    allowMonthlyPlans: true,
    allowAnnualPlans: true,
    memberBookingFeeBaisa: 5000,
    nonMemberBookingFeeBaisa: 7500,
    eventBookingFeeBaisa: 3000,
    qaOnly: true,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: reviewer.uid,
  }, { merge: true });
  batch.set(organization.collection("subscription_plans").doc(planId), {
    planId,
    organizationId,
    nameArabic: "الباقة الشهرية التجريبية",
    descriptionArabic: "اشتراك شهري وهمي لاختبارات الجهاز.",
    billingCycle: "monthly",
    amountBaisa: 12500,
    active: true,
    startDate: FieldValue.serverTimestamp(),
    endDate: null,
    qaOnly: true,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    createdBy: reviewer.uid,
    updatedBy: reviewer.uid,
  }, { merge: true });

  const currentProfile = profile(currentUid, "عضو الاختبار المالي", "QA-100", currentMember.phone);
  batch.set(firestore.collection("users").doc(currentUid), currentProfile, { merge: true });
  batch.set(firestore.collection("members").doc(currentUid), legacyMember(currentUid, "عضو الاختبار المالي", "QA-100", currentMember.phone), { merge: true });
  batch.set(organization.collection("memberships").doc(currentUid), membership(currentUid, "QA-100"), { merge: true });

  batch.set(firestore.collection("users").doc(reviewer.uid), profile(reviewer.uid, reviewer.displayName, "QA-900", "+96800000001"), { merge: true });
  batch.set(firestore.collection("members").doc(reviewer.uid), legacyMember(reviewer.uid, reviewer.displayName, "QA-900", "+96800000001"), { merge: true });
  batch.set(organization.collection("memberships").doc(reviewer.uid), membership(
    reviewer.uid,
    "QA-900",
    "financialReviewer",
    ["transactions.review", "reports.view", "receipts.review", "payments.approve", "payments.reject", "payments.read"]
  ), { merge: true });

  batch.set(firestore.collection("users").doc(guest.uid), profile(guest.uid, guest.displayName, "", "+96800000002"), { merge: true });
  batch.set(firestore.collection("members").doc(guest.uid), legacyMember(guest.uid, guest.displayName, "", "+96800000002"), { merge: true });

  beneficiaries.forEach((beneficiary) => {
    batch.set(firestore.collection("users").doc(beneficiary.uid), profile(beneficiary.uid, beneficiary.fullName, beneficiary.memberNumber), { merge: true });
    batch.set(firestore.collection("members").doc(beneficiary.uid), legacyMember(beneficiary.uid, beneficiary.fullName, beneficiary.memberNumber), { merge: true });
    batch.set(organization.collection("memberships").doc(beneficiary.uid), membership(beneficiary.uid, beneficiary.memberNumber), { merge: true });
  });

  batch.set(organization.collection("member_accounts").doc(currentUid), {
    organizationId,
    membershipId: currentUid,
    userId: currentUid,
    planId,
    planNameArabic: "الباقة الشهرية التجريبية",
    subscriptionStatus: "active",
    subscriptionStartDate: FieldValue.serverTimestamp(),
    subscriptionEndDate: null,
    feeOverrideType: "default",
    customAmountBaisa: null,
    exemptionReason: null,
    qaOnly: true,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: reviewer.uid,
  }, { merge: true });

  const currentSubscriptionCharge = charge({
    membershipId: currentUid,
    userId: currentUid,
    chargeType: "subscription",
    sourceId: planId,
    periodKey: subscription.periodKey,
    titleArabic: `الباقة الشهرية التجريبية - ${subscription.periodKey}`,
    descriptionArabic: "رسم اشتراك شهري غير مدفوع.",
    amountDueBaisa: 12500,
    dueDate: subscription.dueDate,
  });
  const currentPartialCharge = charge({
    membershipId: currentUid,
    userId: currentUid,
    chargeType: "other",
    sourceId: "qa-partial-additional-v1",
    titleArabic: "رسم تجريبي مسدد جزئيًا",
    descriptionArabic: "رسم إضافي لاختبار حالة السداد الجزئي.",
    amountDueBaisa: 12500,
    amountPaidBaisa: 5000,
    dueDate,
  });
  const receiptPreviewCharge = charge({
    membershipId: currentUid,
    userId: currentUid,
    chargeType: "other",
    sourceId: "qa-reviewer-pdf-preview-v1",
    titleArabic: "رسم معاينة إيصال PDF",
    descriptionArabic: "رسم مخصص لاختبار فتح الإيصال من حساب المراجع.",
    amountDueBaisa: 1000,
    dueDate,
  });
  batch.set(organization.collection("charges").doc(currentSubscriptionCharge.chargeId), currentSubscriptionCharge.data, { merge: true });
  batch.set(organization.collection("charges").doc(currentPartialCharge.chargeId), currentPartialCharge.data, { merge: true });
  batch.set(organization.collection("charges").doc(receiptPreviewCharge.chargeId), receiptPreviewCharge.data, { merge: true });
  beneficiaries.forEach((beneficiary) => {
    const beneficiaryCharge = charge({
      membershipId: beneficiary.uid,
      userId: beneficiary.uid,
      chargeType: "other",
      sourceId: `qa-open-${beneficiary.uid}-v1`,
      titleArabic: `رسم مفتوح - ${beneficiary.fullName}`,
      descriptionArabic: "رسم وهمي لاختبار الدفع عن عضو آخر.",
      amountDueBaisa: beneficiary.amountBaisa,
      dueDate,
    });
    batch.set(organization.collection("charges").doc(beneficiaryCharge.chargeId), beneficiaryCharge.data, { merge: true });
  });
  [5000, 8000, 12500, 7500].forEach((amountBaisa) => {
    const notificationId = `qa_omr_display_${amountBaisa}`;
    const bodyTemplate = "مبلغ تجريبي للتحقق من عرض الريال: {amount}";
    batch.set(
      firestore.collection("users").doc(currentUid).collection("notifications").doc(notificationId),
      {
        notificationId,
        userId: currentUid,
        organizationId,
        title: "اختبار عرض الريال العُماني",
        body: bodyTemplate.replace("{amount}", formatOmrSystem(amountBaisa)),
        bodyTemplate,
        amountBaisa,
        currencyCode: "OMR",
        type: "financialCurrencyQa",
        relatedEntityType: "financialQa",
        relatedEntityId: notificationId,
        status: "unread",
        readAt: null,
        createdByUserId: reviewer.uid,
        qaOnly: true,
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });
  await batch.commit();

  const previewPdfPath = String(process.env.QA_RECEIPT_PDF_PATH || "").trim();
  if (previewPdfPath) {
    const previewBytes = fs.readFileSync(previewPdfPath);
    if (previewBytes.length <= 0 || previewBytes.length > 10 * 1024 * 1024 ||
        previewBytes.subarray(0, 5).toString("ascii") !== "%PDF-") {
      throw new Error("QA_RECEIPT_PDF_PATH must be a valid PDF no larger than 10 MiB.");
    }
    const transactionId = "85ec044c-fc43-4c6a-a793-496c5edd2fea";
    const fileName = "qa-receipt.pdf";
    const storagePath = `organizations/${organizationId}/members/${currentUid}/receipts/${transactionId}/${fileName}`;
    await storage.file(storagePath).save(previewBytes, {
      resumable: false,
      metadata: {
        contentType: "application/pdf",
        metadata: {
          temporaryUpload: "true",
          receiptId: transactionId,
          uploaderUid: currentUid,
          organizationId,
          uploadedAt: new Date().toISOString(),
          qaOnly: "true",
        },
      },
    });
    const nowTimestamp = Timestamp.now();
    const expiresAt = Timestamp.fromMillis(nowTimestamp.toMillis() + 48 * 60 * 60 * 1000);
    const transaction = organization.collection("transactions").doc(transactionId);
    const lock = organization.collection("pending_receipt_locks")
      .doc(`${currentUid}_${receiptPreviewCharge.chargeId}`);
    await firestore.runTransaction(async (firestoreTransaction) => {
      firestoreTransaction.set(transaction, {
        transactionId,
        organizationId,
        payerUserId: currentUid,
        payerMembershipId: currentUid,
        payerName: currentMember.displayName,
        payerMemberNumber: "QA-100",
        paymentScope: "self",
        amountDeclaredBaisa: 1000,
        allocationTotalBaisa: 1000,
        differenceBaisa: 0,
        receiptUrl: "emulator-only",
        receiptStoragePath: storagePath,
        fileName,
        fileType: "application/pdf",
        reviewStatus: "pending",
        status: "pendingReview",
        currentStatus: "submitted",
        submittedAt: nowTimestamp,
        expiresAt,
        reviewedAt: null,
        reviewedBy: null,
        rejectionReason: null,
        allocations: [{
          beneficiaryUserId: currentUid,
          beneficiaryMembershipId: currentUid,
          beneficiaryName: currentMember.displayName,
          chargeId: receiptPreviewCharge.chargeId,
          chargeTitle: receiptPreviewCharge.data.titleArabic,
          amountAllocatedBaisa: 1000,
          balanceBeforeBaisa: 1000,
          statusBefore: "unpaid",
        }],
        beneficiaryMembershipIds: [currentUid],
        beneficiaryUserIds: [currentUid],
        allocationChargeIds: [receiptPreviewCharge.chargeId],
        qaOnly: true,
        createdAt: nowTimestamp,
        updatedAt: nowTimestamp,
      }, { merge: true });
      firestoreTransaction.set(lock, {
        payerUserId: currentUid,
        chargeId: receiptPreviewCharge.chargeId,
        transactionId,
        expiresAt,
        createdAt: nowTimestamp,
        qaOnly: true,
      }, { merge: true });
    });
  }

  const memberBooking = organization.collection("bookings").doc("qa-member-approved-booking");
  const guestBooking = organization.collection("bookings").doc("qa-guest-approved-booking");
  const bookingRows = [
    [memberBooking, {
      bookingId: memberBooking.id,
      organizationId,
      userId: currentUid,
      membershipId: currentUid,
      requesterName: "عضو الاختبار المالي",
      requesterPhone: "+96800000000",
      bookingDate,
      startTime: "18:00",
      endTime: "21:00",
      occasionType: "مناسبة عائلية تجريبية",
      notes: "حجز وهمي لمسار رسوم حجز العضو.",
    }],
    [guestBooking, {
      bookingId: guestBooking.id,
      organizationId,
      userId: guest.uid,
      requesterName: guest.displayName,
      requesterPhone: "+96800000002",
      bookingDate,
      startTime: "09:00",
      endTime: "12:00",
      occasionType: "حجز ضيف تجريبي",
      notes: "حجز وهمي لمسار رسوم غير العضو.",
    }],
  ];
  for (const [reference, data] of bookingRows) {
    const existing = await reference.get();
    if (!existing.exists) {
      await reference.set({
        ...data,
        status: "pending",
        qaOnly: true,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    const current = await reference.get();
    if (current.get("status") === "pending") {
      await reference.update({
        status: "approved",
        approvedBy: reviewer.uid,
        approvedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  }

  await Promise.all([
    ...[currentUid, reviewer.uid, ...beneficiaries.map((item) => item.uid)].map((uid) =>
      waitForDocument(organization.collection("member_directory").doc(uid), () => true, `member directory ${uid}`)
    ),
    waitForDocument(memberBooking, (snapshot) => Boolean(snapshot.get("financialChargeId")), "member booking financial charge"),
    waitForDocument(guestBooking, (snapshot) => Boolean(snapshot.get("financialChargeId")), "guest booking financial charge"),
  ]);

  const chargeSnapshot = await organization.collection("charges").get();
  const qaCharges = chargeSnapshot.docs.filter((document) => document.get("qaOnly") === true || [
    memberBooking.id,
    guestBooking.id,
  ].includes(document.get("bookingId")));
  console.log(JSON.stringify({
    status: "seeded",
    projectId,
    currentUid: currentAuthUser.uid,
    currentAuthResult,
    organizationId,
    organizationName: "مجلس الاختبار المالي",
    reviewer: { uid: reviewer.uid, phone: reviewer.phone, authResult: reviewerAuthResult },
    guest: { uid: guest.uid, phone: guest.phone, authResult: guestAuthResult },
    memberCount: 5,
    qaChargeCount: qaCharges.length,
    currentChargeIds: [currentSubscriptionCharge.chargeId, currentPartialCharge.chargeId],
  }, null, 2));
}

seed().then(() => process.exit(0)).catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
