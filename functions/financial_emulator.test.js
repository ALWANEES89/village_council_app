const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");
const { after, before, beforeEach } = test;
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const { collection, deleteDoc, doc, getDoc, getDocs, orderBy, query, setDoc, updateDoc, where } = require("firebase/firestore");
const { getBytes, ref, uploadBytes } = require("firebase/storage");
const admin = require("firebase-admin");
const { Timestamp } = require("firebase-admin/firestore");

const projectId = process.env.GCLOUD_PROJECT || "demo-financial-fix";
if (projectId === "alrahmat-console" || !projectId.startsWith("demo-")) {
  throw new Error("Financial Emulator QA requires a demo-* Firebase project.");
}
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
  throw new Error("Financial Emulator QA requires Firestore and Storage Emulators.");
}
if (admin.apps.length === 0) {
  admin.initializeApp({ projectId, storageBucket: `${projectId}.appspot.com` });
}
const {
  bookingFinancialLifecycleHandler,
  cleanupOrphanReceiptsHandler,
  deliverFinancialNotificationOutboxHandler,
  ensureSubscriptionCharge,
  financialRateLimitId,
  generateSubscriptionChargesHandler,
  getBookingAvailabilityHandler,
  getFinancialReceiptDownloadUrlHandler,
  getGuestBookingChargeHandler,
  getPayableChargesHandler,
  listFinancialMembersHandler,
  markFinancialChargesOverdueHandler,
  requestBookingCancellationHandler,
  reviewFinancialReceiptHandler,
  reviewBookingCancellationHandler,
  searchCouncilMembersHandler,
  readFinancialReceiptFromEmulator,
  submitGuestBookingReceiptHandler,
  submitFinancialReceiptHandler,
} = require("./financial")._test;
const {
  bootstrapOrganizationHandler,
  createBookingHandler,
  repairOrganizationStructureHandler,
  reviewBookingHandler,
  syncMembershipAccessHandler,
  transferPrimaryCouncilOwnershipHandler,
} = require("./production_security")._test;
const { onNotificationCreatedHandler } = require("./notifications")._test;

let environment;

function enabledScheduleEnvironment(taskKey) {
  return {
    FINANCIAL_SCHEDULES_ENABLED: "true",
    [taskKey]: "true",
    FINANCIAL_SCHEDULE_DRY_RUN: "false",
  };
}

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-financial-fix",
    firestore: { rules: fs.readFileSync(path.join(__dirname, "..", "firestore.rules"), "utf8") },
    storage: { rules: fs.readFileSync(path.join(__dirname, "..", "storage.rules"), "utf8") },
  });
});

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.clearStorage();
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "organizations/o1/memberships/member"), {
      organizationId: "o1", userId: "member", status: "active", roleId: "member", permissionsSnapshot: [],
    });
    await setDoc(doc(db, "organizations/o1/memberships/finance"), {
      organizationId: "o1", userId: "finance", status: "active", roleId: "financialManager", permissionsSnapshot: ["payments.manage", "bookings.manage"],
    });
    await setDoc(doc(db, "organizations/o1/memberships/finance2"), {
      organizationId: "o1", userId: "finance2", status: "active", roleId: "financialReviewer", permissionsSnapshot: ["receipts.review", "bookings.manage"],
    });
    await setDoc(doc(db, "organizations/o1/memberships/reviewer-membership-42"), {
      organizationId: "o1", userId: "reviewer-different", status: "active",
      roleId: "financialReviewer", permissionsSnapshot: ["receipts.review"],
    });
    await setDoc(doc(db, "organizations/o1/member_access/reviewer-different"), {
      organizationId: "o1", membershipId: "reviewer-membership-42",
      userId: "reviewer-different", status: "active", roleId: "financialReviewer",
      permissionsSnapshot: ["receipts.review"], isPrimaryOwner: false,
    });
    await setDoc(doc(db, "organizations/o1/memberships/legacy-owner-membership"), {
      organizationId: "o1", userId: "legacy-owner", status: "active",
      roleId: "owner", permissionsSnapshot: ["fullAccess"], isPrimaryOwner: false,
    });
    await setDoc(doc(db, "organizations/o1/member_access/legacy-owner"), {
      organizationId: "o1", membershipId: "legacy-owner-membership",
      userId: "legacy-owner", status: "active", roleId: "owner",
      permissionsSnapshot: ["fullAccess"], isPrimaryOwner: true,
    });
    await setDoc(doc(db, "organizations/o1/memberships/beneficiary"), {
      organizationId: "o1", userId: "beneficiary", status: "active", roleId: "member", permissionsSnapshot: [], memberNumber: "2",
    });
    await setDoc(doc(db, "organizations/o2/memberships/outsider"), {
      organizationId: "o2", userId: "outsider", status: "active", roleId: "member", permissionsSnapshot: [],
    });
    await setDoc(doc(db, "platform_admins/system-owner"), {
      role: "system_owner", status: "active", fullAccess: true,
    });
    await setDoc(doc(db, "organizations/o1/member_directory/member"), {
      membershipId: "member", userId: "member", fullName: "Member", memberNumber: "1", active: true,
      searchNameNormalized: "member", searchPrefixes: ["mem"],
    });
    await setDoc(doc(db, "organizations/o1/member_directory/beneficiary"), {
      membershipId: "beneficiary", userId: "beneficiary", fullName: "Beneficiary", memberNumber: "2", active: true,
      searchNameNormalized: "beneficiary", searchPrefixes: ["ben"],
    });
    for (let index = 0; index < 12; index += 1) {
      await setDoc(doc(db, `organizations/o1/member_directory/search-${index}`), {
        membershipId: `search-${index}`, userId: `search-user-${index}`,
        fullName: `Member ${index}`, memberNumber: String(100 + index), active: true,
        searchNameNormalized: `member ${index}`, searchPrefixes: ["mem", "memb", "membe", "member"],
      });
    }
    await setDoc(doc(db, "users/member"), { fullName: "Payer" });
    await setDoc(doc(db, "users/beneficiary"), { fullName: "Beneficiary" });
    await setDoc(doc(db, "organizations/o1/financial_settings/main"), {
      organizationId: "o1", currency: "OMR", feeMode: "booking",
      memberBookingFeeBaisa: 2500, nonMemberBookingFeeBaisa: 4000,
      eventBookingFeeBaisa: 0, receiptPaymentsEnabled: true,
      onlinePaymentsEnabled: false, onlinePaymentProvider: null,
    });
    await setDoc(doc(db, "organizations/o1/financial_profile/banking"), {
      organizationId: "o1", enabled: true, bankName: "Test Bank",
      accountName: "Private", accountNumber: "TEST-ONLY", iban: "TEST-ONLY",
    });
    await setDoc(doc(db, "organizations/o2/financial_profile/banking"), {
      organizationId: "o2", enabled: true, bankName: "Other Test Bank",
    });
    for (let index = 0; index < 30; index += 1) {
      const membershipId = index === 0 ? "member" : `other-${index}`;
      await setDoc(doc(db, `organizations/o1/charges/c${index}`), {
        chargeId: `c${index}`, organizationId: "o1", membershipId,
        userId: membershipId, chargeType: "subscription", amountDueBaisa: 1000,
        amountPaidBaisa: 0, balanceBaisa: 1000, status: "unpaid",
      });
    }
    await setDoc(doc(db, "organizations/o1/charges/b1"), {
      chargeId: "b1", organizationId: "o1", membershipId: "beneficiary",
      userId: "beneficiary", chargeType: "subscription", amountDueBaisa: 1000,
      amountPaidBaisa: 0, balanceBaisa: 1000, status: "unpaid", titleArabic: "Fee",
    });
  });
});

after(async () => {
  if (environment) await environment.cleanup();
});

test("member reads only own charge and cannot list the directory", async () => {
  const db = environment.authenticatedContext("member").firestore();
  await assertSucceeds(getDoc(doc(db, "organizations/o1/charges/c0")));
  await assertFails(getDoc(doc(db, "organizations/o1/charges/c1")));
  await assertFails(getDocs(collection(db, "organizations/o1/member_directory")));
  await assertFails(getDoc(doc(db, "organizations/o1/member_directory/member")));
});

test("finance manager can list many council charges but another council cannot", async () => {
  const financeDb = environment.authenticatedContext("finance").firestore();
  const result = await assertSucceeds(getDocs(collection(financeDb, "organizations/o1/charges")));
  if (result.size !== 31) throw new Error(`Expected 31 charges, received ${result.size}.`);
  const outsiderDb = environment.authenticatedContext("outsider").firestore();
  await assertFails(getDocs(query(collection(outsiderDb, "organizations/o1/charges"), where("membershipId", "==", "member"))));
  const ownerDb = environment.authenticatedContext("system-owner").firestore();
  await assertSucceeds(getDocs(collection(ownerDb, "organizations/o1/charges")));
});

test("financial reviewers can list pending council receipts", async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    await setDoc(doc(database, "organizations/o1/transactions/pending-receipt"), {
      organizationId: "o1",
      transactionId: "pending-receipt",
      payerUserId: "member",
      payerMembershipId: "member",
      reviewStatus: "pending",
      status: "pendingReview",
      submittedAt: new Date(),
    });
  });
  const reviewerDb = environment.authenticatedContext("finance2").firestore();
  await assertSucceeds(getDocs(query(
    collection(reviewerDb, "organizations/o1/transactions"),
    where("reviewStatus", "==", "pending"),
    orderBy("submittedAt", "desc")
  )));
});

