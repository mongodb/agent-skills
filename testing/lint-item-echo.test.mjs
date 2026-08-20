// Pins the tokenizer/span behaviour that makes lint-item-echo.mjs a true port of
// agent-skills-evals/inspect/analysis/echo.py. The fixtures and expected values here are
// IDENTICAL to test_echo.py's — that is the cross-repo parity mechanism: neither repo's
// CI can import the other, so both pin the same numbers.
//
// Uses node's built-in test runner — no new dependency on the testing/ toolchain.
import { test } from "node:test";
import assert from "node:assert/strict";

import { containment, longestVerbatimSpan, ngrams, tokenize } from "./lint-item-echo.mjs";

// Same fixtures as test_echo.py.
const SKILL = `
    Follow the ESR rule when building a compound index: equality fields first, then sort
    fields, then range fields. A filter on an exact value with a descending sort should use
    a compound index whose leading key is the equality field.
`;
const HONEST_ITEM = `
    Queries against the events collection that filter by an exact type and sort by
    timestamp descending are slow. Diagnose the cause and create an appropriate index.
`;
const COPIED_ITEM = `
    Follow the ESR rule when building a compound index: equality fields first, then sort
    fields, then range fields. A filter on an exact value with a descending sort should use
    a compound index whose leading key is the equality field.
`;
const OTHER_SKILL_A = `
    Configure maxPoolSize to match expected concurrency. A serverless function should keep
    the pool small and reuse the client across invocations rather than reconnecting.
`;

const N = 8; // echo-thresholds.json's n

function containmentOf(itemText, skillText) {
  return containment(ngrams(tokenize(itemText), N), ngrams(tokenize(skillText), N));
}

test("tokenize: lowercases and splits", () => {
  assert.ok(tokenize("ESR rule", { stripDomain: false }).includes("esr"));
});

test("tokenize: strips domain vocabulary by default", () => {
  const toks = tokenize("create a compound index on the collection");
  assert.ok(!toks.includes("index") && !toks.includes("collection"));
});

test("tokenize: retains domain words when asked", () => {
  assert.ok(tokenize("create a compound index", { stripDomain: false }).includes("index"));
});

test("tokenize: operator sigils normalised", () => {
  assert.ok(tokenize("$match stage", { stripDomain: false }).includes("match"));
});

test("tokenize: hyphenated words stay one token", () => {
  assert.deepEqual(tokenize("outer-join", { stripDomain: false }), ["outer-join"]);
});

test("tokenize: fenced code blocks are stripped", () => {
  // code examples are not prose to quote; an item restating one is legitimate reuse
  assert.deepEqual(tokenize("intro text\n```python\ndb.things.find({})\n```\nafter"), [
    "intro",
    "text",
    "after",
  ]);
});

test("tokenize: empty text", () => {
  assert.deepEqual(tokenize(""), []);
});

test("containment: identical text is fully contained", () => {
  assert.equal(containmentOf(COPIED_ITEM, SKILL), 1.0);
});

test("containment: unrelated text is zero", () => {
  assert.equal(containmentOf(HONEST_ITEM, OTHER_SKILL_A), 0.0);
});

test("containment: honest item scores below a copy", () => {
  assert.ok(containmentOf(HONEST_ITEM, SKILL) < containmentOf(COPIED_ITEM, SKILL));
});

test("containment: short item cannot be judged", () => {
  assert.equal(containmentOf("create an index", SKILL), 0.0);
});

test("span: finds a long quotation", () => {
  assert.ok(
    longestVerbatimSpan(
      tokenize(COPIED_ITEM, { stripDomain: false }),
      tokenize(SKILL, { stripDomain: false }),
    ) > 20,
  );
});

test("span: short for unrelated text", () => {
  assert.ok(
    longestVerbatimSpan(
      tokenize(HONEST_ITEM, { stripDomain: false }),
      tokenize(OTHER_SKILL_A, { stripDomain: false }),
    ) < 5,
  );
});

test("span: zero on empty", () => {
  assert.equal(longestVerbatimSpan([], tokenize(SKILL, { stripDomain: false })), 0);
});
