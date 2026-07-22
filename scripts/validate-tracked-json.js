"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

// These files were committed empty in 82f1cd9 with the initial Project Brain
// scaffold. Repository-wide history and consumer searches show that they have
// never had a reader, writer, schema, or generated content. They remain only
// because deleting user files is outside this QA round's safety boundary.
const LEGACY_EMPTY_JSON_PLACEHOLDERS = new Set([
  "project-brain/data/dashboard.json",
  "project-brain/data/project.json",
  "project-brain/data/versions.json",
]);

function findRepositoryRoot(startDirectory = process.cwd()) {
  return execFileSync("git", ["rev-parse", "--show-toplevel"], {
    cwd: startDirectory,
    encoding: "utf8",
  }).trim();
}

function listTrackedJsonFiles(repositoryRoot) {
  const output = execFileSync(
    "git",
    ["ls-files", "-z", "--", "*.json"],
    {
      cwd: repositoryRoot,
      encoding: "utf8",
    },
  );

  return output.split("\0").filter(Boolean);
}

function validateJsonFiles(repositoryRoot, relativePaths) {
  const errors = [];
  const legacyExclusions = [];
  let validCount = 0;

  for (const relativePath of relativePaths) {
    const absolutePath = path.join(repositoryRoot, relativePath);

    if (!fs.existsSync(absolutePath)) {
      errors.push(`${relativePath}: tracked JSON file is missing`);
      continue;
    }

    const contents = fs.readFileSync(absolutePath, "utf8");
    if (contents.trim().length === 0) {
      if (LEGACY_EMPTY_JSON_PLACEHOLDERS.has(relativePath)) {
        legacyExclusions.push(relativePath);
        continue;
      }
      errors.push(`${relativePath}: tracked JSON file is empty`);
      continue;
    }

    try {
      JSON.parse(contents);
      validCount += 1;
    } catch (error) {
      errors.push(`${relativePath}: ${error.message}`);
    }
  }

  return { validCount, errors, legacyExclusions };
}

function validateTrackedJson(repositoryRoot) {
  return validateJsonFiles(
    repositoryRoot,
    listTrackedJsonFiles(repositoryRoot),
  );
}

function main() {
  const repositoryRoot = findRepositoryRoot();
  const result = validateTrackedJson(repositoryRoot);

  console.log(`Valid tracked JSON files: ${result.validCount}`);

  if (result.legacyExclusions.length > 0) {
    console.log("Legacy empty JSON placeholders (explicit exclusions):");
    for (const relativePath of result.legacyExclusions) {
      console.log(`- ${relativePath}`);
    }
  }

  if (result.errors.length > 0) {
    console.error("Tracked JSON validation failed:");
    for (const error of result.errors) {
      console.error(`- ${error}`);
    }
    process.exitCode = 1;
    return;
  }

  console.log("Tracked JSON validation passed.");
}

if (require.main === module) {
  main();
}

module.exports = {
  LEGACY_EMPTY_JSON_PLACEHOLDERS,
  findRepositoryRoot,
  listTrackedJsonFiles,
  validateJsonFiles,
  validateTrackedJson,
};
