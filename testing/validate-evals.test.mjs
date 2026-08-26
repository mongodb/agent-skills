// Pins the `files` containment rule that the evals.schema.json regex alone cannot enforce.
//
// The schema pattern rejects a leading '/' and any '..' segment, but a regex cannot reason
// about what a path RESOLVES to. validate-evals.mjs::filesEntryEscapes is the authoritative
// check, and it is what blocks cross-skill answer-key handover: a case pointing at another
// skill's evals/ or at ../../skills/<name>/SKILL.md would hand the agent its own answer key,
// pass the schema regex, and be invisible to lint-item-echo.mjs (which excludes `files` from
// overlap analysis because they are provided input data). Without this test that guard is
// code that only runs in CI with no failure when it regresses.
//
// Uses node's built-in test runner — no new dependency on the testing/ toolchain.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { filesEntryEscapes, checkAssetsExist, duplicateIds } from "./validate-evals.mjs";

const EVALS_DIR = "/repo/testing/mongodb-query-optimizer/evals";
const CONTRACT = {
  FIXTURE_DIR: "fixtures",
  FIXTURE_EXT: ".js",
  RESERVED_SEEDS: new Set(["clean_slate"]),
};

test("filesEntryEscapes: paths inside the evals dir are contained", () => {
  assert.equal(filesEntryEscapes(EVALS_DIR, "fixtures/seeded_events.js"), false);
  assert.equal(filesEntryEscapes(EVALS_DIR, "asset.json"), false);
  assert.equal(filesEntryEscapes(EVALS_DIR, "sub/dir/asset.json"), false);
});

test("filesEntryEscapes: parent traversal escapes — the cross-skill answer-key handover", () => {
  // Reaching another skill's evals dir requires '..', which the schema regex forbids as a
  // segment — but a regex forbidding '..' and a resolve() that catches '..' are two different
  // defenses. This pins the latter, which is the one that reasons about the resolved target.
  assert.equal(
    filesEntryEscapes(EVALS_DIR, "../mongodb-search-and-ai/evals/seeded_movies.js"),
    true,
  );
  assert.equal(
    filesEntryEscapes(EVALS_DIR, "../../skills/mongodb-query-optimizer/SKILL.md"),
    true,
  );
});

test("filesEntryEscapes: absolute paths escape (resolve, not join, semantics)", () => {
  // join('/a', '/etc/x') nests to '/a/etc/x'; resolve() honours the absolute and yields
  // '/etc/x'. The harness uses Path('/a') / '/etc/x' (resolve semantics), so this matches.
  assert.equal(filesEntryEscapes(EVALS_DIR, "/etc/passwd"), true);
});

test("checkAssetsExist: a cross-skill files ref is rejected even when the target exists", () => {
  // The answer-key file under another skill DOES exist — existence is not the point,
  // containment is. This is the case the schema regex + an existence-only check would miss.
  const root = mkdtempSync(join(tmpdir(), "evals-"));
  const skillA = join(root, "skill-a", "evals");
  const skillB = join(root, "skill-b", "evals");
  mkdirSync(skillA, { recursive: true });
  mkdirSync(skillB, { recursive: true });
  writeFileSync(join(skillB, "answer.md"), "the answer key");
  const doc = { evals: [{ id: 1, files: ["../../skill-b/evals/answer.md"] }] };
  const problems = checkAssetsExist(skillA, doc, CONTRACT);
  assert.ok(
    problems.some((p) => p.includes("escapes the evals dir")),
    `expected an escape finding, got: ${JSON.stringify(problems)}`,
  );
});

test("checkAssetsExist: a contained, existing file is accepted", () => {
  const root = mkdtempSync(join(tmpdir(), "evals-"));
  const evalsDir = join(root, "evals");
  mkdirSync(evalsDir, { recursive: true });
  writeFileSync(join(evalsDir, "asset.json"), "{}");
  const doc = { evals: [{ id: 1, files: ["asset.json"] }] };
  assert.deepEqual(checkAssetsExist(evalsDir, doc, CONTRACT), []);
});

test("checkAssetsExist: a files entry pointing at a directory is rejected", () => {
  // existsSync() treats directories as existing, but `files` are asset files the harness
  // inlines. A directory would validate here and fail downstream as EISDIR.
  const root = mkdtempSync(join(tmpdir(), "evals-"));
  const evalsDir = join(root, "evals");
  mkdirSync(join(evalsDir, "assets"), { recursive: true });
  const doc = { evals: [{ id: 1, files: ["assets"] }] };
  const problems = checkAssetsExist(evalsDir, doc, CONTRACT);
  assert.ok(
    problems.some((p) => p.includes("directory, not a file")),
    `expected a not-a-file finding, got: ${JSON.stringify(problems)}`,
  );
});

test("checkAssetsExist: a missing contained file is reported as not-found (not as an escape)", () => {
  const root = mkdtempSync(join(tmpdir(), "evals-"));
  const evalsDir = join(root, "evals");
  mkdirSync(evalsDir, { recursive: true });
  const doc = { evals: [{ id: 1, files: ["missing.json"] }] };
  const problems = checkAssetsExist(evalsDir, doc, CONTRACT);
  assert.ok(problems.some((p) => p.includes("not found")));
  assert.ok(problems.every((p) => !p.includes("escapes")));
});

test("duplicateIds: a reused case id is reported", () => {
  // The harness keys qa_runs metadata and mutation analysis on the id; a duplicate merges
  // two unrelated cases into one identity. ajv cannot express this (uniqueItems compares
  // whole items), so the check lives in validate-evals.mjs and is pinned here.
  const doc = { evals: [{ id: 7, prompt: "a" }, { id: 8, prompt: "b" }, { id: 7, prompt: "c" }] };
  assert.deepEqual(duplicateIds(doc), ["case id 7 is used twice in this file"]);
});

test("duplicateIds: unique ids and id-less cases are clean", () => {
  // Missing ids are the schema's finding (id is required), not this check's.
  assert.deepEqual(duplicateIds({ evals: [{ id: 1 }, { id: 2 }] }), []);
  assert.deepEqual(duplicateIds({ evals: [{ prompt: "no id yet" }] }), []);
});
