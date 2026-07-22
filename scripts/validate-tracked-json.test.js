"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const {
  validateJsonFiles,
} = require("./validate-tracked-json");

function withTemporaryRepository(run) {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), "tracked-json-validation-"),
  );
  try {
    run(directory);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

function writeFile(repositoryRoot, relativePath, contents) {
  const absolutePath = path.join(repositoryRoot, relativePath);
  fs.mkdirSync(path.dirname(absolutePath), { recursive: true });
  fs.writeFileSync(absolutePath, contents, "utf8");
}

test("accepts valid tracked JSON", () => {
  withTemporaryRepository((repositoryRoot) => {
    writeFile(repositoryRoot, "config/example.json", '{"enabled":true}\n');

    const result = validateJsonFiles(repositoryRoot, ["config/example.json"]);

    assert.equal(result.validCount, 1);
    assert.deepEqual(result.errors, []);
    assert.deepEqual(result.legacyExclusions, []);
  });
});

test("rejects a new empty tracked JSON file", () => {
  withTemporaryRepository((repositoryRoot) => {
    writeFile(repositoryRoot, "config/new-placeholder.json", "");

    const result = validateJsonFiles(repositoryRoot, [
      "config/new-placeholder.json",
    ]);

    assert.deepEqual(result.errors, [
      "config/new-placeholder.json: tracked JSON file is empty",
    ]);
  });
});

test("permits only the three proven legacy placeholders to remain empty", () => {
  withTemporaryRepository((repositoryRoot) => {
    const relativePath = "project-brain/data/dashboard.json";
    writeFile(repositoryRoot, relativePath, "");

    const result = validateJsonFiles(repositoryRoot, [relativePath]);

    assert.deepEqual(result.errors, []);
    assert.deepEqual(result.legacyExclusions, [relativePath]);
  });
});

test("rejects invalid non-empty content even at a legacy path", () => {
  withTemporaryRepository((repositoryRoot) => {
    const relativePath = "project-brain/data/project.json";
    writeFile(repositoryRoot, relativePath, "not-json");

    const result = validateJsonFiles(repositoryRoot, [relativePath]);

    assert.equal(result.errors.length, 1);
    assert.match(result.errors[0], /^project-brain\/data\/project\.json: /);
    assert.deepEqual(result.legacyExclusions, []);
  });
});

test("rejects a missing tracked JSON file", () => {
  withTemporaryRepository((repositoryRoot) => {
    const result = validateJsonFiles(repositoryRoot, ["config/missing.json"]);

    assert.deepEqual(result.errors, [
      "config/missing.json: tracked JSON file is missing",
    ]);
  });
});
