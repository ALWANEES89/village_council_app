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
const { collection, doc, getDoc, getDocs, query, setDoc, where } = require("firebase/firestore");
const { getBytes, ref, uploadBytes } = require("firebase/storage");
const admin = require("firebase-admin");
const { Timestamp } = require("firebase-admin/firestore");

const projectId = process.env.GCLOUD_PROJECT || "demo-financial-fix";
if (admin.apps.length === 0) {
  admin.initializeApp({ projectId, storageBucket: `${projectId}.appspot.com` });
}
const {
  bookingFinancialLifecycleHandler,
  cleanupOrphanReceiptsHandler,
  deliverFinancialNotificationOutboxHandler,
  ensureSubscriptionCharge,
  generateSubscriptionChargesHandler,
  getFinancialReceiptDownloadUrlHandler,
  getGuestBookingChargeHandler,
  getPayableChargesHandler,
  markFinancialChargesOverdueHandler,
  requestBookingCancellationHandler,
  reviewFinancialReceiptHandler,
  reviewBookingCancellationHandler,
  searchCouncilMembersHandler,
  submitGuestBookingReceiptHandler,
  submitFinancialReceiptHandler,
} = require("./financial")._test;

let environment;

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

test("production member search enforces three characters, ten results, and council membership", async () => {
  const result = await searchCouncilMembersHandler({
    auth: { uid: "member" }, data: { organizationId: "o1", query: "mem" },
  });
  if (result.members.length !== 10) throw new Error(`Expected 10 search results, received ${result.members.length}.`);
  for (const row of result.members) {
    assert.deepEqual(Object.keys(row).sort(), ["fullName", "memberNumber", "membershipId", "photoUrl", "userId"]);
  }
  await assert.rejects(
    searchCouncilMembersHandler({ auth: { uid: "member" }, data: { organizationId: "o1", query: "me" } }),
    /three normalized characters/,
  );
  await assert.rejects(
    searchCouncilMembersHandler({ auth: { uid: "outsider" }, data: { organizationId: "o1", query: "mem" } }),
    /Active council membership/,
  );
});