test("notification rules deny all client creates and permit read-state updates only", async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/member/notifications/server-notification"), {
      notificationId: "server-notification", userId: "member", organizationId: "o1",
      title: "Server title", body: "Server body", type: "bookingApproved",
      relatedEntityType: "booking", relatedEntityId: "b1", status: "unread",
      readAt: null, createdAt: new Date(), deliverySource: "server",
    });
  });
  const memberDb = environment.authenticatedContext("member").firestore();
  const otherDb = environment.authenticatedContext("beneficiary").firestore();
  await assertFails(setDoc(doc(memberDb, "users/member/notifications/client-self"), {
    notificationId: "client-self", userId: "member", organizationId: "o1",
    title: "Injected", body: "Injected", type: "injected", status: "unread",
  }));
  await assertFails(setDoc(doc(memberDb, "users/beneficiary/notifications/client-other"), {
    notificationId: "client-other", userId: "beneficiary", organizationId: "o1",
    title: "Injected", body: "Injected", type: "injected", status: "unread",
  }));
  await assertSucceeds(getDoc(doc(memberDb, "users/member/notifications/server-notification")));
  await assertFails(getDoc(doc(otherDb, "users/member/notifications/server-notification")));
  await assertSucceeds(updateDoc(doc(memberDb, "users/member/notifications/server-notification"), {
    status: "read", readAt: new Date(),
  }));
  await assertFails(updateDoc(doc(memberDb, "users/member/notifications/server-notification"), {
    title: "Changed", status: "read", readAt: new Date(),
  }));
  await assertFails(updateDoc(doc(memberDb, "users/member/notifications/server-notification"), {
    userId: "beneficiary", status: "read", readAt: new Date(),
  }));
});

test("trusted server notification reaches FCM handler while untrusted documents are rejected", async () => {
  const database = admin.firestore();
  await database.doc("users/member").set({ fcmTokens: ["test-token"], notificationSettings: {} }, { merge: true });
  const trustedRef = database.doc("users/member/notifications/trusted-handler");
  await trustedRef.set({
    notificationId: "trusted-handler", userId: "member", organizationId: "o1",
    title: "Trusted", body: "Trusted body", type: "bookingApproved",
    relatedEntityType: "booking", relatedEntityId: "b1", status: "unread",
    deliverySource: "server", createdAt: Timestamp.now(),
  });
  let sends = 0;
  const response = await onNotificationCreatedHandler({
    params: { userId: "member", notificationId: "trusted-handler" },
    data: await trustedRef.get(),
  }, {
    database,
    messaging: { async sendEachForMulticast(message) {
      sends += 1;
      assert.equal(message.tokens.length, 1);
      assert.equal(message.data.organizationId, "o1");
      return { successCount: 1, failureCount: 0, responses: [{ success: true }] };
    } },
    log: { info() {}, warn() {} },
  });
  assert.equal(response.status, "sent");
  assert.equal(sends, 1);
  const untrustedRef = database.doc("users/member/notifications/untrusted-handler");
  await untrustedRef.set({
    notificationId: "untrusted-handler", userId: "member", organizationId: "o1",
    title: "Untrusted", body: "body", type: "injected",
    relatedEntityType: "booking", relatedEntityId: "b1", status: "unread",
    deliverySource: "client",
  });
  const rejected = await onNotificationCreatedHandler({
    params: { userId: "member", notificationId: "untrusted-handler" },
    data: await untrustedRef.get(),
  }, { database, messaging: { async sendEachForMulticast() { sends += 1; } }, log: { warn() {} } });
  assert.equal(rejected.status, "rejected");
  assert.equal(sends, 1);
});

test("financial profile is council-role isolated and never guest/public readable", async () => {
  const path = "organizations/o1/financial_profile/banking";
  await assertFails(getDoc(doc(environment.authenticatedContext("member").firestore(), path)));
  await assertSucceeds(getDoc(doc(environment.authenticatedContext("finance").firestore(), path)));
  await assertSucceeds(getDoc(doc(environment.authenticatedContext("legacy-owner").firestore(), path)));
  await assertSucceeds(getDoc(doc(environment.authenticatedContext("system-owner").firestore(), path)));
  await assertFails(getDoc(doc(environment.authenticatedContext("outsider").firestore(), path)));
  await assertFails(getDoc(doc(environment.authenticatedContext("guest").firestore(), path)));
  await assertFails(getDoc(doc(environment.unauthenticatedContext().firestore(), path)));
  await assertFails(getDoc(doc(environment.authenticatedContext("finance").firestore(), "organizations/o2/financial_profile/banking")));
});

test("primary owner variants are immutable to clients while ordinary memberships remain manageable", async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "organizations/o1/memberships/flag-owner"), {
      organizationId: "o1", userId: "flag-owner-user", status: "active",
      roleId: "member", isPrimaryOwner: true, permissionsSnapshot: ["fullAccess"],
    });
    await setDoc(doc(context.firestore(), "organizations/o1/memberships/council-owner-role"), {
      organizationId: "o1", userId: "council-owner-user", status: "active",
      roleId: "council_owner", permissionsSnapshot: ["fullAccess"],
    });
  });
  const localOwner = environment.authenticatedContext("legacy-owner").firestore();
  const platformOwner = environment.authenticatedContext("system-owner").firestore();
  for (const id of ["flag-owner", "council-owner-role", "legacy-owner-membership"]) {
    await assertFails(updateDoc(doc(localOwner, `organizations/o1/memberships/${id}`), { status: "suspended" }));
    await assertFails(updateDoc(doc(platformOwner, `organizations/o1/memberships/${id}`), { roleId: "member", isPrimaryOwner: false }));
    await assertFails(deleteDoc(doc(platformOwner, `organizations/o1/memberships/${id}`)));
  }
  await assertSucceeds(updateDoc(doc(localOwner, "organizations/o1/memberships/beneficiary"), {
    status: "suspended", updatedAt: new Date(),
  }));
  await assertFails(getDoc(doc(localOwner, "organizations/o1/member_access/legacy-owner")));
});

test("membership access projection supports different membership and user IDs", async () => {
  const database = admin.firestore();
  const membership = database.doc("organizations/o1/memberships/projection-membership-99");
  await membership.set({
    organizationId: "o1", userId: "projection-user", status: "active",
    roleId: "adminManager", permissionsSnapshot: ["members.manage"],
  });
  await syncMembershipAccessHandler({
    params: { organizationId: "o1", membershipId: "projection-membership-99" },
    data: {
      before: { exists: false },
      after: await membership.get(),
    },
  });
  const access = await database.doc("organizations/o1/member_access/projection-user").get();
  assert.equal(access.get("membershipId"), "projection-membership-99");
  assert.equal(access.get("userId"), "projection-user");
  assert.equal(access.get("roleId"), "adminManager");
  assert.deepEqual(access.get("permissionsSnapshot"), ["members.manage"]);
});

test("organization bootstrap is explicit, system-owner-only, complete and idempotent", async () => {
  const request = {
    auth: { uid: "system-owner" },
    data: {
      requestId: "bootstrap-test-request", organizationId: "bootstrap-test-org",
      officialNameArabic: "مجلس اختبار", officialNameEnglish: "Test Council",
      chairmanUserId: "member",
    },
  };
  const first = await bootstrapOrganizationHandler(request);
  const second = await bootstrapOrganizationHandler(request);
  assert.equal(first.organizationId, "bootstrap-test-org");
  assert.equal(first.idempotent, false);
  assert.equal(second.organizationId, "bootstrap-test-org");
  assert.equal(second.idempotent, true);
  const database = admin.firestore();
  assert.equal((await database.collection("organizations/bootstrap-test-org/roles").get()).size, 6);
  assert.equal((await database.doc("organizations/bootstrap-test-org/financial_profile/banking").get()).exists, true);
  assert.equal((await database.doc("organizations/bootstrap-test-org/settings/organization").get()).exists, true);
  assert.equal((await database.collection("organizations/bootstrap-test-org/memberships").get()).size, 2);
  await database.doc("organizations/bootstrap-test-org/roles/member").delete();
  const repaired = await repairOrganizationStructureHandler({
    auth: { uid: "system-owner" }, data: { organizationId: "bootstrap-test-org" },
  });
  const repairedAgain = await repairOrganizationStructureHandler({
    auth: { uid: "system-owner" }, data: { organizationId: "bootstrap-test-org" },
  });
  assert.equal(repaired.createdCount, 1);
  assert.equal(repaired.idempotent, false);
  assert.equal(repairedAgain.createdCount, 0);
  assert.equal(repairedAgain.idempotent, true);
  assert.equal((await database.doc("organizations/bootstrap-test-org/roles/member").get()).exists, true);
  await assert.rejects(repairOrganizationStructureHandler({
    auth: { uid: "finance" }, data: { organizationId: "bootstrap-test-org" },
  }), /Platform system owner/);
  await assert.rejects(bootstrapOrganizationHandler({ ...request, auth: { uid: "finance" }, data: {
    ...request.data, requestId: "bootstrap-denied", organizationId: "bootstrap-denied-org",
  } }), /Platform system owner/);
  await assertFails(setDoc(
    doc(environment.authenticatedContext("system-owner").firestore(), "organizations/client-bootstrap"),
    { organizationId: "client-bootstrap", status: "active" },
  ));
});

test("primary ownership transfer is platform-only and atomic", async () => {
  await assert.rejects(transferPrimaryCouncilOwnershipHandler({
    auth: { uid: "finance" }, data: {
      organizationId: "o1", currentMembershipId: "legacy-owner-membership",
      targetMembershipId: "beneficiary", previousOwnerRoleId: "member",
    },
  }), /Platform system owner/);
  await transferPrimaryCouncilOwnershipHandler({
    auth: { uid: "system-owner" }, data: {
      organizationId: "o1", currentMembershipId: "legacy-owner-membership",
      targetMembershipId: "beneficiary", previousOwnerRoleId: "member",
    },
  });
  const database = admin.firestore();
  const [previous, target] = await Promise.all([
    database.doc("organizations/o1/memberships/legacy-owner-membership").get(),
    database.doc("organizations/o1/memberships/beneficiary").get(),
  ]);
  assert.equal(previous.get("isPrimaryOwner"), false);
  assert.equal(previous.get("roleId"), "member");
  assert.equal(target.get("isPrimaryOwner"), true);
  assert.equal(target.get("roleId"), "council_owner");
});

