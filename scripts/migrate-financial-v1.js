#!/usr/bin/env node
/*
 * Idempotent financial-v1 migration. Default mode is DRY RUN.
 * Usage:
 *   node scripts/migrate-financial-v1.js --project <firebase-project-id>
 *   node scripts/migrate-financial-v1.js --project <id> --apply
 *
 * The --apply flag is intentionally required for every real write. Do not run
 * it against production before reviewing the dry-run report and a backup.
 */

let admin;
let FieldValue;
let Timestamp;
const fs = require("node:fs");
const path = require("node:path");
try {
  admin = require("firebase-admin");
  ({ FieldValue, Timestamp } = require("firebase-admin/firestore"));
} catch (_) {
  admin = require("../functions/node_modules/firebase-admin");
  ({ FieldValue, Timestamp } = require("../functions/node_modules/firebase-admin/firestore"));
}
const {
  canonicalChargeKey,
  normalizeArabic,
  readMoneyWithLegacy,
  searchPrefixes,
} = require("../functions/financial_core");

function parseOptions(argv) {
  const values = [...argv];
  const projectIndex = values.indexOf("--project");
  const confirmIndex = values.indexOf("--confirm");
  const manifestIndex = values.indexOf("--manifest");
  return {
    apply: values.includes("--apply"),
    projectId: projectIndex >= 0 ? values[projectIndex + 1] : undefined,
    confirmation: confirmIndex >= 0 ? values[confirmIndex + 1] : undefined,
    manifestPath: manifestIndex >= 0 ? values[manifestIndex + 1] : undefined,
  };
}

function validateOptions(options) {
  if (options.apply && !options.projectId) throw new Error("--apply requires an explicit --project.");
  if (options.apply && options.confirmation !== `APPLY:${options.projectId}`) {
    throw new Error(`--apply requires --confirm APPLY:${options.projectId}.`);
  }
  if (options.apply && !options.manifestPath) {
    throw new Error("--apply requires an explicit --manifest path.");
  }
  if (options.manifestPath) {
    const resolved = path.resolve(options.manifestPath);
    const allowedRoot = path.resolve("migration-manifests");
    if (!resolved.startsWith(`${allowedRoot}${path.sep}`)) {
      throw new Error("--manifest must be inside the ignored migration-manifests directory.");
    }
  }
}

function manifestValue(value) {
  if (value == null || ["string", "number", "boolean"].includes(typeof value)) return value;
  if (value instanceof Timestamp) return { __type: "timestamp", value: value.toDate().toISOString() };
  if (Array.isArray(value)) return value.map(manifestValue);
  if (value.constructor && value.constructor.name === "FieldValue") {
    return { __type: "serverTimestamp" };
  }
  if (typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, manifestValue(item)]));
  }
  return String(value);
}

async function buildManifest(writes, { projectId, db }) {
  const entries = [];
  for (const write of writes) {
    const before = await write.reference.get();
    entries.push({
      path: write.reference.path,
      operation: before.exists ? "merge" : "create",
      before: before.exists ? manifestValue(before.data()) : null,
      after: manifestValue(write.data),
    });
  }
  return {
    schema: "financial-v1-migration-manifest/v1",
    projectId,
    generatedAt: new Date().toISOString(),
    containsSensitiveData: true,
    entries,
  };
}

function writeManifest(manifest, manifestPath) {
  if (!manifestPath) return;
  fs.mkdirSync(path.dirname(manifestPath), { recursive: true });
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, { flag: "wx" });
}

async function commitWrites(writes, { apply, db }) {
  if (!apply || writes.length === 0) return 0;
  let committed = 0;
  for (let offset = 0; offset < writes.length; offset += 400) {
    const batch = db.batch();
    writes.slice(offset, offset + 400).forEach(({ reference, data }) => batch.set(reference, data, { merge: true }));
    await batch.commit();
    committed += Math.min(400, writes.length - offset);
  }
  return committed;
}