test("financial documents cannot be mutated directly by clients", async () => {
  const db = environment.authenticatedContext("finance").firestore();
  await assertFails(setDoc(doc(db, "organizations/o1/charges/new"), {
    organizationId: "o1", chargeId: "new", amountDueBaisa: 1,
  }));
  await assertFails(setDoc(doc(db, "organizations/o1/financial_settings/main"), {
    organizationId: "o1", onlinePaymentsEnabled: false,
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
});

test("receipt download authorization supports membershipId different from userId", async () => {
  const database = admin.firestore();
  const storagePath = "organizations/o1/members/member/receipts/mismatched-reviewer/receipt.png";
  await database.doc("organizations/o1/transactions/mismatched-reviewer").set({
    organizationId: "o1",
    transactionId: "mismatched-reviewer",
    payerUserId: "member",
    receiptStoragePath: storagePath,
    reviewStatus: "pending",
    status: "pendingReview",
  });
  const signed = await getFinancialReceiptDownloadUrlHandler({
    auth: { uid: "reviewer-different" },
    data: { organizationId: "o1", transactionId: "mismatched-reviewer" },
  }, {
    createDownloadUrl: async (path) => `https://signed.invalid/${encodeURIComponent(path)}`,
  });
  assert.equal(signed.expiresInSeconds, 300);
  assert.match(signed.url, /^https:\/\/signed\.invalid\//);
  await assert.rejects(
    getFinancialReceiptDownloadUrlHandler({
      auth: { uid: "outsider" },
      data: { organizationId: "o1", transactionId: "mismatched-reviewer" },
    }, {
      createDownloadUrl: async () => "https://signed.invalid/forbidden",
    }),
    /Active council membership/,
  );
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
  const chargeIds = new Set();
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
    page.charges.forEach((charge) => chargeIds.add(charge.chargeId));
    pageToken = page.nextPageToken;
    if (pageToken && !tokens.add(pageToken)) throw new Error("Pagination repeated a token.");
  } while (pageToken);
  assert.equal(chargeIds.size, 62);
  assert.ok(chargeIds.has("page-060"));
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
      receiptUrl: `http://127.0.0.1/${receiptId}`,
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
    database, pageSize: 50, nowDate: new Date("2026-07-31T20:30:00.000Z"),
    log: { info(message, values) { logRows.push({ message, values }); } },
  });
  assert.equal(stats.scanned, 205);
  assert.equal((await organization.collection("charges").get()).size, 205);
  const retry = await generateSubscriptionChargesHandler(null, {
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
    database, pageSize: 1, nowDate: new Date("2026-12-31T19:30:00Z"), log: { info() {} },
  });
  assert.ok(stats.scanned >= 2);
  assert.equal((await charges.doc("same-day").get()).get("status"), "unpaid");
  assert.equal((await charges.doc("prior-day").get()).get("status"), "overdue");
  await markFinancialChargesOverdueHandler(null, {
    database, pageSize: 1, nowDate: new Date("2026-12-31T20:30:00Z"), log: { info() {} },
  });
  assert.equal((await charges.doc("same-day").get()).get("status"), "overdue");
});

test("guest booking uses non-member fee, is private, and submits only its own receipt", async () => {
  const database = admin.firestore();
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
  assert.equal(charge.get("amountDueBaisa"), 4000);
  const response = await getGuestBookingChargeHandler({ auth: { uid: "guest" }, data: { organizationId: "o1", bookingId: "guest-booking" } });
  assert.equal(response.charge.balanceBaisa, 4000);
  await assert.rejects(getGuestBookingChargeHandler({ auth: { uid: "outsider" }, data: { organizationId: "o1", bookingId: "guest-booking" } }), /ownership mismatch/);
  await assert.rejects(searchCouncilMembersHandler({ auth: { uid: "guest" }, data: { organizationId: "o1", query: "mem" } }), /Active council membership/);
  const guestDb = environment.authenticatedContext("guest").firestore();
  await assertSucceeds(getDoc(doc(guestDb, `organizations/o1/charges/${charge.id}`)));
  const outsiderDb = environment.authenticatedContext("outsider").firestore();
  await assertFails(getDoc(doc(outsiderDb, `organizations/o1/charges/${charge.id}`)));
  await submitGuestBookingReceiptHandler({ auth: { uid: "guest" }, data: {
    organizationId: "o1", bookingId: "guest-booking", chargeId: charge.id,
    receiptId: "guest-receipt", amountDeclaredBaisa: 1000, balanceBeforeBaisa: 4000,
    receiptUrl: "http://127.0.0.1/guest-receipt",
    receiptStoragePath: "organizations/o1/members/guest/receipts/guest-receipt/receipt.png",
    fileName: "receipt.png", fileType: "image/png",
  } });
  await assert.rejects(submitGuestBookingReceiptHandler({ auth: { uid: "guest" }, data: {
    organizationId: "o1", bookingId: "guest-booking", chargeId: "c0",
    receiptId: "guest-invalid", amountDeclaredBaisa: 1000, balanceBeforeBaisa: 1000,
    receiptUrl: "http://127.0.0.1/guest-invalid",
    receiptStoragePath: "organizations/o1/members/guest/receipts/guest-invalid/receipt.png",
    fileName: "receipt.png", fileType: "image/png",
  } }), /Only your own guest booking charge/);
  await reviewFinancialReceiptHandler({ auth: { uid: "finance" }, data: {
    organizationId: "o1", transactionId: "guest-receipt", decision: "approve",
  } });
  assert.equal((await charge.ref.get()).get("status"), "partial");
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
  await settings.update({ feeMode: "booking", nonMemberBookingFeeBaisa: 0 });
  await createAndApprove("zero-booking");
  assert.equal((await database.collection("organizations/o1/charges").where("bookingId", "==", "zero-booking").get()).size, 0);
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
  assert.equal((await database.doc("organizations/o1/charges/cancel-charge").get()).get("status"), "refundRequired");

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
    database, bucket, nowDate: future, pageSize: 2, log: { info() {} },
  });
  assert.equal(rerun.deleted, 1, "The previous Firestore-error orphan becomes deletable on a healthy rerun.");
});