test("booking list is owner-constrained while booking managers can review the council", async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    await Promise.all([
      setDoc(doc(database, "organizations/o1/bookings/member-booking"), {
        bookingId: "member-booking", organizationId: "o1", userId: "member",
        requesterName: "Member", requesterPhone: "00000001", status: "pending",
        bookingDate: new Date("2026-08-01T00:00:00.000Z"),
      }),
      setDoc(doc(database, "organizations/o1/bookings/beneficiary-booking"), {
        bookingId: "beneficiary-booking", organizationId: "o1", userId: "beneficiary",
        requesterName: "Beneficiary", requesterPhone: "00000002", status: "pending",
        bookingDate: new Date("2026-08-02T00:00:00.000Z"),
      }),
    ]);
  });
  const memberDb = environment.authenticatedContext("member").firestore();
  await assertFails(getDocs(collection(memberDb, "organizations/o1/bookings")));
  const own = await assertSucceeds(getDocs(query(
    collection(memberDb, "organizations/o1/bookings"),
    where("userId", "==", "member"),
  )));
  assert.equal(own.size, 1);
  assert.equal(own.docs[0].id, "member-booking");
  const financeDb = environment.authenticatedContext("finance").firestore();
  const review = await assertSucceeds(getDocs(collection(financeDb, "organizations/o1/bookings")));
  assert.equal(review.size, 2);
  const outsiderDb = environment.authenticatedContext("outsider").firestore();
  await assertFails(getDocs(collection(outsiderDb, "organizations/o1/bookings")));
});

