#!/usr/bin/env node
/* Targeted rollback for a reviewed financial-v1 manifest. Default: DRY RUN. */

const fs = require("node:fs");
const path = require("node:path");
let admin;
try {
  admin = require("firebase-admin");
} catch (_) {
  admin = require("../functions/node_modules/firebase-admin");
}
const { Timestamp } = admin.firestore;

function parseOptions(argv) {
  const valueAfter = (name) => {
    const index = argv.indexOf(name);
    return index >= 0 ? argv[index + 1] : undefined;
  };
  return {
    projectId: valueAfter("--project"),
    manifestPath: valueAfter("--manifest"),
    apply: argv.includes("--apply"),
    confirmation: valueAfter("--confirm"),
  };
}

function validateOptions(options) {
  if (!options.projectId || !options.manifestPath) {
    throw new Error("Explicit --project and --manifest are required.");
  }
  const resolved = path.resolve(options.manifestPath);
  const allowedRoot = path.resolve("migration-manifests");
  if (!resolved.startsWith(`${allowedRoot}${path.sep}`)) {
    throw new Error("--manifest must be inside migration-manifests.");
  }
  if (options.apply && options.confirmation !== `ROLLBACK:${options.projectId}`) {
    throw new Error(`--apply requires --confirm ROLLBACK:${options.projectId}.`);
  }
}

function restoreValue(value) {
  if (Array.isArray(value)) return value.map(restoreValue);
  if (value && typeof value === "object") {
    if (value.__type === "timestamp") return Timestamp.fromDate(new Date(value.value));
    if (value.__type === "serverTimestamp") return null;
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, restoreValue(item)]));
  }
  return value;
}

async function main(argv = process.argv.slice(2), options = {}) {
  const parsed = parseOptions(argv);
  validateOptions(parsed);
  const manifest = JSON.parse(fs.readFileSync(parsed.manifestPath, "utf8"));
  if (manifest.schema !== "financial-v1-migration-manifest/v1" ||
      manifest.projectId !== parsed.projectId || !Array.isArray(manifest.entries)) {
    throw new Error("Manifest schema or project does not match.");
  }
  if (admin.apps.length === 0) admin.initializeApp({ projectId: parsed.projectId });
  const database = options.database || admin.firestore();
  const actions = [];
  for (const entry of manifest.entries) {
    const reference = database.doc(entry.path);
    const current = await reference.get();
    if (!current.exists || current.get("migrationVersion") !== 1) {
      actions.push({ reference, operation: "skip-changed", before: entry.before });
    } else {
      actions.push({ reference, operation: entry.before == null ? "delete" : "restore", before: entry.before });
    }
  }
  const stats = actions.reduce((value, action) => {
    value[action.operation] = (value[action.operation] || 0) + 1;
    return value;
  }, {});
  console.log(JSON.stringify({ mode: parsed.apply ? "APPLY" : "DRY RUN", counts: stats }, null, 2));
  if (parsed.apply) {
    for (let offset = 0; offset < actions.length; offset += 400) {
      const batch = database.batch();
      for (const action of actions.slice(offset, offset + 400)) {
        if (action.operation === "delete") batch.delete(action.reference);
        if (action.operation === "restore") batch.set(action.reference, restoreValue(action.before), { merge: false });
      }
      await batch.commit();
    }
  }
  return stats;
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message || error);
    process.exitCode = 1;
  });
}

module.exports = { main, parseOptions, restoreValue, validateOptions };
