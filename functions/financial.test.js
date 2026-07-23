const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const {
  canonicalChargeKey,
  isOverdueInMuscat,
  legacyOmaniRialsToBaisa,
  normalizeArabic,
  processPaginated,
  readBaisaField,
  readMoneyWithLegacy,
  receiptStorageIdentity,
  searchPrefixes,
  subscriptionPeriod,
} = require("./financial_core");
const { commitWrites, parseOptions, validateOptions } = require("../scripts/migrate-financial-v1");
const {
  formatOmaniRialForSystemNotification,
  formatOmaniRialNumber,
  renderStructuredNotificationBody,
} = require("./omr_currency");
const {
  notification,
  receiptBytesMatchContentType,
  receiptDownloadRuntime,
  requireBaisa,
  requireNonNegativeBaisa,
  scheduleGate,
} = require("./financial")._test;
const {
  bookingSlotIdentity,
  isPrimaryCouncilOwner,
  serverNotification,
} = require("./production_security")._test;
const { isTrustedNotification } = require("./notifications")._test;
const {
  parseOptions: parseInventoryOptions,
  validateOptions: validateInventoryOptions,
} = require("../scripts/inspect-firestore-readiness");

test("Arabic normalization ignores hamza, diacritics and tatweel", () => {
  assert.equal(normalizeArabic("إِبْــرَاهِيم"), normalizeArabic("ابراهيم"));
  assert.equal(normalizeArabic("أحمد علي"), "احمد علي");
});

test("search prefixes include every compound-name part after three letters", () => {
  const values = searchPrefixes("محمد عبدالله الحارثي");
  assert.ok(values.includes("محمد"));
  assert.ok(values.includes("عبد"));
  assert.ok(values.includes("الحار"));
  assert.ok(!values.includes("مح"));
});

test("subscription periods are stable for monthly and annual plans", () => {
  const date = new Date("2026-07-15T00:00:00Z");
  assert.equal(subscriptionPeriod("monthly", date).periodKey, "2026-07");
  assert.equal(subscriptionPeriod("annual", date).periodKey, "2026");
  assert.equal(subscriptionPeriod("oneTime", date).periodKey, "one-time");
});

test("legacy OMR integer and decimal amounts always become baisa", () => {
  assert.equal(legacyOmaniRialsToBaisa(5), 5000);
  assert.equal(legacyOmaniRialsToBaisa(10), 10000);
  assert.equal(legacyOmaniRialsToBaisa(5.5), 5500);
  assert.equal(readBaisaField({ amountBaisa: 5000 }, "amountBaisa"), 5000);
  assert.equal(readMoneyWithLegacy({ amount: 5 }, "amountBaisa", "amount"), 5000);
  assert.equal(legacyOmaniRialsToBaisa(0), 0);
});

test("OMR notification formatting uses three decimals and no raw baisa text", () => {
  assert.equal(formatOmaniRialNumber(5000), "5.000");
  assert.equal(formatOmaniRialNumber(8000), "8.000");
  assert.equal(formatOmaniRialNumber(12500), "12.500");
  assert.equal(formatOmaniRialNumber(7500), "7.500");
  assert.equal(formatOmaniRialForSystemNotification(12500), "12.500 ر.ع.");
  const body = renderStructuredNotificationBody({
    body: "legacy fallback",
    bodyTemplate: "تم استلام مبلغ {amount}.",
    amountBaisa: 12500,
    currencyCode: "OMR",
  });
  assert.equal(body, "تم استلام مبلغ 12.500 ر.ع.");
  assert.ok(!body.includes("12500"));
  assert.ok(!body.includes("بيسة"));
});

test("legacy notification bodies remain unchanged without structured OMR data", () => {
  assert.equal(renderStructuredNotificationBody({ body: "legacy notification" }), "legacy notification");
  assert.equal(renderStructuredNotificationBody({
    body: "legacy notification",
    bodyTemplate: "{amount}",
    amountBaisa: 5000,
    currencyCode: "USD",
  }), "legacy notification");
});

test("financial notification payload stores structured OMR data and a safe system fallback", () => {
  const payload = notification(
    "member", "o1", "n1", "title", "fallback", "receiptSubmitted", "r1", "reviewer", "receipt",
    { amountBaisa: 12500, currencyCode: "OMR", bodyTemplate: "إيصال بقيمة {amount}." }
  );
  assert.equal(payload.amountBaisa, 12500);
  assert.equal(payload.currencyCode, "OMR");
  assert.equal(payload.bodyTemplate, "إيصال بقيمة {amount}.");
  assert.equal(payload.body, "إيصال بقيمة 12.500 ر.ع.");
  assert.ok(!payload.body.includes("12500"));
  assert.ok(!payload.body.includes("بيسة"));
});

