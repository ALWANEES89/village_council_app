#!/usr/bin/env node
/*
 * Read-only schema inventory. It never calls set/update/delete/batch/transaction.
 * Production is denied unless two explicit switches are supplied in a separately
 * authorized session. Output contains aggregate counts only, never document IDs,
 * names, phone numbers, bank fields, receipt paths, or monetary values.
 */

const fs = require("node:fs");
const path = require("node:path");
let admin;
try {
  admin = require("firebase-admin");
} catch (_) {
  admin = require("../functions/node_modules/firebase-admin");
}

const PRODUCTION_PROJECT = "alrahmat-console";

function parseOptions(argv) {
  const valueAfter = (name) => {
    const index = argv.indexOf(name);
    return index >= 0 ? argv[index + 1] : undefined;
  };
  return {
    projectId: valueAfter("--project"),
    output: valueAfter("--output"),
    allowProductionRead: argv.includes("--allow-production-read"),
    confirmation: valueAfter("--confirm"),
  };
}

function validateOptions(options) {
  if (!options.projectId) throw new Error("An explicit --project is required.");
  if (options.projectId === PRODUCTION_PROJECT &&
      (!options.allowProductionRead || options.confirmation !== `READ_ONLY:${PRODUCTION_PROJECT}`)) {
    throw new Error("Production inventory is denied by default and requires separate read-only authorization.");
  }
  if (options.output) {
    const resolved = path.resolve(options.output);
    const allowedRoot = path.resolve("migration-manifests");
    if (!resolved.startsWith(`${allowedRoot}${path.sep}`)) {
      throw new Error("--output must be inside the ignored migration-manifests directory.");
    }
  }
}

function emptyOrganizationStats() {
  return {
    organizations: 0,
    memberships: 0,
    membershipIdUserIdMismatch: 0,
    membershipsMissingUserId: 0,
    duplicateOrganizationUsers: 0,
    primaryOwnerCount: 0,
    legacySystemOwnerMembershipRole: 0,
    legacyOwnerRole: 0,
    memberAccessDocuments: 0,
    charges: 0,
    invalidBaisaCharges: 0,
    transactions: 0,
    invalidBaisaTransactions: 0,
    bookings: 0,
    activeBookingsMissingSlotKey: 0,
    bookingSlots: 0,
    financialProfiles: 0,
  };
}

function hasUnsafeMoney(data, fields) {
  return fields.some((field) => data[field] != null &&
    (!Number.isSafeInteger(data[field]) || data[field] < 0));
}

async function main(argv = process.argv.slice(2), options = {}) {
  const parsed = parseOptions(argv);
  validateOptions(parsed);
  if (admin.apps.length === 0) admin.initializeApp({ projectId: parsed.projectId });
  const database = options.database || admin.firestore();
  const stats = emptyOrganizationStats();
  const organizations = await database.collection("organizations").get();
  stats.organizations = organizations.size;
  for (const organization of organizations.docs) {
    const [memberships, access, charges, transactions, bookings, slots, profiles] = await Promise.all([
      organization.ref.collection("memberships").get(),
      organization.ref.collection("member_access").get(),
      organization.ref.collection("charges").get(),
      organization.ref.collection("transactions").get(),
      organization.ref.collection("bookings").get(),
      organization.ref.collection("booking_slots").get(),
      organization.ref.collection("financial_profile").get(),
    ]);
    const users = new Map();
    for (const membership of memberships.docs.filter((document) => document.id !== "_meta")) {
      stats.memberships += 1;
      const data = membership.data();
      const userId = typeof data.userId === "string" && data.userId ? data.userId : null;
      if (!userId) stats.membershipsMissingUserId += 1;
      if (userId && membership.id !== userId) stats.membershipIdUserIdMismatch += 1;
      if (userId) users.set(userId, (users.get(userId) || 0) + 1);
      const roles = [data.roleId, data.role];
      if (data.isPrimaryOwner === true || roles.some((role) => ["owner", "council_owner"].includes(role))) {
        stats.primaryOwnerCount += 1;
      }
      if (roles.includes("system_owner")) stats.legacySystemOwnerMembershipRole += 1;
      if (roles.some((role) => ["owner", "council_owner"].includes(role))) stats.legacyOwnerRole += 1;
    }
    stats.duplicateOrganizationUsers += [...users.values()].filter((count) => count > 1).length;
    stats.memberAccessDocuments += access.size;
    stats.charges += charges.size;
    stats.invalidBaisaCharges += charges.docs.filter((document) => hasUnsafeMoney(
      document.data(), ["amountDueBaisa", "amountPaidBaisa", "balanceBaisa"],
    )).length;
    stats.transactions += transactions.size;
    stats.invalidBaisaTransactions += transactions.docs.filter((document) => hasUnsafeMoney(
      document.data(), ["amountDeclaredBaisa", "amountAllocatedBaisa"],
    )).length;
    stats.bookings += bookings.size;
    stats.activeBookingsMissingSlotKey += bookings.docs.filter((document) =>
      ["pending", "approved", "cancellationRequested"].includes(document.get("status")) &&
      !document.get("slotKey")).length;
    stats.bookingSlots += slots.size;
    stats.financialProfiles += profiles.size;
  }
  const report = {
    schema: "production-readiness-inventory/v1",
    projectId: parsed.projectId,
    generatedAt: new Date().toISOString(),
    readOnly: true,
    containsPersonalOrFinancialValues: false,
    counts: stats,
  };
  console.log(JSON.stringify(report, null, 2));
  if (parsed.output) {
    fs.mkdirSync(path.dirname(parsed.output), { recursive: true });
    fs.writeFileSync(parsed.output, `${JSON.stringify(report, null, 2)}\n`, { flag: "wx" });
  }
  return report;
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message || error);
    process.exitCode = 1;
  });
}

module.exports = { emptyOrganizationStats, main, parseOptions, validateOptions };
