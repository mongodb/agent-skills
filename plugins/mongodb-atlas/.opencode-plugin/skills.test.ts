// Unit tests for the SKILL.md frontmatter parser. Runs with Node's built-in
// test runner and type-stripping — no dependencies to install:
//   node --test plugins/mongodb/.opencode-plugin/skills.test.ts

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { loadBundledSkills, parseFrontmatter } from "./skills.ts";

test("parseFrontmatter extracts description and body", () => {
  const raw =
    "---\nname: example\ndescription: Does something useful.\nlicense: Apache-2.0\n---\n\n# Example\n\nBody text.\n";
  const parsed = parseFrontmatter(raw, "example");
  assert.equal(parsed.description, "Does something useful.");
  assert.equal(parsed.content, "\n# Example\n\nBody text.\n");
});

test("parseFrontmatter handles quoted descriptions", () => {
  const raw = '---\nname: example\ndescription: "Quoted description."\n---\nbody\n';
  const parsed = parseFrontmatter(raw, "example");
  assert.equal(parsed.description, "Quoted description.");
});

test("parseFrontmatter throws on missing frontmatter", () => {
  assert.throws(() => parseFrontmatter("no frontmatter here", "example"), /Missing skill frontmatter/);
});

test("parseFrontmatter throws on missing description", () => {
  const raw = "---\nname: example\n---\nbody\n";
  assert.throws(() => parseFrontmatter(raw, "example"), /Missing "description"/);
});

test("parseFrontmatter handles single-quoted descriptions", () => {
  const raw = "---\ndescription: 'It''s quoted.'\n---\nbody\n";
  assert.equal(parseFrontmatter(raw, "example").description, "It's quoted.");
});

test("parseFrontmatter folds `>` and `>-` block scalars", () => {
  for (const indicator of [">", ">-"]) {
    const raw = `---\nname: example\ndescription: ${indicator}\n  First line\n  second line.\nlicense: Apache-2.0\n---\nbody\n`;
    assert.equal(parseFrontmatter(raw, "example").description, "First line second line.");
  }
});

test("parseFrontmatter keeps newlines in `|` block scalars", () => {
  const raw = "---\ndescription: |\n  Line one.\n  Line two.\nlicense: x\n---\nbody\n";
  assert.equal(parseFrontmatter(raw, "example").description, "Line one.\nLine two.");
});

test("parseFrontmatter joins plain multi-line scalars", () => {
  const raw = "---\ndescription: Starts here\n  and continues.\n---\nbody\n";
  assert.equal(parseFrontmatter(raw, "example").description, "Starts here and continues.");
});

// Guards against the parser silently mis-reading a real skill (e.g. returning
// ">" for a block scalar), which would stop OpenCode from ever advertising it.
// Runs against both the canonical repo-root skills/ (always present) and the
// plugin's own skills/ copy — the same copy the OpenCode package ships.
function assertSkillsParse(dir: string) {
  const skills = loadBundledSkills(dir);
  assert.ok(skills.length > 0, `no skills found under ${dir}/skills`);
  for (const skill of skills) {
    assert.ok(skill.description.length > 20, `${skill.id}: description too short`);
    assert.doesNotMatch(skill.description, /^[|>][-+]?$/, `${skill.id}: unparsed block scalar`);
    assert.doesNotMatch(skill.description, /^["']/, `${skill.id}: unstripped quote`);
  }
}

test("every canonical repo skill parses", () => {
  assertSkillsParse(join(import.meta.dirname, "..", "..", ".."));
});

test("every bundled skill parses", () => {
  assertSkillsParse(join(import.meta.dirname, ".."));
});
