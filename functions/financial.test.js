const test = require("node:test");
const assert = require("node:assert/strict");

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
  assert.doesNotThrow(() => validateOptions(parseOptions([
    "--apply", "--project", "demo", "--confirm", "APPLY:demo",
  ])));
  let batches = 0;
  const fakeDb = { batch: () => { batches += 1; return { set() {}, async commit() {} }; } };
  assert.equal(await commitWrites([{ reference: {}, data: {} }], { apply: false, db: fakeDb }), 0);
  assert.equal(batches, 0, "dry-run must not create a batch or write");
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
