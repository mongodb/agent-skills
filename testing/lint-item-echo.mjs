#!/usr/bin/env node
/**
 * Flag eval items that echo their own skill's guidance text rather than testing whether
 * an agent can produce it unaided. An item authored by copy-pasting from SKILL.md or a
 * references/*.md file is grading "can the agent quote the instructions back," not
 * "did the agent apply them" — the AXP/mongodb-skills work found this exact failure mode
 * plausible under author-only authoring with no held-out curator (see DESIGN.md's
 * anti-overfitting phase).
 *
 * Method: 8-word-gram containment of each item's authored text (prompt + expected_output +
 * expectations — NOT `files`, which are legitimate provided input data, not description
 * text) against its own skill's SKILL.md + references. Containment, not Jaccard, because
 * the item is always much shorter than the skill body, so Jaccard would be swamped by that
 * length asymmetry regardless of overlap.
 *
 * Threshold is calibrated from the corpus itself rather than a guessed constant: every
 * item's containment against every OTHER skill's body forms a null distribution of
 * "coincidental" overlap (shared MongoDB vocabulary, common phrasing). An item's own-skill
 * containment is flagged only if it clears the 99th percentile of that null.
 *
 * Advisory today (prints, exits 0) until the threshold has been sanity-checked against a
 * few real PRs — see .github/workflows/validate-eval-cases.yml.
 */
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { globSync } from "glob";

const here = dirname(fileURLToPath(import.meta.url));
const N = 8; // n-gram size
const STRICT = process.argv.includes("--strict");

const STOPWORDS = new Set(
  "a an the of to in on for and or is are was were be been being with as at by from this " +
    "that it its into if then else not do does did you your".split(" "),
);

function tokenize(text) {
  return (text ?? "")
    .toLowerCase()
    .replace(/```[\s\S]*?```/g, " ") // fenced code blocks are not prose to compare
    .replace(/[^a-z0-9\s]/g, " ")
    .split(/\s+/)
    .filter((w) => w && !STOPWORDS.has(w));
}

function ngrams(tokens, n) {
  const grams = new Set();
  for (let i = 0; i + n <= tokens.length; i++) {
    grams.add(tokens.slice(i, i + n).join(" "));
  }
  return grams;
}

// containment = fraction of the ITEM's n-grams that also appear in the corpus
function containment(itemGrams, corpusGrams) {
  if (itemGrams.size === 0) return 0;
  let hits = 0;
  for (const g of itemGrams) if (corpusGrams.has(g)) hits++;
  return hits / itemGrams.size;
}

// Longest run of consecutive item n-grams that each independently appear in the corpus —
// an approximation of "verbatim shared span," cheap because item text is always short
// (one prompt/expected_output, not the whole corpus).
function longestSharedSpan(tokens, corpusGrams) {
  let best = 0;
  let run = 0;
  for (let i = 0; i + N <= tokens.length; i++) {
    const g = tokens.slice(i, i + N).join(" ");
    if (corpusGrams.has(g)) {
      run++;
      best = Math.max(best, run);
    } else {
      run = 0;
    }
  }
  return best === 0 ? 0 : best + N - 1; // consecutive overlapping n-grams -> word span length
}

function skillCorpusText(skillName) {
  const dir = join(here, "..", "skills", skillName);
  const parts = [];
  const skillMd = join(dir, "SKILL.md");
  try {
    parts.push(readFileSync(skillMd, "utf8"));
  } catch {
    /* no SKILL.md is a lint failure elsewhere (validate-skills.yml), not ours to report */
  }
  const refsDir = join(dir, "references");
  try {
    for (const f of readdirSync(refsDir)) {
      if (f.endsWith(".md")) parts.push(readFileSync(join(refsDir, f), "utf8"));
    }
  } catch {
    /* no references/ dir is fine */
  }
  return parts.join("\n\n");
}

function itemText(ev) {
  const parts = [];
  if (ev.prompt) parts.push(ev.prompt);
  if (ev.workflow) for (const t of ev.workflow) parts.push(t.prompt);
  if (ev.expected_output) parts.push(ev.expected_output);
  if (ev.expectations) parts.push(ev.expectations.join("\n"));
  return parts.join("\n\n");
}

const evalFiles = globSync(join(here, "*/evals/evals.json")).sort();
const bySkill = evalFiles.map((file) => {
  const doc = JSON.parse(readFileSync(file, "utf8"));
  const skillName = doc.skill_name;
  return { file, skillName, doc, corpusGrams: ngrams(tokenize(skillCorpusText(skillName)), N) };
});

// Build the cross-skill null distribution: every item's containment against every OTHER
// skill's corpus.
const nullSamples = [];
const perItem = []; // {skillName, file, ev, ownContainment}

for (const { file, skillName, doc, corpusGrams: ownCorpus } of bySkill) {
  for (const ev of doc.evals ?? []) {
    const tokens = tokenize(itemText(ev));
    if (tokens.length < N) continue; // too short to judge
    const itemGrams = ngrams(tokens, N);

    perItem.push({
      skillName,
      file,
      id: ev.id,
      tokens,
      itemGrams,
      ownContainment: containment(itemGrams, ownCorpus),
    });

    for (const other of bySkill) {
      if (other.skillName === skillName) continue;
      nullSamples.push(containment(itemGrams, other.corpusGrams));
    }
  }
}

nullSamples.sort((a, b) => a - b);
const p99 =
  nullSamples.length === 0
    ? 0.15 // fallback if only one skill has cases at all
    : nullSamples[Math.min(nullSamples.length - 1, Math.floor(0.99 * nullSamples.length))];
const threshold = Math.max(p99, 0.15); // never flag on near-zero coincidental overlap alone

console.log(
  `Cross-skill null: ${nullSamples.length} samples, p99=${p99.toFixed(3)}, ` +
    `threshold=${threshold.toFixed(3)}`,
);

let flagged = 0;
for (const item of perItem) {
  if (item.ownContainment <= threshold) continue;
  flagged++;
  const own = bySkill.find((s) => s.skillName === item.skillName);
  const span = longestSharedSpan(item.tokens, own.corpusGrams);
  console.log(
    `⚠ ${item.file} case ${item.id}: ${(item.ownContainment * 100).toFixed(0)}% containment ` +
      `against ${item.skillName} (threshold ${(threshold * 100).toFixed(0)}%), ` +
      `longest shared span ~${span} words`,
  );
}

if (flagged === 0) {
  console.log("No echoing items found.");
} else {
  console.log(`\n${flagged} item(s) look like they echo their own skill's guidance text.`);
  console.log(
    "Not necessarily wrong — some overlap is expected for MongoDB vocabulary — but worth a " +
      "second look: does this item test whether the agent APPLIES the guidance, or just " +
      "whether it can quote it?",
  );
}

// Advisory until the threshold's been sanity-checked against a few real PRs of item
// additions (see the workflow comment). Flip with --strict once that's done.
process.exit(STRICT && flagged > 0 ? 1 : 0);