test("atomic booking slot allows exactly one concurrent create and releases on pending cancellation", async () => {
  const database = admin.firestore();
  const request = (userId, membershipId, bookingId) => ({
    auth: { uid: userId },
    data: {
      organizationId: "o1", membershipId, bookingId,
      requesterName: `Test ${userId}`, requesterPhone: "00000000",
      bookingDate: "2026-10-15", startTime: "10:00", endTime: "12:00",
      occasionType: "QA", notes: "Synthetic Emulator data",
    },
  });
  const results = await Promise.allSettled([
    createBookingHandler(request("member", "member", "concurrent-create-a")),
    createBookingHandler(request("beneficiary", "beneficiary", "concurrent-create-b")),
  ]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal(results.filter((result) => result.status === "rejected").length, 1);
  const bookings = await database.collection("organizations/o1/bookings")
    .where("bookingDay", "==", "2026-10-15").get();
  assert.equal(bookings.size, 1);
  const slots = await database.collection("organizations/o1/booking_slots").get();
  assert.equal(slots.size, 1);
  const winner = bookings.docs[0];
  await requestBookingCancellationHandler({
    auth: { uid: winner.get("userId") },
    data: { organizationId: "o1", bookingId: winner.id, reason: "QA release" },
  });
  assert.equal((await database.collection("organizations/o1/booking_slots").get()).size, 0);
  const retryUser = winner.get("userId") === "member" ? "beneficiary" : "member";
  const retryMembership = retryUser;
  const retry = await createBookingHandler(request(retryUser, retryMembership, "concurrent-create-retry"));
  assert.equal(retry.status, "pending");
});

test("new booking rejects an active legacy booking that has no slot lock", async () => {
  const database = admin.firestore();
  await database.doc("organizations/o1/bookings/legacy-active-without-lock").set({
    bookingId: "legacy-active-without-lock", organizationId: "o1",
    userId: "beneficiary", membershipId: "beneficiary", status: "approved",
    bookingDate: Timestamp.fromDate(new Date("2026-12-10T20:00:00.000Z")),
    startTime: "18:00", endTime: "20:00", resourceId: "council_hall",
    requesterName: "Synthetic", requesterPhone: "00000000",
  });
  await assert.rejects(createBookingHandler({
    auth: { uid: "member" },
    data: {
      organizationId: "o1", membershipId: "member", bookingId: "blocked-by-legacy",
      requesterName: "Synthetic", requesterPhone: "00000000",
      bookingDate: "2026-12-11", startTime: "18:00", endTime: "20:00",
      occasionType: "QA", notes: "Synthetic Emulator data",
    },
  }), (error) => error.code === "already-exists");
  assert.equal((await database.doc("organizations/o1/bookings/blocked-by-legacy").get()).exists, false);
});

test("concurrent approval of legacy bookings for one slot yields one winner", async () => {
  const database = admin.firestore();
  const bookingDate = Timestamp.fromDate(new Date("2026-11-05T20:00:00.000Z"));
  await Promise.all(["legacy-race-a", "legacy-race-b"].map((bookingId, index) =>
    database.doc(`organizations/o1/bookings/${bookingId}`).set({
      bookingId, organizationId: "o1", userId: index === 0 ? "member" : "beneficiary",
      membershipId: index === 0 ? "member" : "beneficiary", status: "pending",
      bookingDate, startTime: "18:00", endTime: "20:00",
      requesterName: "Synthetic", requesterPhone: "00000000",
    })));
  const results = await Promise.allSettled([
    reviewBookingHandler({ auth: { uid: "finance" }, data: {
      organizationId: "o1", bookingId: "legacy-race-a", decision: "approve",
    } }),
    reviewBookingHandler({ auth: { uid: "finance2" }, data: {
      organizationId: "o1", bookingId: "legacy-race-b", decision: "approve",
    } }),
  ]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal(results.filter((result) => result.status === "rejected").length, 1);
  const approved = await database.collection("organizations/o1/bookings")
    .where("status", "==", "approved").get();
  assert.equal(approved.docs.filter((document) => document.id.startsWith("legacy-race-")).length, 1);
  assert.equal((await database.collection("organizations/o1/booking_slots").get()).size, 1);
});

test("production member search enforces three characters, ten results, and council membership", async () => {
  const result = await searchCouncilMembersHandler({
    auth: { uid: "member" }, data: { organizationId: "o1", query: "mem" },
  });
  if (result.members.length !== 10) throw new Error(`Expected 10 search results, received ${result.members.length}.`);
  for (const row of result.members) {
    assert.deepEqual(Object.keys(row).sort(), ["fullName", "memberNumber", "membershipId", "photoUrl", "userId"]);
  }
  const rateReference = admin.firestore().doc(
    `organizations/o1/financial_rate_limits/${financialRateLimitId("member_search", "member")}`
  );
  assert.equal((await rateReference.get()).get("count"), 1);
  await rateReference.set({
    userId: "member", operation: "member_search", count: 30,
    windowStartedAt: Timestamp.now(), updatedAt: Timestamp.now(),
  });
  await assert.rejects(
    searchCouncilMembersHandler({ auth: { uid: "member" }, data: { organizationId: "o1", query: "mem" } }),
    /operation limit reached/,
  );
  await assert.rejects(
    searchCouncilMembersHandler({ auth: { uid: "member" }, data: { organizationId: "o1", query: "me" } }),
    /three normalized characters/,
  );
  await assert.rejects(
    searchCouncilMembersHandler({ auth: { uid: "outsider" }, data: { organizationId: "o1", query: "mem" } }),
    /Active council membership/,
  );
});

test("financial reviewer member listing paginates beyond fifty with council-bound tokens", async () => {
  const database = admin.firestore();
  const batch = database.batch();
  for (let index = 0; index < 65; index += 1) {
    const id = `paged-member-${String(index).padStart(3, "0")}`;
    batch.set(database.doc(`organizations/o1/member_directory/${id}`), {
      membershipId: id, userId: `paged-user-${index}`, active: true,
      fullName: `Paged Member ${String(index).padStart(3, "0")}`,
      memberNumber: String(500 + index), photoUrl: null,
    });
  }
  await batch.commit();
  const ids = new Set();
  let pageToken;
  let pageCount = 0;
  do {
    const page = await listFinancialMembersHandler({ auth: { uid: "finance" }, data: {
      organizationId: "o1", pageSize: 20, ...(pageToken ? { pageToken } : {}),
    } });
    page.members.forEach((member) => ids.add(member.membershipId));
    pageToken = page.nextPageToken;
    pageCount += 1;
  } while (pageToken);
  assert.equal(ids.size, 79);
  assert.ok(pageCount >= 4);
  const invalidToken = Buffer.from(JSON.stringify({
    version: 1, organizationId: "o2", fullName: "Member", documentId: "member",
  }), "utf8").toString("base64url");
  await assert.rejects(listFinancialMembersHandler({ auth: { uid: "finance" }, data: {
    organizationId: "o1", pageToken: invalidToken,
  } }), /page token is invalid/);
  await assert.rejects(listFinancialMembersHandler({ auth: { uid: "member" }, data: {
    organizationId: "o1",
  } }), /review permission/);
});

test("financial documents cannot be mutated directly by clients", async () => {
  const db = environment.authenticatedContext("finance").firestore();
  await assertFails(setDoc(doc(db, "organizations/o1/charges/new"), {
    organizationId: "o1", chargeId: "new", amountDueBaisa: 1,
  }));
  await assertFails(setDoc(doc(db, "organizations/o1/financial_settings/main"), {
    organizationId: "o1", onlinePaymentsEnabled: false,
  }));
  const rateId = financialRateLimitId("member_search", "finance");
  await assertFails(getDoc(doc(db, `organizations/o1/financial_rate_limits/${rateId}`)));
  await assertFails(setDoc(doc(db, `organizations/o1/financial_rate_limits/${rateId}`), {
    userId: "finance", operation: "member_search", count: 0,
  }));
});

test("receipt storage permits only owner direct reads", async () => {
  const ownerStorage = environment.authenticatedContext("member").storage();
  const object = ref(ownerStorage, "organizations/o1/members/member/receipts/r1/receipt.png");
  await assertSucceeds(uploadBytes(object, new Uint8Array([1, 2, 3]), {
    contentType: "image/png",
    customMetadata: {
      temporaryUpload: "true", receiptId: "r1", uploaderUid: "member",
      organizationId: "o1", uploadedAt: new Date().toISOString(),
    },
  }))
    .catch((error) => { throw new Error(`owner upload failed: ${error.message}`); });
  const outsiderObject = ref(environment.authenticatedContext("outsider").storage(), object.fullPath);
  await assertFails(getBytes(outsiderObject))
    .catch((error) => { throw new Error(`outsider read assertion failed: ${error.message}`); });
  const financeObject = ref(environment.authenticatedContext("finance").storage(), object.fullPath);
  await assertFails(getBytes(financeObject))
    .catch((error) => { throw new Error(`finance direct read assertion failed: ${error.message}`); });

  const supported = [
    ["jpg", "image/jpeg"],
    ["png", "image/png"],
    ["webp", "image/webp"],
    ["pdf", "application/pdf"],
  ];
  for (const [extension, contentType] of supported) {
    const id = `allowed-${extension}`;
    const allowed = ref(ownerStorage, `organizations/o1/members/member/receipts/${id}/receipt.${extension}`);
    await assertSucceeds(uploadBytes(allowed, new Uint8Array([1, 2, 3]), {
      contentType,
      customMetadata: {
        temporaryUpload: "true", receiptId: id, uploaderUid: "member",
        organizationId: "o1", uploadedAt: new Date().toISOString(),
      },
    }));
  }
  const svg = ref(ownerStorage, "organizations/o1/members/member/receipts/rejected-svg/receipt.svg");
  await assertFails(uploadBytes(svg, new TextEncoder().encode("<svg></svg>"), {
    contentType: "image/svg+xml",
    customMetadata: {
      temporaryUpload: "true", receiptId: "rejected-svg", uploaderUid: "member",
      organizationId: "o1", uploadedAt: new Date().toISOString(),
    },
  }));
  const legacySvg = ref(ownerStorage, "receipts/member/legacy-svg/receipt.svg");
  await assertFails(uploadBytes(legacySvg, new TextEncoder().encode("<svg></svg>"), {
    contentType: "image/svg+xml",
  }));
  const legacyPng = ref(ownerStorage, "receipts/member/legacy-png/receipt.png");
  await assertSucceeds(uploadBytes(legacyPng, new Uint8Array([1]), { contentType: "image/png" }));
});

test("receipt download authorization supports membershipId different from userId", async () => {
  const database = admin.firestore();
  const storagePath = "organizations/o1/members/member/receipts/mismatched-reviewer/receipt.png";
  await database.doc("organizations/o1/transactions/mismatched-reviewer").set({
    organizationId: "o1",
    transactionId: "mismatched-reviewer",
    payerUserId: "member",
    receiptStoragePath: storagePath,
    fileName: "receipt.png",
    fileType: "image/png",
    reviewStatus: "pending",
    status: "pendingReview",
  });
  const emulatorFile = {
    bytesBase64: Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).toString("base64"),
    sizeBytes: 8,
    contentType: "image/png",
    fileName: "receipt.png",
  };
  const reviewerResult = await getFinancialReceiptDownloadUrlHandler({
    auth: { uid: "reviewer-different" },
    data: { organizationId: "o1", transactionId: "mismatched-reviewer" },
  }, {
    environment: { FUNCTIONS_EMULATOR: "true", GCLOUD_PROJECT: "demo-financial-prestaging" },
    readReceiptFile: async () => emulatorFile,
  });
  assert.equal(reviewerResult.kind, "bytes");
  assert.equal(reviewerResult.bytesBase64, emulatorFile.bytesBase64);
  const ownerResult = await getFinancialReceiptDownloadUrlHandler({
    auth: { uid: "member" },
    data: { organizationId: "o1", transactionId: "mismatched-reviewer" },
  }, {
    environment: { FUNCTIONS_EMULATOR: "true", GCLOUD_PROJECT: "demo-financial-prestaging" },
    readReceiptFile: async () => emulatorFile,
  });
  assert.equal(ownerResult.kind, "bytes");
  await assert.rejects(
    getFinancialReceiptDownloadUrlHandler({
      auth: { uid: "outsider" },
      data: { organizationId: "o1", transactionId: "mismatched-reviewer" },
    }, {
      environment: { FUNCTIONS_EMULATOR: "true", GCLOUD_PROJECT: "demo-financial-prestaging" },
      readReceiptFile: async () => emulatorFile,
    }),
    /Active council membership/,
  );
  await assert.rejects(
    getFinancialReceiptDownloadUrlHandler({
      auth: { uid: "reviewer-different" },
      data: { organizationId: "o2", transactionId: "mismatched-reviewer" },
    }, {
      environment: { FUNCTIONS_EMULATOR: "true", GCLOUD_PROJECT: "demo-financial-prestaging" },
      readReceiptFile: async () => emulatorFile,
    }),
    /not found/,
  );
  await database.doc("organizations/o1/transactions/path-mismatch").set({
    organizationId: "o1",
    transactionId: "path-mismatch",
    payerUserId: "member",
    receiptStoragePath: storagePath,
    fileName: "receipt.png",
    fileType: "image/png",
  });
  await assert.rejects(
    getFinancialReceiptDownloadUrlHandler({
      auth: { uid: "member" },
      data: { organizationId: "o1", transactionId: "path-mismatch" },
    }, {
      environment: { FUNCTIONS_EMULATOR: "true", GCLOUD_PROJECT: "demo-financial-prestaging" },
      readReceiptFile: async () => emulatorFile,
    }),
    /storage identity is invalid/,
  );
  let emulatorReaderCalled = false;
  const production = await getFinancialReceiptDownloadUrlHandler({
    auth: { uid: "reviewer-different" },
    data: { organizationId: "o1", transactionId: "mismatched-reviewer" },
  }, {
    environment: { FUNCTIONS_EMULATOR: "false", GCLOUD_PROJECT: "demo-financial-prestaging" },
    readReceiptFile: async () => { emulatorReaderCalled = true; return emulatorFile; },
    createDownloadUrl: async (path) => `https://signed.invalid/${encodeURIComponent(path)}`,
  });
  assert.equal(production.kind, "url");
  assert.equal(production.expiresInSeconds, 300);
  assert.match(production.url, /^https:\/\/signed\.invalid\//);
  assert.equal(emulatorReaderCalled, false);
});

test("emulator receipt reader rejects missing, oversized, mismatched, and invalid files without logging bytes", async () => {
  const pdf = Buffer.from("%PDF-1.7\nqa");
  const bucket = (metadata, bytes = pdf, error = null) => ({
    file: () => ({
      getMetadata: async () => {
        if (error) throw error;
        return [metadata];
      },
      download: async () => [bytes],
    }),
  });
  const valid = await readFinancialReceiptFromEmulator(
    "organizations/o1/members/member/receipts/r1/receipt.pdf",
    "receipt.pdf",
    "application/pdf",
    { bucket: bucket({ size: String(pdf.length), contentType: "application/pdf" }) }
  );
  assert.equal(valid.bytesBase64, pdf.toString("base64"));
  await assert.rejects(readFinancialReceiptFromEmulator(
    "organizations/o1/members/member/receipts/r1/receipt.pdf",
    "receipt.pdf",
    "application/pdf",
    { bucket: bucket(null, pdf, { code: 404 }) }
  ), /not found/);
  await assert.rejects(readFinancialReceiptFromEmulator(
    "organizations/o1/members/member/receipts/r1/receipt.pdf",
    "receipt.pdf",
    "application/pdf",
    { bucket: bucket({ size: String(10 * 1024 * 1024 + 1), contentType: "application/pdf" }) }
  ), /size is invalid/);
  await assert.rejects(readFinancialReceiptFromEmulator(
    "organizations/o1/members/member/receipts/r1/receipt.pdf",
    "receipt.pdf",
    "application/pdf",
    { bucket: bucket({ size: String(pdf.length), contentType: "image/png" }) }
  ), /does not match/);
  await assert.rejects(readFinancialReceiptFromEmulator(
    "organizations/o1/members/member/receipts/r1/receipt.exe",
    "receipt.exe",
    "application/octet-stream",
    { bucket: bucket({ size: "4", contentType: "application/octet-stream" }, Buffer.from("test")) }
  ), /not allowed/);
  await assert.rejects(readFinancialReceiptFromEmulator(
    "organizations/o1/members/member/receipts/r1/receipt.pdf",
    "receipt.pdf",
    "application/pdf",
    { bucket: bucket({ size: "9", contentType: "application/pdf" }, Buffer.from("not-a-pdf")) }
  ), /content is invalid/);
  assert.doesNotMatch(JSON.stringify(valid), /%PDF-/);
});

test("payable charge pagination returns every charge beyond the first fifty", async () => {
  const database = admin.firestore();
  const batch = database.batch();
  for (let index = 0; index < 61; index += 1) {
    const chargeId = `page-${String(index).padStart(3, "0")}`;
    batch.set(database.doc(`organizations/o1/charges/${chargeId}`), {
      chargeId,
      organizationId: "o1",
      membershipId: "member",
      userId: "member",
      chargeType: "subscription",
      amountDueBaisa: 1000,
      amountPaidBaisa: 0,
      balanceBaisa: 1000,
      status: "unpaid",
    });
  }
  await batch.commit();
  await database.doc("organizations/o1/pending_receipt_locks/member_c0").set({
    payerUserId: "member",
    chargeId: "c0",
    transactionId: "pending-c0",
    expiresAt: Timestamp.fromMillis(Date.now() + 60 * 60 * 1000),
  });
  const chargeIds = new Set();
  let pendingCharge;
  const tokens = new Set();
  let pageToken;
  do {
    const page = await getPayableChargesHandler({
      auth: { uid: "member" },
      data: {
        organizationId: "o1",
        membershipIds: ["member"],
        pageSize: 20,
        ...(pageToken ? { pageToken } : {}),
      },
    });
    page.charges.forEach((charge) => {
      chargeIds.add(charge.chargeId);
      if (charge.chargeId === "c0") pendingCharge = charge;
    });
    pageToken = page.nextPageToken;
    if (pageToken && !tokens.add(pageToken)) throw new Error("Pagination repeated a token.");
  } while (pageToken);
  assert.equal(chargeIds.size, 62);
  assert.ok(chargeIds.has("page-060"));
  assert.equal(pendingCharge.hasPendingReceipt, true);
  assert.equal(pendingCharge.pendingTransactionId, "pending-c0");
});

test("financial notification outbox retries a failure and never duplicates delivery", async () => {
  const database = admin.firestore();
  const notificationId = "outbox-failure-retry";
  const outbox = database.doc("organizations/o1/_financial_notification_outbox_test/outbox-failure-retry");
  const createdAt = Timestamp.now();
  await outbox.set({
    organizationId: "o1",
    userId: "member",
    notificationId,
    status: "pending",
    attemptCount: 0,
    createdAt,
    updatedAt: createdAt,
    deliveredAt: null,
    payload: {
      notificationId,
      title: "اختبار",
      body: "إعادة محاولة",
      type: "receiptReceived",
      userId: "member",
      organizationId: "o1",
      relatedEntityType: "receipt",
      relatedEntityId: "outbox-receipt",
      status: "unread",
      createdAt,
      readAt: null,
      createdByUserId: "member",
      deliverySource: "server",
    },
  });
  const event = { data: await outbox.get(), params: { organizationId: "o1", outboxId: outbox.id } };
  await assert.rejects(
    deliverFinancialNotificationOutboxHandler(event, {
      beforeCommit: async () => { throw new Error("simulated delivery failure"); },
    }),
    /simulated delivery failure/,
  );
  const target = database.doc(`users/member/notifications/${notificationId}`);
  assert.equal((await target.get()).exists, false);
  assert.equal((await outbox.get()).get("status"), "pending");
  const retry = await deliverFinancialNotificationOutboxHandler(event);
  assert.equal(retry.status, "delivered");
  const duplicate = await deliverFinancialNotificationOutboxHandler(event);
  assert.equal(duplicate.idempotent, true);
  assert.equal((await target.get()).exists, true);
  assert.equal((await outbox.get()).get("attemptCount"), 1);
  const matches = await database.collection("users/member/notifications")
    .where("notificationId", "==", notificationId).get();
  assert.equal(matches.size, 1);
});

function receiptRequest(receiptId, allocations, amountDeclaredBaisa) {
  return {
    auth: { uid: "member" },
    data: {
      receiptId,
      organizationId: "o1",
      payerMembershipId: "member",
      paymentScope: allocations.some((item) => item.beneficiaryMembershipId === "member") &&
        allocations.some((item) => item.beneficiaryMembershipId !== "member") ? "mixed" :
        allocations.every((item) => item.beneficiaryMembershipId === "member") ? "self" : "others",
      amountDeclaredBaisa,
      receiptStoragePath: `organizations/o1/members/member/receipts/${receiptId}/receipt.png`,
      fileName: "receipt.png",
      fileType: "image/png",
      allocations,
    },
  };
}

test("production receipt handlers keep charges payable, are idempotent, and only one reviewer wins", async () => {
  const allocations = [
    { chargeId: "c0", beneficiaryMembershipId: "member", amountAllocatedBaisa: 500, balanceBeforeBaisa: 1000 },
    { chargeId: "b1", beneficiaryMembershipId: "beneficiary", amountAllocatedBaisa: 1000, balanceBeforeBaisa: 1000 },
  ];
  const request = receiptRequest("mixed-race", allocations, 1500);
  const first = await submitFinancialReceiptHandler(request);
  const retry = await submitFinancialReceiptHandler(request);
  if (first.idempotent || !retry.idempotent) throw new Error("Receipt submission idempotency failed.");

  const database = admin.firestore();
  const storedReceipt = await database.doc("organizations/o1/transactions/mixed-race").get();
  assert.equal(
    storedReceipt.get("receiptUrl"),
    "gs://demo-financial-prestaging.appspot.com/organizations/o1/members/member/receipts/mixed-race/receipt.png",
  );
  assert.doesNotMatch(storedReceipt.get("receiptUrl"), /token=|https?:/);
  const pendingCharge = await database.doc("organizations/o1/charges/b1").get();
  if (pendingCharge.get("status") !== "unpaid") throw new Error("Submission locked a beneficiary charge.");

  const reviews = await Promise.allSettled([
    reviewFinancialReceiptHandler({ auth: { uid: "finance" }, data: { organizationId: "o1", transactionId: "mixed-race", decision: "approve" } }),
    reviewFinancialReceiptHandler({ auth: { uid: "finance2" }, data: { organizationId: "o1", transactionId: "mixed-race", decision: "approve" } }),
  ]);
  if (reviews.filter((item) => item.status === "fulfilled").length !== 1) throw new Error("Exactly one reviewer must win.");
  const [selfCharge, beneficiaryCharge] = await Promise.all([
    database.doc("organizations/o1/charges/c0").get(),
    database.doc("organizations/o1/charges/b1").get(),
  ]);
  if (selfCharge.get("balanceBaisa") !== 500 || selfCharge.get("status") !== "partial") throw new Error("Partial allocation failed.");
  if (beneficiaryCharge.get("balanceBaisa") !== 0 || beneficiaryCharge.get("status") !== "paid") throw new Error("Beneficiary allocation failed.");
});

test("production approval rolls back every allocation when one balance changes", async () => {
  const database = admin.firestore();
  const request = receiptRequest("rollback-race", [
    { chargeId: "c0", beneficiaryMembershipId: "member", amountAllocatedBaisa: 500, balanceBeforeBaisa: 1000 },
    { chargeId: "b1", beneficiaryMembershipId: "beneficiary", amountAllocatedBaisa: 500, balanceBeforeBaisa: 1000 },
  ], 1000);
  await submitFinancialReceiptHandler(request);
  await database.doc("organizations/o1/charges/b1").update({ balanceBaisa: 750 });
  await assert.rejects(
    reviewFinancialReceiptHandler({ auth: { uid: "finance" }, data: { organizationId: "o1", transactionId: "rollback-race", decision: "approve" } }),
    /balance changed/,
  );
  const selfCharge = await database.doc("organizations/o1/charges/c0").get();
  if (selfCharge.get("amountPaidBaisa") !== 0 || selfCharge.get("balanceBaisa") !== 1000) throw new Error("Approval did not roll back atomically.");
  await reviewFinancialReceiptHandler({
    auth: { uid: "finance" },
    data: { organizationId: "o1", transactionId: "rollback-race", decision: "reject", rejectionReason: "Balance changed" },
  });
});

async function waitForCharge(database, bookingId, expectedStatus, timeoutMs = 12000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const snapshot = await database.collection("organizations/o1/charges")
      .where("sourceId", "==", bookingId).get();
    if (snapshot.size === 1 && snapshot.docs[0].get("status") === expectedStatus) return snapshot.docs[0];
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  throw new Error(`Timed out waiting for booking ${bookingId} charge status ${expectedStatus}.`);
}

test("booking trigger creates one idempotent charge and marks paid cancellation for refund review", async () => {
  const database = admin.firestore();
  const booking = database.doc("organizations/o1/bookings/booking-emulator");
  await booking.set({
    bookingId: "booking-emulator", organizationId: "o1", userId: "member",
    membershipId: "member", status: "pending", bookingDate: Timestamp.now(),
  });
  const pending = await booking.get();
  await booking.update({ status: "approved", approvedBy: "finance" });
  const approved = await booking.get();
  await bookingFinancialLifecycleHandler({
    id: "booking-emulator-approved",
    params: { organizationId: "o1", bookingId: "booking-emulator" },
    data: { before: pending, after: approved },
  });
  const charge = await waitForCharge(database, "booking-emulator", "unpaid");
  if (charge.get("amountDueBaisa") !== 2500) throw new Error("Incorrect member booking fee.");
  await booking.update({ approvedAt: Timestamp.now() });
  const duplicates = await database.collection("organizations/o1/charges")
    .where("sourceId", "==", "booking-emulator").get();
  if (duplicates.size !== 1) throw new Error("Booking approval created a duplicate charge.");
  await charge.ref.update({ amountPaidBaisa: 2500, balanceBaisa: 0, status: "paid" });
  const beforeCancelled = await booking.get();
  await booking.update({ status: "cancelled", cancelledBy: "finance", cancellationReason: "test" });
  const cancelled = await booking.get();
  await bookingFinancialLifecycleHandler({
    id: "booking-emulator-cancelled",
    params: { organizationId: "o1", bookingId: "booking-emulator" },
    data: { before: beforeCancelled, after: cancelled },
  });
  await waitForCharge(database, "booking-emulator", "refundRequired");
});

test("full member booking cycle creates, reviews, partially pays, completes, and cancels safely", async () => {
  const database = admin.firestore();
  const bookingId = "booking-full-cycle";
  const bookingPath = `organizations/o1/bookings/${bookingId}`;
  const memberDb = environment.authenticatedContext("member").firestore();
  const financeDb = environment.authenticatedContext("finance").firestore();
  const outsiderDb = environment.authenticatedContext("outsider").firestore();
  const memberBooking = doc(memberDb, bookingPath);

  await assertFails(setDoc(memberBooking, {
    bookingId,
    organizationId: "o1",
    userId: "member",
    membershipId: "member",
    requesterName: "عضو تجريبي",
    requesterPhone: "00000000",
    bookingDate: new Date("2026-09-10T00:00:00.000Z"),
    occasionType: "اختبار دورة الحجز",
    notes: "بيانات Emulator وهمية",
    status: "pending",
    createdAt: new Date(),
    updatedAt: new Date(),
  }));
  await createBookingHandler({
    auth: { uid: "member" },
    data: {
      bookingId, organizationId: "o1", membershipId: "member",
      requesterName: "عضو تجريبي", requesterPhone: "00000000",
      bookingDate: "2026-09-10", occasionType: "اختبار دورة الحجز",
      notes: "بيانات Emulator وهمية",
    },
  });

  await assertFails(updateDoc(doc(outsiderDb, bookingPath), {
    status: "approved",
    approvedBy: "outsider",
    updatedAt: new Date(),
  }));
  await assert.rejects(requestBookingCancellationHandler({
    auth: { uid: "outsider" },
    data: { organizationId: "o1", bookingId },
  }), /Only the booking owner/);

  const beforeApproval = await database.doc(bookingPath).get();
  await assertFails(updateDoc(doc(financeDb, bookingPath), {
    status: "approved",
    approvedBy: "finance",
    approvedAt: new Date(),
    updatedAt: new Date(),
  }));
  await reviewBookingHandler({
    auth: { uid: "finance" },
    data: { organizationId: "o1", bookingId, decision: "approve" },
  });
  const afterApproval = await database.doc(bookingPath).get();
  await bookingFinancialLifecycleHandler({
    id: `${bookingId}-approved`,
    params: { organizationId: "o1", bookingId },
    data: { before: beforeApproval, after: afterApproval },
  });
  await bookingFinancialLifecycleHandler({
    id: `${bookingId}-approved-retry`,
    params: { organizationId: "o1", bookingId },
    data: { before: beforeApproval, after: afterApproval },
  });

  let charge = await waitForCharge(database, bookingId, "unpaid");
  assert.equal(charge.get("accountType"), "member");
  assert.equal(charge.get("membershipId"), "member");
  assert.equal(charge.get("amountDueBaisa"), 2500);
  assert.equal((await database.collection("organizations/o1/charges")
    .where("bookingId", "==", bookingId).get()).size, 1);

  const uploadReceipt = async (receiptId) => {
    const storagePath = `organizations/o1/members/member/receipts/${receiptId}/receipt.png`;
    const object = ref(environment.authenticatedContext("member").storage(), storagePath);
    await assertSucceeds(uploadBytes(object, new Uint8Array([0x89, 0x50, 0x4e, 0x47]), {
      contentType: "image/png",
      customMetadata: {
        temporaryUpload: "true",
        receiptId,
        uploaderUid: "member",
        organizationId: "o1",
        uploadedAt: new Date().toISOString(),
      },
    }));
    return storagePath;
  };
  const submitBookingReceipt = async (receiptId, amountBaisa, balanceBeforeBaisa) => {
    const receiptStoragePath = await uploadReceipt(receiptId);
    return submitFinancialReceiptHandler({
      auth: { uid: "member" },
      data: {
        receiptId,
        organizationId: "o1",
        payerMembershipId: "member",
        paymentScope: "self",
        amountDeclaredBaisa: amountBaisa,
        receiptStoragePath,
        fileName: "receipt.png",
        fileType: "image/png",
        allocations: [{
          chargeId: charge.id,
          beneficiaryMembershipId: "member",
          amountAllocatedBaisa: amountBaisa,
          balanceBeforeBaisa,
        }],
      },
    });
  };

  const rejected = await submitBookingReceipt("booking-rejected-receipt", 500, 2500);
  assert.equal(rejected.idempotent, false);
  await reviewFinancialReceiptHandler({
    auth: { uid: "finance" },
    data: {
      organizationId: "o1",
      transactionId: "booking-rejected-receipt",
      decision: "reject",
      rejectionReason: "إيصال QA مرفوض عمدًا",
    },
  });
  charge = await charge.ref.get();
  assert.equal(charge.get("status"), "unpaid");
  assert.equal(charge.get("amountPaidBaisa"), 0);
  assert.equal(charge.get("balanceBaisa"), 2500);

  const partial = await submitBookingReceipt("booking-partial-receipt", 1000, 2500);
  assert.equal(partial.idempotent, false);
  assert.equal((await submitFinancialReceiptHandler({
    auth: { uid: "member" },
    data: {
      receiptId: "booking-partial-receipt",
      organizationId: "o1",
      payerMembershipId: "member",
      paymentScope: "self",
      amountDeclaredBaisa: 1000,
      receiptStoragePath: "organizations/o1/members/member/receipts/booking-partial-receipt/receipt.png",
      fileName: "receipt.png",
      fileType: "image/png",
      allocations: [{
        chargeId: charge.id,
        beneficiaryMembershipId: "member",
        amountAllocatedBaisa: 1000,
        balanceBeforeBaisa: 2500,
      }],
    },
  })).idempotent, true);
  await reviewFinancialReceiptHandler({
    auth: { uid: "finance" },
    data: { organizationId: "o1", transactionId: "booking-partial-receipt", decision: "approve" },
  });
  charge = await charge.ref.get();
  assert.equal(charge.get("status"), "partial");
  assert.equal(charge.get("amountPaidBaisa"), 1000);
  assert.equal(charge.get("balanceBaisa"), 1500);

  await submitBookingReceipt("booking-final-receipt", 1500, 1500);
  await reviewFinancialReceiptHandler({
    auth: { uid: "finance2" },
    data: { organizationId: "o1", transactionId: "booking-final-receipt", decision: "approve" },
  });
  charge = await charge.ref.get();
  assert.equal(charge.get("status"), "paid");
  assert.equal(charge.get("amountPaidBaisa"), 2500);
  assert.equal(charge.get("balanceBaisa"), 0);

  assert.equal((await requestBookingCancellationHandler({
    auth: { uid: "member" },
    data: { organizationId: "o1", bookingId, reason: "إلغاء QA بعد السداد" },
  })).status, "cancellationRequested");
  const cancellation = await reviewBookingCancellationHandler({
    auth: { uid: "finance" },
    data: { organizationId: "o1", bookingId, decision: "approve" },
  });
  assert.equal(cancellation.status, "cancelled");
  assert.equal(cancellation.chargeStatus, "refundRequired");
  charge = await charge.ref.get();
  assert.equal(charge.get("status"), "refundRequired");
  assert.equal(charge.get("amountPaidBaisa"), 2500);
  assert.equal(charge.get("balanceBaisa"), 0);
  assert.equal((await database.doc(bookingPath).get()).get("status"), "cancelled");
});

test("production scheduled handlers paginate over 200 accounts, fail loudly, and retry without duplicates", async () => {
  const database = admin.firestore();
  const organization = database.doc("organizations/scheduled");
  const batch = database.batch();
  batch.set(organization.collection("financial_settings").doc("main"), {
    organizationId: "scheduled", feeMode: "subscription", currency: "OMR",
  });
  batch.set(organization.collection("subscription_plans").doc("monthly"), {
    planId: "monthly", organizationId: "scheduled", billingCycle: "monthly",
    amountBaisa: 1000, active: true, nameArabic: "Monthly",
  });
  for (let index = 0; index < 205; index += 1) {
    batch.set(organization.collection("member_accounts").doc(`m${String(index).padStart(3, "0")}`), {
      organizationId: "scheduled", membershipId: `m${String(index).padStart(3, "0")}`,
      userId: `u${index}`, planId: "monthly", feeOverrideType: "default",
    });
  }
  await batch.commit();
  let attempts = 0;
  await assert.rejects(generateSubscriptionChargesHandler(null, {
    environment: enabledScheduleEnvironment("FINANCIAL_SCHEDULE_GENERATE_SUBSCRIPTIONS_ENABLED"),
    database, pageSize: 50, nowDate: new Date("2026-07-31T20:30:00.000Z"),
    processAccount: async (snapshot) => {
      attempts += 1;
      if (snapshot.id === "m075") throw new Error("temporary page failure");
      return ensureSubscriptionCharge(snapshot, { nowDate: new Date("2026-07-31T20:30:00.000Z") });
    },
    log: { info() {} },
  }), /Page processing failed/);
  assert.ok(attempts > 50, "The injected failure must occur after the first page.");
  const logRows = [];
  const stats = await generateSubscriptionChargesHandler(null, {
    environment: enabledScheduleEnvironment("FINANCIAL_SCHEDULE_GENERATE_SUBSCRIPTIONS_ENABLED"),
    database, pageSize: 50, nowDate: new Date("2026-07-31T20:30:00.000Z"),
    log: { info(message, values) { logRows.push({ message, values }); } },
  });
  assert.equal(stats.scanned, 205);
  assert.equal((await organization.collection("charges").get()).size, 205);
  const retry = await generateSubscriptionChargesHandler(null, {
    environment: enabledScheduleEnvironment("FINANCIAL_SCHEDULE_GENERATE_SUBSCRIPTIONS_ENABLED"),
    database, pageSize: 50, nowDate: new Date("2026-07-31T20:30:00.000Z"), log: { info() {} },
  });
  assert.equal(retry.outcomes.exists, 205);
  assert.equal((await organization.collection("charges").get()).size, 205);
  const serializedLogs = JSON.stringify(logRows);
  assert.doesNotMatch(serializedLogs, /u0|m000|fullName|email|phone/);
});

test("production overdue handler respects Muscat due day and year boundary", async () => {
  const database = admin.firestore();
  const charges = database.collection("organizations/time/charges");
  await Promise.all([
    charges.doc("same-day").set({ organizationId: "time", membershipId: "m", userId: "u", status: "unpaid", dueDate: Timestamp.fromDate(new Date("2026-12-31T19:00:00Z")) }),
    charges.doc("prior-day").set({ organizationId: "time", membershipId: "m", userId: "u", status: "partial", dueDate: Timestamp.fromDate(new Date("2026-12-30T19:00:00Z")) }),
  ]);
  const stats = await markFinancialChargesOverdueHandler(null, {
    environment: enabledScheduleEnvironment("FINANCIAL_SCHEDULE_MARK_OVERDUE_ENABLED"),
    database, pageSize: 1, nowDate: new Date("2026-12-31T19:30:00Z"), log: { info() {} },
  });
  assert.ok(stats.scanned >= 2);
  assert.equal((await charges.doc("same-day").get()).get("status"), "unpaid");
  assert.equal((await charges.doc("prior-day").get()).get("status"), "overdue");
  await markFinancialChargesOverdueHandler(null, {
    environment: enabledScheduleEnvironment("FINANCIAL_SCHEDULE_MARK_OVERDUE_ENABLED"),
    database, pageSize: 1, nowDate: new Date("2026-12-31T20:30:00Z"), log: { info() {} },
  });
  assert.equal((await charges.doc("same-day").get()).get("status"), "overdue");
});

test("guest booking uses non-member fee, is private, and submits only its own receipt", async () => {
  const database = admin.firestore();
  await database.doc("organizations/o1/financial_settings/main").update({
    nonMemberBookingFeeBaisa: 7500,
  });
  await database.doc("users/guest").set({ fullName: "Guest" });
  const booking = database.doc("organizations/o1/bookings/guest-booking");
  await booking.set({
    bookingId: "guest-booking", organizationId: "o1", userId: "guest",
    status: "pending", bookingDate: Timestamp.now(),
  });
  const before = await booking.get();
  await booking.update({ status: "approved", approvedBy: "finance" });
  const afterApproval = await booking.get();
  await bookingFinancialLifecycleHandler({
    id: "guest-approved", params: { organizationId: "o1", bookingId: "guest-booking" },
    data: { before, after: afterApproval },
  });
  const charge = await waitForCharge(database, "guest-booking", "unpaid");
  assert.equal(charge.get("accountType"), "guest");
  assert.equal(charge.get("membershipId"), null);
  assert.equal(charge.get("amountDueBaisa"), 7500);
  const response = await getGuestBookingChargeHandler({ auth: { uid: "guest" }, data: { organizationId: "o1", bookingId: "guest-booking" } });
  assert.equal(response.charge.balanceBaisa, 7500);
  await assert.rejects(getGuestBookingChargeHandler({ auth: { uid: "outsider" }, data: { organizationId: "o1", bookingId: "guest-booking" } }), /ownership mismatch/);
  await assert.rejects(searchCouncilMembersHandler({ auth: { uid: "guest" }, data: { organizationId: "o1", query: "mem" } }), /Active council membership/);
  const guestDb = environment.authenticatedContext("guest").firestore();
  await assertSucceeds(getDoc(doc(guestDb, `organizations/o1/charges/${charge.id}`)));
  const outsiderDb = environment.authenticatedContext("outsider").firestore();
  await assertFails(getDoc(doc(outsiderDb, `organizations/o1/charges/${charge.id}`)));
  const firstReceiptRequest = { auth: { uid: "guest" }, data: {
    organizationId: "o1", bookingId: "guest-booking", chargeId: charge.id,
    receiptId: "guest-receipt", amountDeclaredBaisa: 1000, balanceBeforeBaisa: 7500,
    receiptUrl: "https://firebasestorage.invalid/download?token=must-not-be-stored",
    receiptStoragePath: "organizations/o1/members/guest/receipts/guest-receipt/receipt.png",
    fileName: "receipt.png", fileType: "image/png",
  } };
  const guestRateReference = database.doc(
    `organizations/o1/financial_rate_limits/${financialRateLimitId("guest_receipt", "guest")}`
  );
  await guestRateReference.set({
    userId: "guest", operation: "guest_receipt", count: 10,
    windowStartedAt: Timestamp.now(), updatedAt: Timestamp.now(),
  });
  await assert.rejects(submitGuestBookingReceiptHandler(firstReceiptRequest), /operation limit reached/);
  await guestRateReference.delete();
  await assert.rejects(submitGuestBookingReceiptHandler({ auth: { uid: "guest" }, data: {
    ...firstReceiptRequest.data,
    receiptId: "guest-svg",
    receiptStoragePath: "organizations/o1/members/guest/receipts/guest-svg/receipt.svg",
    fileName: "receipt.svg",
    fileType: "image/svg+xml",
  } }), /content type is not allowed/);
  assert.equal((await submitGuestBookingReceiptHandler(firstReceiptRequest)).idempotent, false);
  assert.equal((await submitGuestBookingReceiptHandler(firstReceiptRequest)).idempotent, true);
  const guestTransaction = await database.doc("organizations/o1/transactions/guest-receipt").get();
  assert.equal(
    guestTransaction.get("receiptUrl"),
    "gs://demo-financial-prestaging.appspot.com/organizations/o1/members/guest/receipts/guest-receipt/receipt.png",
  );
  assert.doesNotMatch(guestTransaction.get("receiptUrl"), /must-not-be-stored|token=|https?:/);
  await assert.rejects(submitGuestBookingReceiptHandler({ auth: { uid: "guest" }, data: {
    organizationId: "o1", bookingId: "guest-booking", chargeId: "c0",
    receiptId: "guest-invalid", amountDeclaredBaisa: 1000, balanceBeforeBaisa: 1000,
    receiptStoragePath: "organizations/o1/members/guest/receipts/guest-invalid/receipt.png",
    fileName: "receipt.png", fileType: "image/png",
  } }), /Only your own guest booking charge/);
  await reviewFinancialReceiptHandler({ auth: { uid: "finance" }, data: {
    organizationId: "o1", transactionId: "guest-receipt", decision: "approve",
  } });
  assert.equal((await charge.ref.get()).get("status"), "partial");
  assert.equal((await database.doc(`organizations/o1/pending_receipt_locks/guest_${charge.id}`).get()).exists, false);

  await submitGuestBookingReceiptHandler({ auth: { uid: "guest" }, data: {
    organizationId: "o1", bookingId: "guest-booking", chargeId: charge.id,
    receiptId: "guest-receipt-final", amountDeclaredBaisa: 6500, balanceBeforeBaisa: 6500,
    receiptStoragePath: "organizations/o1/members/guest/receipts/guest-receipt-final/receipt.webp",
    fileName: "receipt.webp", fileType: "image/webp",
  } });
  await reviewFinancialReceiptHandler({ auth: { uid: "finance" }, data: {
    organizationId: "o1", transactionId: "guest-receipt-final", decision: "approve",
  } });
  const paid = await charge.ref.get();
  assert.equal(paid.get("amountPaidBaisa"), 7500);
  assert.equal(paid.get("balanceBaisa"), 0);
  assert.equal(paid.get("status"), "paid");
  await assert.rejects(submitGuestBookingReceiptHandler({ auth: { uid: "guest" }, data: {
    organizationId: "o1", bookingId: "guest-booking", chargeId: charge.id,
    receiptId: "guest-overpay", amountDeclaredBaisa: 1, balanceBeforeBaisa: 0,
    receiptStoragePath: "organizations/o1/members/guest/receipts/guest-overpay/receipt.png",
    fileName: "receipt.png", fileType: "image/png",
  } }), /Invalid monetary amount/);
  const unrelatedGuestDb = environment.authenticatedContext("guest2").firestore();
  await assertFails(getDoc(doc(unrelatedGuestDb, `organizations/o1/charges/${charge.id}`)));
});

test("booking fees honor disabled modes and zero amounts", async () => {
  const database = admin.firestore();
  const settings = database.doc("organizations/o1/financial_settings/main");
  const createAndApprove = async (id) => {
    const booking = database.doc(`organizations/o1/bookings/${id}`);
    await booking.set({ bookingId: id, organizationId: "o1", userId: "guest", status: "pending", bookingDate: Timestamp.now() });
    const before = await booking.get();
    await booking.update({ status: "approved", approvedBy: "finance" });
    await bookingFinancialLifecycleHandler({ id, params: { organizationId: "o1", bookingId: id }, data: { before, after: await booking.get() } });
  };
  await settings.update({ feeMode: "free" });
  await createAndApprove("free-booking");
  assert.equal((await database.collection("organizations/o1/charges").where("bookingId", "==", "free-booking").get()).size, 0);
  await settings.update({ feeMode: "subscription", nonMemberBookingFeeBaisa: 4000 });
  await createAndApprove("subscription-booking");
  assert.equal((await database.collection("organizations/o1/charges").where("bookingId", "==", "subscription-booking").get()).size, 0);
  await settings.update({ feeMode: "booking", nonMemberBookingFeeBaisa: 0 });
  await createAndApprove("zero-booking");
  assert.equal((await database.collection("organizations/o1/charges").where("bookingId", "==", "zero-booking").get()).size, 0);

  await settings.update({ feeMode: "subscriptionAndBooking", memberBookingFeeBaisa: 2500 });
  const memberBooking = database.doc("organizations/o1/bookings/member-combined-booking");
  await memberBooking.set({
    bookingId: memberBooking.id, organizationId: "o1", userId: "member",
    membershipId: "member", status: "pending", bookingDate: Timestamp.now(),
  });
  const before = await memberBooking.get();
  await memberBooking.update({ status: "approved", approvedBy: "finance" });
  await bookingFinancialLifecycleHandler({
    id: "member-combined-approved",
    params: { organizationId: "o1", bookingId: memberBooking.id },
    data: { before, after: await memberBooking.get() },
  });
  const memberCharge = await waitForCharge(database, memberBooking.id, "unpaid");
  assert.equal(memberCharge.get("accountType"), "member");
  assert.equal(memberCharge.get("membershipId"), "member");
  assert.equal(memberCharge.get("amountDueBaisa"), 2500);
});

test("booking availability supports members and guests, stays redacted and council-isolated", async () => {
  const database = admin.firestore();
  await database.doc("organizations/o1/settings/organization").set({ allowHallRental: false });
  const rows = [
    ["availability-pending", "pending", "2026-08-02T08:00:00.000Z"],
    ["availability-approved", "approved", "2026-08-03T08:00:00.000Z"],
    ["availability-cancelling", "cancellationRequested", "2026-08-04T08:00:00.000Z"],
    ["availability-cancelled", "cancelled", "2026-08-05T08:00:00.000Z"],
    ["availability-rejected", "rejected", "2026-08-06T08:00:00.000Z"],
  ];
  await Promise.all(rows.map(([id, status, date]) => database.doc(`organizations/o1/bookings/${id}`).set({
    bookingId: id, organizationId: "o1", userId: "beneficiary", status,
    bookingDate: Timestamp.fromDate(new Date(date)),
    requesterName: "Must stay private", requesterPhone: "00000003", notes: "private",
    financialChargeId: "private-charge", receiptUrl: "private-receipt",
  })));
  await database.doc("organizations/o2/bookings/other-council").set({
    bookingId: "other-council", organizationId: "o2", userId: "outsider", status: "approved",
    bookingDate: Timestamp.fromDate(new Date("2026-08-07T08:00:00.000Z")),
    requesterName: "Other council private name",
  });

  const memberAvailability = await getBookingAvailabilityHandler({
    auth: { uid: "member" }, data: { organizationId: "o1", year: 2026, month: 8 },
  });
  assert.equal(memberAvailability.days.length, 3);
  memberAvailability.days.forEach((day) => {
    assert.deepEqual(Object.keys(day).sort(), ["date", "endTime", "resourceId", "startTime", "status"]);
    assert.equal("userId" in day || "requesterName" in day || "receiptUrl" in day || "financialChargeId" in day, false);
  });
  assert.deepEqual(memberAvailability.days.map((day) => day.status).sort(), ["approved", "approved", "pending"]);
  assert.equal(memberAvailability.days.some((day) => day.date.includes("2026-08-07")), false);

  await assert.rejects(getBookingAvailabilityHandler({
    auth: { uid: "guest2" }, data: { organizationId: "o1", year: 2026, month: 8 },
  }), /not enabled/);
  await database.doc("organizations/o1/settings/organization").set({ allowHallRental: true });
  const guestAvailability = await getBookingAvailabilityHandler({
    auth: { uid: "guest2" }, data: { organizationId: "o1", year: 2026, month: 8 },
  });
  assert.deepEqual(guestAvailability, memberAvailability);

  await database.doc("organizations/o1/bookings/availability-cancelling").update({ status: "cancelled" });
  const released = await getBookingAvailabilityHandler({
    auth: { uid: "member" }, data: { organizationId: "o1", year: 2026, month: 8 },
  });
  assert.equal(released.days.length, 2);
  await assert.rejects(getBookingAvailabilityHandler({
    auth: { uid: "member" }, data: { organizationId: "o2", year: 2026, month: 8 },
  }), /not enabled/);
});

test("booking availability paginates beyond one hundred without exposing owners", async () => {
  const database = admin.firestore();
  const batch = database.batch();
  for (let index = 0; index < 125; index += 1) {
    const day = (index % 28) + 1;
    const bookingId = `availability-page-${String(index).padStart(3, "0")}`;
    batch.set(database.doc(`organizations/o1/bookings/${bookingId}`), {
      bookingId, organizationId: "o1", userId: "beneficiary", status: "pending",
      bookingDate: Timestamp.fromDate(new Date(Date.UTC(2026, 11, day, 8))),
      requesterName: "Private synthetic", requesterPhone: "00000000",
    });
  }
  await batch.commit();
  const result = await getBookingAvailabilityHandler({
    auth: { uid: "member" }, data: { organizationId: "o1", year: 2026, month: 12 },
  });
  assert.equal(result.days.length, 125);
  assert.equal(result.days.some((day) => "userId" in day || "requesterName" in day), false);
});

test("booking cancellation is owner-only, review-safe, and paid charges require refund review", async () => {
  const database = admin.firestore();
  const pending = database.doc("organizations/o1/bookings/cancel-pending");
  await pending.set({ bookingId: "cancel-pending", organizationId: "o1", userId: "member", membershipId: "member", status: "pending" });
  await assert.rejects(requestBookingCancellationHandler({ auth: { uid: "beneficiary" }, data: { organizationId: "o1", bookingId: "cancel-pending" } }), /Only the booking owner/);
  assert.equal((await requestBookingCancellationHandler({ auth: { uid: "member" }, data: { organizationId: "o1", bookingId: "cancel-pending" } })).status, "cancelled");

  const approved = database.doc("organizations/o1/bookings/cancel-approved");
  await approved.set({ bookingId: "cancel-approved", organizationId: "o1", userId: "member", membershipId: "member", status: "approved", financialChargeId: "cancel-charge" });
  await database.doc("organizations/o1/charges/cancel-charge").set({
    chargeId: "cancel-charge", organizationId: "o1", accountType: "member", membershipId: "member", userId: "member",
    bookingId: "cancel-approved", chargeType: "booking", amountDueBaisa: 2500, amountPaidBaisa: 500, balanceBaisa: 2000, status: "partial",
  });
  assert.equal((await requestBookingCancellationHandler({ auth: { uid: "member" }, data: { organizationId: "o1", bookingId: "cancel-approved", reason: "change" } })).status, "cancellationRequested");
  const reviews = await Promise.allSettled([
    reviewBookingCancellationHandler({ auth: { uid: "finance" }, data: { organizationId: "o1", bookingId: "cancel-approved", decision: "approve" } }),
    reviewBookingCancellationHandler({ auth: { uid: "finance2" }, data: { organizationId: "o1", bookingId: "cancel-approved", decision: "approve" } }),
  ]);
  assert.equal(reviews.filter((item) => item.status === "fulfilled").length, 1);
  const partialCharge = await database.doc("organizations/o1/charges/cancel-charge").get();
  assert.equal(partialCharge.get("status"), "refundRequired");
  assert.equal(partialCharge.get("amountDueBaisa"), 2500);
  assert.equal(partialCharge.get("amountPaidBaisa"), 500);
  assert.equal(partialCharge.get("balanceBaisa"), 2000);
  await assert.rejects(reviewBookingCancellationHandler({ auth: { uid: "finance" }, data: {
    organizationId: "o1", bookingId: "cancel-approved", decision: "approve",
  } }), /no longer pending/);

  const rejected = database.doc("organizations/o1/bookings/cancel-rejected");
  await rejected.set({ bookingId: "cancel-rejected", organizationId: "o1", userId: "member", status: "approved" });
  await requestBookingCancellationHandler({ auth: { uid: "member" }, data: { organizationId: "o1", bookingId: "cancel-rejected" } });
  await reviewBookingCancellationHandler({ auth: { uid: "finance" }, data: {
    organizationId: "o1", bookingId: "cancel-rejected", decision: "reject", reason: "still reserved",
  } });
  assert.equal((await rejected.get()).get("status"), "approved");

  const unpaid = database.doc("organizations/o1/bookings/cancel-unpaid");
  await unpaid.set({ bookingId: "cancel-unpaid", organizationId: "o1", userId: "member", status: "approved", financialChargeId: "unpaid-charge" });
  await database.doc("organizations/o1/charges/unpaid-charge").set({
    chargeId: "unpaid-charge", organizationId: "o1", accountType: "member", membershipId: "member", userId: "member",
    bookingId: "cancel-unpaid", chargeType: "booking", amountDueBaisa: 2500, amountPaidBaisa: 0, balanceBaisa: 2500, status: "unpaid",
  });
  await requestBookingCancellationHandler({ auth: { uid: "member" }, data: { organizationId: "o1", bookingId: "cancel-unpaid" } });
  await reviewBookingCancellationHandler({ auth: { uid: "finance" }, data: {
    organizationId: "o1", bookingId: "cancel-unpaid", decision: "approve",
  } });
  assert.equal((await database.doc("organizations/o1/charges/unpaid-charge").get()).get("status"), "cancelled");

  const paid = database.doc("organizations/o1/bookings/cancel-paid");
  await paid.set({
    bookingId: "cancel-paid", organizationId: "o1", userId: "member",
    status: "approved", financialChargeId: "paid-charge",
  });
  await database.doc("organizations/o1/charges/paid-charge").set({
    chargeId: "paid-charge", organizationId: "o1", accountType: "member",
    membershipId: "member", userId: "member", bookingId: "cancel-paid",
    chargeType: "booking", amountDueBaisa: 2500, amountPaidBaisa: 2500,
    balanceBaisa: 0, status: "paid", lastTransactionId: "kept-transaction",
  });
  await requestBookingCancellationHandler({ auth: { uid: "member" }, data: {
    organizationId: "o1", bookingId: "cancel-paid",
  } });
  await reviewBookingCancellationHandler({ auth: { uid: "finance" }, data: {
    organizationId: "o1", bookingId: "cancel-paid", decision: "approve",
  } });
  const paidCharge = await database.doc("organizations/o1/charges/paid-charge").get();
  assert.equal(paidCharge.get("status"), "refundRequired");
  assert.equal(paidCharge.get("amountPaidBaisa"), 2500);
  assert.equal(paidCharge.get("balanceBaisa"), 0);
  assert.equal(paidCharge.get("lastTransactionId"), "kept-transaction");

  const expectedAuditIds = [
    "booking_cancelled_by_owner_cancel-pending",
    "booking_cancellation_requested_cancel-approved",
    "booking_cancellation_approved_cancel-approved",
    "booking_cancellation_rejected_cancel-rejected",
    "booking_cancellation_approved_cancel-unpaid",
    "booking_cancellation_approved_cancel-paid",
  ];
  for (const auditId of expectedAuditIds) {
    assert.equal((await database.doc(`organizations/o1/audit_logs/${auditId}`).get()).exists, true, `Missing audit ${auditId}`);
  }
  assert.equal((await database.doc("users/member/notifications/bookingCancellation_cancel-paid_cancellationRequested").get()).exists, true);
  assert.equal((await database.doc("users/member/notifications/bookingCancellationReview_cancel-paid_approve").get()).exists, true);
});

test("scheduled orphan sweep protects recent, linked, incomplete, and Firestore-error files", async () => {
  const ownerStorage = environment.authenticatedContext("member").storage();
  const bucket = admin.storage().bucket(ref(ownerStorage).bucket);
  const future = new Date(Date.now() + 72 * 60 * 60 * 1000);
  const upload = async (id, metadata = {}, userId = "member") => {
    const object = ref(ownerStorage, `organizations/o1/members/${userId}/receipts/${id}/receipt.png`);
    await uploadBytes(object, new Uint8Array([1]), {
      contentType: "image/png",
      customMetadata: {
        temporaryUpload: "true", receiptId: id, uploaderUid: userId,
        organizationId: "o1", uploadedAt: new Date().toISOString(), ...metadata,
      },
    });
    return object.fullPath;
  };
  const oldOrphan = await upload("old-orphan");
  const recentUploadedAt = new Date(future.getTime() - 60 * 60 * 1000).toISOString();
  const recent = await upload("recent", { uploadedAt: recentUploadedAt });
  const pending = await upload("pending-linked");
  const approved = await upload("approved-linked");
  const rejected = await upload("rejected-linked");
  const missingMetadata = "organizations/o1/members/member/receipts/missing-meta/receipt.png";
  await bucket.file(missingMetadata).save(Buffer.from([1]), {
    contentType: "image/png", metadata: { temporaryUpload: "true" },
  });
  const readFailure = await upload("read-failure");
  const database = admin.firestore();
  const [recentMetadata] = await bucket.file(recent).getMetadata();
  assert.equal(recentMetadata.metadata.uploadedAt, recentUploadedAt);
  await Promise.all([
    database.doc("organizations/o1/transactions/pending-linked").set({ receiptStoragePath: pending, reviewStatus: "pending" }),
    database.doc("organizations/o1/transactions/approved-linked").set({ receiptStoragePath: approved, reviewStatus: "approved" }),
    database.doc("organizations/o1/transactions/rejected-linked").set({ receiptStoragePath: rejected, reviewStatus: "rejected" }),
  ]);
  const stats = await cleanupOrphanReceiptsHandler(null, {
    environment: enabledScheduleEnvironment("FINANCIAL_SCHEDULE_CLEANUP_ORPHANS_ENABLED"),
    database, bucket, nowDate: future, pageSize: 2, log: { info() {} },
    isLinked: async (identity, storagePath) => {
      if (storagePath === readFailure) throw new Error("Firestore unavailable");
      const direct = await database.doc(`organizations/${identity.organizationId}/transactions/${identity.receiptId}`).get();
      return direct.exists && direct.get("receiptStoragePath") === storagePath;
    },
  });
  assert.ok(stats.scanned > 2);
  assert.ok(stats.deleted >= 1);
  assert.equal(stats.linked, 3);
  assert.ok(stats.reviewRequired >= 1);
  assert.equal(stats.firestoreErrors, 1);
  await assert.rejects(bucket.file(oldOrphan).getMetadata(), /No such object|404/);
  await bucket.file(recent).getMetadata();
  const rerun = await cleanupOrphanReceiptsHandler(null, {
    environment: enabledScheduleEnvironment("FINANCIAL_SCHEDULE_CLEANUP_ORPHANS_ENABLED"),
    database, bucket, nowDate: future, pageSize: 2, log: { info() {} },
  });
  assert.equal(rerun.deleted, 1, "The previous Firestore-error orphan becomes deletable on a healthy rerun.");
});
