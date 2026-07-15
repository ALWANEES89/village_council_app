const crypto = require("node:crypto");

const MUSCAT_TIME_ZONE = "Asia/Muscat";

function assertFiniteNonNegative(value, fieldName) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw new TypeError(`${fieldName} must be a finite non-negative number.`);
  }
  return value;
}

function legacyOmaniRialsToBaisa(value, fieldName = "legacyAmount", { required = true } = {}) {
  if (value === null || value === undefined || value === "") {
    if (required) throw new TypeError(`${fieldName} is required.`);
    return null;
  }
  const number = assertFiniteNonNegative(value, fieldName);
  const baisa = Math.round((number + Number.EPSILON) * 1000);
  if (!Number.isSafeInteger(baisa)) throw new RangeError(`${fieldName} is outside the safe baisa range.`);
  return baisa;
}

function readBaisaField(record, fieldName, { required = true } = {}) {
  const value = record && record[fieldName];
  if (value === null || value === undefined) {
    if (required) throw new TypeError(`${fieldName} is required.`);
    return null;
  }
  assertFiniteNonNegative(value, fieldName);
  if (!Number.isSafeInteger(value)) throw new TypeError(`${fieldName} must be an integer number of baisa.`);
  return value;
}

function readMoneyWithLegacy(record, baisaField, legacyRialField, options = {}) {
  if (record && record[baisaField] !== null && record[baisaField] !== undefined) {
    return readBaisaField(record, baisaField, options);
  }
  return legacyOmaniRialsToBaisa(record && record[legacyRialField], legacyRialField, options);
}

function normalizeArabic(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/[\u064B-\u065F\u0670\u06D6-\u06ED]/g, "")
    .replace(/ـ/g, "")
    .replace(/[أإآٱ]/g, "ا")
    .replace(/ى/g, "ي")
    .replace(/ؤ/g, "و")
    .replace(/ئ/g, "ي")
    .replace(/\s+/g, " ")
    .trim();
}

function searchPrefixes(fullName) {
  const normalized = normalizeArabic(fullName);
  const values = new Set();
  for (const candidate of [normalized, ...normalized.split(" ")]) {
    for (let length = 3; length <= candidate.length; length += 1) values.add(candidate.slice(0, length));
  }
  return [...values].slice(0, 500);
}

function muscatDateParts(date = new Date()) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: MUSCAT_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const values = Object.fromEntries(parts.filter((part) => part.type !== "literal").map((part) => [part.type, part.value]));
  return { year: Number(values.year), month: Number(values.month), day: Number(values.day) };
}

function endOfMuscatDay({ year, month, day }) {
  return new Date(Date.UTC(year, month - 1, day + 1, -4, 0, 0, 0) - 1);
}

function subscriptionPeriod(cycle, date = new Date()) {
  const parts = muscatDateParts(date);
  if (cycle === "annual") {
    return { periodKey: String(parts.year), dueDate: endOfMuscatDay({ year: parts.year, month: 1, day: 1 }) };
  }
  if (cycle === "oneTime") return { periodKey: "one-time", dueDate: endOfMuscatDay(parts) };
  return {
    periodKey: `${parts.year}-${String(parts.month).padStart(2, "0")}`,
    dueDate: endOfMuscatDay({ year: parts.year, month: parts.month, day: 1 }),
  };
}

function dateKey(parts) {
  return parts.year * 10000 + parts.month * 100 + parts.day;
}

function isOverdueInMuscat(dueDate, now = new Date()) {
  if (!(dueDate instanceof Date) || Number.isNaN(dueDate.valueOf())) throw new TypeError("dueDate must be valid.");
  return dateKey(muscatDateParts(now)) > dateKey(muscatDateParts(dueDate));
}

function canonicalChargeKey({
  organizationId,
  membershipId,
  userId,
  accountType = "member",
  chargeType,
  periodKey = "none",
  sourceId = "none",
}) {
  for (const [name, value] of Object.entries({ organizationId, chargeType })) {
    if (typeof value !== "string" || !value.trim()) throw new TypeError(`${name} is required.`);
  }
  if (!["member", "guest"].includes(accountType)) throw new TypeError("accountType is invalid.");
  const accountId = accountType === "guest" ? userId : membershipId;
  if (typeof accountId !== "string" || !accountId.trim()) {
    throw new TypeError(`${accountType === "guest" ? "userId" : "membershipId"} is required.`);
  }
  const canonicalSource = chargeType === "subscription" ? "subscription-period" : String(sourceId || "none");
  // Keep the original member identity format so existing deterministic charge IDs remain stable.
  const identity = accountType === "guest" ? `guest:${accountId}` : accountId;
  const input = [organizationId, identity, chargeType, String(periodKey || "none"), canonicalSource].join("|");
  const digest = crypto.createHash("sha256").update(input).digest("hex").slice(0, 32);
  return `${chargeType}_${digest}`;
}

async function processPaginated({ fetchPage, processItem, pageSize = 200, concurrency = 10 }) {
  if (!Number.isInteger(pageSize) || pageSize < 1 || pageSize > 500) throw new RangeError("Invalid pageSize.");
  let cursor = null;
  let scanned = 0;
  const outcomes = {};
  for (;;) {
    const page = await fetchPage({ cursor, pageSize });
    if (!page || !Array.isArray(page.items)) throw new TypeError("fetchPage returned an invalid page.");
    if (page.items.length === 0) break;
    for (let offset = 0; offset < page.items.length; offset += concurrency) {
      const results = await Promise.allSettled(page.items.slice(offset, offset + concurrency).map(processItem));
      for (const result of results) {
        scanned += 1;
        const key = result.status === "fulfilled" ? String(result.value || "processed") : "errors";
        outcomes[key] = (outcomes[key] || 0) + 1;
      }
      const failure = results.find((result) => result.status === "rejected");
      if (failure) {
        const error = new Error(`Page processing failed after ${scanned} records.`);
        error.cause = failure.reason;
        error.stats = { scanned, outcomes };
        throw error;
      }
    }
    if (!page.nextCursor) {
      if (page.items.length === pageSize) throw new Error("Pagination stopped without a cursor on a full page.");
      break;
    }
    cursor = page.nextCursor;
  }
  return { scanned, outcomes };
}

function receiptStorageIdentity(path) {
  const match = /^organizations\/([^/]+)\/members\/([^/]+)\/receipts\/([^/]+)\/([^/]+)$/.exec(String(path || ""));
  return match ? { organizationId: match[1], userId: match[2], receiptId: match[3], fileName: match[4] } : null;
}

module.exports = {
  MUSCAT_TIME_ZONE,
  canonicalChargeKey,
  endOfMuscatDay,
  isOverdueInMuscat,
  legacyOmaniRialsToBaisa,
  muscatDateParts,
  normalizeArabic,
  processPaginated,
  readBaisaField,
  readMoneyWithLegacy,
  receiptStorageIdentity,
  searchPrefixes,
  subscriptionPeriod,
};