test("monetary validation errors do not expose internal field names or baisa units", () => {
  for (const validate of [
    () => requireBaisa(0, "amountBaisa"),
    () => requireBaisa(1.5, "amountBaisa"),
    () => requireNonNegativeBaisa(-1, "balanceBaisa"),
  ]) {
    assert.throws(validate, (error) => {
      assert.equal(error.code, "invalid-argument");
      assert.equal(error.message, "Invalid monetary amount.");
      assert.doesNotMatch(error.message, /baisa|amountBaisa|balanceBaisa/i);
      return true;
    });
  }
});

test("migration money readers reject missing, negative and non-finite values", () => {
  assert.throws(() => legacyOmaniRialsToBaisa(null), /required/);
  assert.throws(() => legacyOmaniRialsToBaisa(-1), /non-negative/);
  assert.throws(() => legacyOmaniRialsToBaisa(Number.NaN), /finite/);
  assert.throws(() => legacyOmaniRialsToBaisa(Number.POSITIVE_INFINITY), /finite/);
  assert.throws(() => readBaisaField({ amountBaisa: 1.5 }, "amountBaisa"), /integer/);
  assert.equal(readMoneyWithLegacy({}, "amountPaidBaisa", "amountPaid", { required: false }), null);
});

test("migration apply requires project and exact explicit confirmation", async () => {
  assert.throws(() => validateOptions(parseOptions(["--apply"])), /--project/);
  assert.throws(() => validateOptions(parseOptions(["--apply", "--project", "demo"])), /--confirm/);
  assert.throws(() => validateOptions(parseOptions([
    "--apply", "--project", "demo", "--confirm", "APPLY:demo",
  ])), /--manifest/);
  assert.doesNotThrow(() => validateOptions(parseOptions([
    "--apply", "--project", "demo", "--confirm", "APPLY:demo",
    "--manifest", "migration-manifests/test.json",
  ])));
  let batches = 0;
  const fakeDb = { batch: () => { batches += 1; return { set() {}, async commit() {} }; } };
  assert.equal(await commitWrites([{ reference: {}, data: {} }], { apply: false, db: fakeDb }), 0);
  assert.equal(batches, 0, "dry-run must not create a batch or write");
});

test("production inventory is read-only gated and requires an explicit project", () => {
  assert.throws(() => validateInventoryOptions(parseInventoryOptions([])), /--project/);
  assert.throws(() => validateInventoryOptions(parseInventoryOptions([
    "--project", "alrahmat-console",
  ])), /denied by default/);
  assert.doesNotThrow(() => validateInventoryOptions(parseInventoryOptions([
    "--project", "demo-financial-prestaging",
  ])));
});

test("schedule kill switches default to disabled and dry-run before writes", () => {
  const disabled = scheduleGate("generateSubscriptionCharges", { id: "run-1" }, { environment: {} });
  assert.deepEqual(disabled.result, {
    status: "disabled", task: "generateSubscriptionCharges", runId: "run-1", writes: 0,
  });
  const dryRun = scheduleGate("generateSubscriptionCharges", { id: "run-2" }, { environment: {
    FINANCIAL_SCHEDULES_ENABLED: "true",
    FINANCIAL_SCHEDULE_GENERATE_SUBSCRIPTIONS_ENABLED: "true",
  } });
  assert.equal(dryRun.result.status, "dry-run");
  const enabled = scheduleGate("generateSubscriptionCharges", { id: "run-3" }, { environment: {
    FINANCIAL_SCHEDULES_ENABLED: "true",
    FINANCIAL_SCHEDULE_GENERATE_SUBSCRIPTIONS_ENABLED: "true",
    FINANCIAL_SCHEDULE_DRY_RUN: "false",
  } });
  assert.equal(enabled.execute, true);
  assert.equal(enabled.runId, "run-3");
});