async function main(argv = process.argv.slice(2)) {
  const options = parseOptions(argv);
  validateOptions(options);
  admin.initializeApp({ projectId: options.projectId });
  const db = admin.firestore();
  const { apply, projectId, manifestPath } = options;
  console.log(`Financial v1 migration mode: ${apply ? "APPLY" : "DRY RUN"}`);
  if (!projectId) console.warn("No --project supplied; Application Default Credentials project will be used.");
  const writes = [];
  const stats = {
    payments: 0, charges: 0, accounts: 0, directory: 0, skipped: 0,
    invalidAmounts: 0, amountBeforeRials: 0, amountAfterBaisa: 0,
  };
  const skippedRecords = [];
  const memberships = await db.collectionGroup("memberships").get();
  const membershipByOrgUser = new Map();

  for (const membershipDoc of memberships.docs) {
    const organization = membershipDoc.ref.parent.parent;
    if (!organization) continue;
    const membership = membershipDoc.data();
    const organizationId = organization.id;
    membershipByOrgUser.set(`${organizationId}:${membership.userId}`, membershipDoc);
    const accountRef = organization.collection("member_accounts").doc(membershipDoc.id);
    const account = await accountRef.get();
    if (!account.exists) {
      stats.accounts += 1;
      writes.push({ reference: accountRef, data: {
        organizationId,
        membershipId: membershipDoc.id,
        userId: membership.userId,
        planId: null,
        subscriptionStatus: "inactive",
        feeOverrideType: "default",
        customAmountBaisa: null,
        exemptionReason: null,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: "migration-financial-v1",
        migrationVersion: 1,
      }});
    }
    if (membership.status === "active") {
      const [user, legacy] = await Promise.all([
        db.collection("users").doc(membership.userId).get(),
        db.collection("members").doc(membership.userId).get(),
      ]);
      const profile = user.exists ? user.data() : legacy.exists ? legacy.data() : {};
      const fullName = profile.fullName || profile.name;
      if (fullName) {
        const directoryRef = organization.collection("member_directory").doc(membershipDoc.id);
        stats.directory += 1;
        writes.push({ reference: directoryRef, data: {
          membershipId: membershipDoc.id,
          userId: membership.userId,
          fullName,
          memberNumber: String(membership.memberNumber || ""),
          photoUrl: profile.photoUrl || null,
          active: true,
          searchNameNormalized: normalizeArabic(fullName),
          searchPrefixes: searchPrefixes(fullName),
          updatedAt: FieldValue.serverTimestamp(),
          migrationVersion: 1,
        }});
      }
    }
  }

  const payments = await db.collection("payments").get();
  for (const paymentDoc of payments.docs) {
    stats.payments += 1;
    const payment = paymentDoc.data();
    const organizationId = payment.organizationId;
    if (!organizationId) {
      stats.skipped += 1;
      skippedRecords.push({ collection: "payments", id: paymentDoc.id, reason: "missing organizationId" });
      console.warn(`SKIP payment ${paymentDoc.id}: missing organizationId`);
      continue;
    }
    const membership = membershipByOrgUser.get(`${organizationId}:${payment.memberId}`);
    if (!membership) {
      stats.skipped += 1;
      skippedRecords.push({ collection: "payments", id: paymentDoc.id, reason: "membership not found in organization" });
      console.warn(`SKIP payment ${paymentDoc.id}: no council membership for ${payment.memberId}`);
      continue;
    }
    let amountDueBaisa;
    let amountPaidBaisa;
    try {
      amountDueBaisa = readMoneyWithLegacy(payment, "amountBaisa", "amount", { required: true });
      amountPaidBaisa = payment.status === "paid"
        ? amountDueBaisa
        : readMoneyWithLegacy(payment, "amountPaidBaisa", "amountPaid", { required: false }) || 0;
    } catch (error) {
      stats.skipped += 1;
      stats.invalidAmounts += 1;
      skippedRecords.push({ collection: "payments", id: paymentDoc.id, reason: error.message });
      console.warn(`SKIP payment ${paymentDoc.id}: invalid monetary fields`);
      continue;
    }
    stats.amountBeforeRials += payment.amountBaisa != null ? payment.amountBaisa / 1000 : payment.amount;
    stats.amountAfterBaisa += amountDueBaisa;
    const balanceBaisa = Math.max(0, amountDueBaisa - amountPaidBaisa);
    const periodKey = payment.type === "annual" ? `${payment.year}` : `${payment.year}-${String(payment.month || 1).padStart(2, "0")}`;
    const chargeId = canonicalChargeKey({
      organizationId,
      membershipId: membership.id,
      chargeType: "subscription",
      periodKey,
      sourceId: paymentDoc.id,
    });
    const chargeRef = db.collection("organizations").doc(organizationId).collection("charges").doc(chargeId);
    const existing = await chargeRef.get();
    if (existing.exists) continue;
    stats.charges += 1;
    writes.push({ reference: chargeRef, data: {
      chargeId,
      organizationId,
      membershipId: membership.id,
      userId: membership.get("userId"),
      chargeType: "subscription",
      sourceId: paymentDoc.id,
      periodKey,
      idempotencyKey: chargeId,
      titleArabic: payment.type === "annual" ? `اشتراك سنة ${payment.year}` : `اشتراك ${payment.month}/${payment.year}`,
      descriptionArabic: "محوّل من سجل المدفوعات القديم",
      amountDueBaisa,
      amountPaidBaisa,
      balanceBaisa,
      dueDate: payment.dueDate || payment.createdAt || Timestamp.fromDate(new Date(Number(payment.year || 2000), Number(payment.month || 1) - 1, 1)),
      status: payment.status === "paid" ? "paid" : payment.status === "pending" ? "pendingReview" : payment.status === "rejected" ? "rejected" : balanceBaisa < amountDueBaisa ? "partial" : "unpaid",
      lastTransactionId: payment.transactionId || null,
      createdAt: payment.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      createdBy: "migration-financial-v1",
      migrationVersion: 1,
    }});
  }

  console.table(stats);
  console.log(`Amount totals: before=${stats.amountBeforeRials.toFixed(3)} OMR; after=${stats.amountAfterBaisa} baisa (${(stats.amountAfterBaisa / 1000).toFixed(3)} OMR)`);
  console.log(`Skipped report entries: ${skippedRecords.length}`);
  console.log(`Planned idempotent writes: ${writes.length}`);
  const manifest = await buildManifest(writes, { projectId, db });
  writeManifest(manifest, manifestPath);
  await commitWrites(writes, { apply, db });
  console.log(apply ? "Migration writes completed." : "Dry run completed; no data was changed.");
  return { stats, skippedRecords, plannedWrites: writes.length, manifestEntries: manifest.entries.length };
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message || error);
    process.exitCode = 1;
  });
}

module.exports = {
  buildManifest,
  commitWrites,
  main,
  manifestValue,
  parseOptions,
  validateOptions,
  writeManifest,
};