test("every sensitive financial and booking callable enforces App Check", () => {
  const financialSource = fs.readFileSync(require.resolve("./financial"), "utf8");
  const securitySource = fs.readFileSync(require.resolve("./production_security"), "utf8");
  for (const source of [financialSource, securitySource]) {
    assert.match(source, /sensitiveCallableOptions\s*=\s*\{[^}]*enforceAppCheck:\s*true/s);
  }
  assert.equal((financialSource.match(/onCall\(\s*sensitiveCallableOptions/g) || []).length, 16);
  assert.equal((securitySource.match(/onCall\(\s*sensitiveCallableOptions/g) || []).length, 5);
});

test("trusted notifications require server provenance and path-bound routing", () => {
  const payload = serverNotification({
    userId: "member", organizationId: "o1", notificationId: "n1",
    title: "title", body: "body", type: "bookingApproved",
    relatedEntityType: "booking", relatedEntityId: "b1", actorUserId: "server",
  });
  assert.equal(isTrustedNotification(payload, { userId: "member", notificationId: "n1" }), true);
  assert.equal(isTrustedNotification({ ...payload, userId: "other" }, { userId: "member", notificationId: "n1" }), false);
  assert.equal(isTrustedNotification({ ...payload, deliverySource: "client" }, { userId: "member", notificationId: "n1" }), false);
});

test("booking slot keys are deterministic and council ownership roles are normalized", () => {
  const first = bookingSlotIdentity({ dayKey: "2026-08-01", startTime: "10:00", endTime: "12:00" });
  const second = bookingSlotIdentity({ dayKey: "2026-08-01", startTime: "10:00", endTime: "12:00" });
  assert.equal(first.slotKey, second.slotKey);
  assert.notEqual(first.slotKey, bookingSlotIdentity({ dayKey: "2026-08-01", startTime: "12:00", endTime: "14:00" }).slotKey);
  assert.equal(isPrimaryCouncilOwner({ roleId: "owner" }), true);
  assert.equal(isPrimaryCouncilOwner({ role: "council_owner" }), true);
  assert.equal(isPrimaryCouncilOwner({ roleId: "chairman" }), false);
});

test("canonical charge keys are stable across migration and generator order", () => {
  const input = { organizationId: "org", membershipId: "m1", chargeType: "subscription", periodKey: "2026-08" };
  const fromGenerator = canonicalChargeKey({ ...input, sourceId: "plan-a" });
  const fromMigration = canonicalChargeKey({ ...input, sourceId: "legacy-payment" });
  assert.equal(fromGenerator, fromMigration);
  assert.notEqual(fromGenerator, canonicalChargeKey({ ...input, periodKey: "2026-09" }));
});

test("Muscat period boundaries and overdue dates do not use UTC day", () => {
  assert.equal(subscriptionPeriod("monthly", new Date("2026-07-31T20:30:00Z")).periodKey, "2026-08");
  assert.equal(subscriptionPeriod("annual", new Date("2026-12-31T20:30:00Z")).periodKey, "2027");
  const due = subscriptionPeriod("monthly", new Date("2026-07-31T20:30:00Z")).dueDate;
  assert.equal(isOverdueInMuscat(due, new Date("2026-08-01T19:59:59Z")), false);
  assert.equal(isOverdueInMuscat(due, new Date("2026-08-01T20:00:00Z")), true);
});

test("pagination reaches every page and retry-safe processing can be idempotent", async () => {
  const values = [1, 2, 3, 4, 5];
  const seen = new Set();
  const fetchPage = async ({ cursor, pageSize }) => {
    const start = cursor || 0;
    const items = values.slice(start, start + pageSize);
    return { items, nextCursor: start + items.length < values.length ? start + items.length : null };
  };
  const processItem = async (value) => {
    if (seen.has(value)) return "exists";
    seen.add(value);
    return "created";
  };
  const first = await processPaginated({ fetchPage, pageSize: 2, processItem });
  const second = await processPaginated({ fetchPage, pageSize: 2, processItem });
  assert.equal(first.scanned, 5);
  assert.equal(second.scanned, 5);
  assert.equal(second.outcomes.exists, 5);
  assert.equal(seen.size, 5);
});

test("pagination fails loudly on a full page without a continuation cursor", async () => {
  await assert.rejects(processPaginated({
    pageSize: 2,
    fetchPage: async () => ({ items: [1, 2], nextCursor: null }),
    processItem: async () => "ok",
  }), /without a cursor/);
});

test("receipt storage identity rejects cross-tenant or malformed paths", () => {
  assert.deepEqual(receiptStorageIdentity("organizations/o1/members/u1/receipts/r1/a.pdf"), {
    organizationId: "o1", userId: "u1", receiptId: "r1", fileName: "a.pdf",
  });
  assert.equal(receiptStorageIdentity("organizations/o1/receipts/r1/a.pdf"), null);
});

test("receipt download runtime is server-only and restricted to the approved demo project", () => {
  assert.equal(receiptDownloadRuntime({
    FUNCTIONS_EMULATOR: "true",
    GCLOUD_PROJECT: "demo-financial-prestaging",
  }), "emulator");
  assert.equal(receiptDownloadRuntime({
    FUNCTIONS_EMULATOR: "false",
    GCLOUD_PROJECT: "demo-financial-prestaging",
  }), "production");
  assert.throws(() => receiptDownloadRuntime({
    FUNCTIONS_EMULATOR: "true",
    GCLOUD_PROJECT: "alrahmat-console",
  }), /restricted to demo-financial-prestaging/);
});

test("receipt byte signatures match only supported content types", () => {
  assert.equal(receiptBytesMatchContentType(Buffer.from("%PDF-1.7\n"), "application/pdf"), true);
  assert.equal(receiptBytesMatchContentType(Buffer.from([0xff, 0xd8, 0xff, 0x00]), "image/jpeg"), true);
  assert.equal(receiptBytesMatchContentType(
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    "image/png"
  ), true);
  assert.equal(receiptBytesMatchContentType(Buffer.from("not-a-pdf"), "application/pdf"), false);
});
