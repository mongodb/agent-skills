#!/usr/bin/env node
/**
 * Flag eval items that echo their own skill's guidance text rather than testing whether
 * an agent can produce it unaided. An item authored by copy-pasting from SKILL.md or a
 * references/*.md file is grading "can the agent quote the instructions back," not
 * "did the agent apply them" — the AXP/mongodb-skills work found this exact failure mode
 * plausible under author-only authoring with no held-out curator (see DESIGN.md's
 * anti-overfitting phase).
 *
 * Three checks, in increasing order of how much they can actually prove:
 *
 * 1. **Static containment** (all items). 8-word-gram containment of the item's authored
 *    text against its own skill's body, compared against a cross-skill null. Containment,
 *    not Jaccard, because the item is always much shorter than the skill body, so Jaccard
 *    would be swamped by that length asymmetry regardless of overlap.
 *
 *    Reported per field, not pooled, because the two fields mean different things. High
 *    overlap in `prompt` is leakage: the question is carrying its own answer. High overlap
 *    in `expected_output`/`expectations` is often unavoidable and fine — if the correct
 *    answer IS the rule, an item that states the rule is correctly authored. Pooling them
 *    (the original version of this lint) mostly measured the second and called it the first.
 *
 * 2. **Verbatim span.** A shared run of ≥ maxVerbatimSpan tokens is a quotation whatever
 *    the null says.
 *
 * 3. **Co-movement** (`--base <ref>`, the check that needs no held-out set). If a PR edits
 *    a skill's guidance AND that edit raises an item's containment, that is teaching to the
 *    test — detectable from the diff alone, no curator and no golden corpus required. This
 *    is the highest-value check here and it is pure string processing; it mirrors
 *    agent-skills-evals/inspect/analysis/echo.py::comovement.
 *
 * Thresholds come from testing/echo-thresholds.json, shared with that Python module rather
 * than re-guessed here. Note what the null actually does on real data: it collapses to
 * 0.000 (two skills almost never share an 8-gram), so the percentile rule alone would flag
 * 2% overlap, and `minAbsoluteContainment` is the threshold that does the real work. This
 * is NOT a "calibrated, no constants" design, and describing it as one would misrepresent
 * where the sensitivity comes from.
 *
 * Advisory today (prints, exits 0) unless --strict is passed.
 * TODO(2026-09-30, cory.bullinger): flip validate-eval-cases.yml to --strict once the
 * thresholds have been checked against a few real PRs of item additions, or delete this
 * TODO and record why advisory is the permanent answer. Do not let it sit unowned.
 */
import { execFileSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { globSync } from "glob";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, "..");

function readJson(file) {
  const text = readFileSync(file, "utf8");
  try {
    return JSON.parse(text);
  } catch (err) {
    console.error(`✗ ${file}\n    not valid JSON: ${err.message}`);
    process.exit(1);
  }
}

const T = readJson(join(here, "echo-thresholds.json"));
const N = T.n;
const PERCENTILE = T.percentile;
const MIN_CONTAINMENT = T.minAbsoluteContainment;
const MAX_SPAN = T.maxVerbatimSpan;
const CO_MOVEMENT_MIN_DELTA = T.coMovementMinDelta;

const args = process.argv.slice(2);
const STRICT = args.includes("--strict");
const baseIdx = args.indexOf("--base");
const BASE_REF = baseIdx !== -1 ? args[baseIdx + 1] : null;

// In GitHub Actions, surface findings as PR annotations (file-attached ::warning) so they
// appear in the Files Changed review view even while the lint is advisory (exit 0). A stdout
// line in a green workflow log is invisible to a reviewer; an annotation is not. The lint
// stays non-blocking — these are ::warning, not ::error — matching the advisory intent and
// the dated TODO to flip to --strict. Locally (no GITHUB_ACTIONS), keep the human-readable
// line so `node lint-item-echo.mjs` output is unchanged.
const IN_CI = process.env.GITHUB_ACTIONS === "true";

/**
 * Report one finding. `file` is the evals.json path; `message` is a one-line human message.
 * Emits a GitHub `::warning file=…::` workflow command in CI (attaching to the file in PR
 * review) and the `⚠ …` line in both environments.
 */
function reportFinding(file, message) {
  const rel = relative(repoRoot, file);
  if (IN_CI) {
    // `file` is required for the annotation to attach; line/column are omitted (the lint
    // works on whole-file JSON, not source positions). Percent/newline escaping per the
    // workflow-command spec; `message` is single-line by construction here.
    const escaped = message.replace(/%/g, "%25").replace(/\n/g, "%0A").replace(/\r/g, "%0D");
    process.stdout.write(`::warning file=${rel}::${escaped}\n`);
  }
  console.log(`⚠ ${rel}: ${message}`);
}

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

function percentile(sortedValues, pct) {
  if (sortedValues.length === 0) return 0;
  const idx = Math.min(sortedValues.length - 1, Math.floor((pct / 100) * sortedValues.length));
  return sortedValues[idx];
}

/** Every markdown file that makes up a skill's guidance surface, as repo-relative paths. */
function skillCorpusFiles(skillName) {
  const dir = join(repoRoot, "skills", skillName);
  const files = [];
  files.push(join(dir, "SKILL.md"));
  const refsDir = join(dir, "references");
  try {
    for (const f of readdirSync(refsDir)) {
      if (f.endsWith(".md")) files.push(join(refsDir, f));
    }
  } catch {
    /* no references/ dir is fine */
  }
  return files;
}

function readCorpus(files) {
  const parts = [];
  for (const f of files) {
    try {
      parts.push(readFileSync(f, "utf8"));
    } catch {
      /* a missing SKILL.md is validate-skills.yml's failure to report, not ours */
    }
  }
  return parts.join("\n\n");
}

/**
 * The same files as they were at `ref`.
 *
 * Returns `anyPresent` alongside the text because "" is ambiguous and the two readings call
 * for opposite behaviour: a file that existed and was empty really is a before-state to
 * compare against, whereas a skill that did not exist at base has no before-state at all.
 * Co-movement asks "did this PR's edit move an item's overlap", and for a brand-new skill
 * nothing moved -- every item would trivially measure 0 → n and get reported as a rise that
 * never happened. An item that copies a NEW skill's text is still echoing, but that is the
 * static check's finding to report, in its own words.
 */
function readCorpusAtRef(files, ref) {
  const parts = [];
  let anyPresent = false;
  for (const f of files) {
    try {
      parts.push(
        execFileSync("git", ["show", `${ref}:${relative(repoRoot, f)}`], {
          cwd: repoRoot,
          encoding: "utf8",
          stdio: ["ignore", "pipe", "ignore"],
        }),
      );
      anyPresent = true;
    } catch {
      /* not present at base -- a newly added reference file contributes nothing "before" */
    }
  }
  return { text: parts.join("\n\n"), anyPresent };
}

/**
 * The item's authored text, split by role. `files` is excluded from both: it is provided
 * input data, not authored description, and an asset that legitimately quotes the docs is
 * not an item echoing its skill.
 */
function itemFields(ev) {
  const prompt = [ev.prompt ?? "", ...(ev.workflow ?? []).map((t) => t.prompt ?? "")].join("\n\n");
  const answer = [ev.expected_output ?? "", ...(ev.expectations ?? [])].join("\n\n");
  return { prompt, answer };
}

const evalFiles = globSync(join(here, "*/evals/evals.json")).sort();
const bySkill = evalFiles.map((file) => {
  const doc = readJson(file);
  const skillName = doc.skill_name;
  const corpusFiles = skillCorpusFiles(skillName);
  const corpusText = readCorpus(corpusFiles);
  // An empty corpus silently makes every containment 0 and every item "clean" -- the lint
  // would report a green result precisely when it is measuring nothing. The usual cause is
  // `skill_name` not matching a directory under skills/, which is a config error worth
  // failing on rather than passing quietly.
  if (corpusText.trim() === "") {
    console.error(
      `✗ ${file}: skill_name '${skillName}' has no readable guidance text under ` +
        `skills/${skillName}/ (SKILL.md + references/*.md). Nothing could be compared, so ` +
        `a "no echoing items" result here would be meaningless.`,
    );
    process.exit(1);
  }
  return {
    file,
    skillName,
    doc,
    corpusFiles,
    corpusGrams: ngrams(tokenize(corpusText), N),
  };
});

// Cross-skill null: every item field's containment against every OTHER skill's corpus.
const nullSamples = [];
const perItem = [];

for (const { file, skillName, doc, corpusGrams: ownCorpus } of bySkill) {
  for (const ev of doc.evals ?? []) {
    const fields = itemFields(ev);
    const entry = { skillName, file, id: ev.id, fields: {} };
    for (const [role, text] of Object.entries(fields)) {
      const tokens = tokenize(text);
      if (tokens.length < N) continue; // too short to judge
      const itemGrams = ngrams(tokens, N);
      entry.fields[role] = {
        tokens,
        itemGrams,
        own: containment(itemGrams, ownCorpus),
      };
      for (const other of bySkill) {
        if (other.skillName === skillName) continue;
        nullSamples.push(containment(itemGrams, other.corpusGrams));
      }
    }
    if (Object.keys(entry.fields).length > 0) perItem.push(entry);
  }
}

nullSamples.sort((a, b) => a - b);
const nullPct = percentile(nullSamples, PERCENTILE);

console.log(
  `Cross-skill null: ${nullSamples.length} samples, p${PERCENTILE}=${nullPct.toFixed(3)}; ` +
    `flagging needs containment > ${nullPct.toFixed(3)} AND >= ${MIN_CONTAINMENT} ` +
    `(the null collapses on real data, so the floor is the operative threshold), ` +
    `or a verbatim span >= ${MAX_SPAN} words.`,
);

// A prompt that quotes the guidance is leakage; an expected_output that does is often just
// a correctly-stated answer. Same numbers, different verdict, so they are reported apart.
const ROLE_NOTE = {
  prompt: "LEAKAGE: the question carries its own answer",
  answer: "expected answer restates the guidance (often legitimate — judge in review)",
};

let flagged = 0;
for (const item of perItem) {
  const own = bySkill.find((s) => s.skillName === item.skillName);
  for (const [role, m] of Object.entries(item.fields)) {
    const span = longestSharedSpan(m.tokens, own.corpusGrams);
    const bySpan = span >= MAX_SPAN;
    const byContainment = m.own >= MIN_CONTAINMENT && m.own > nullPct;
    if (!bySpan && !byContainment) continue;
    flagged++;
    const why = bySpan
      ? `verbatim span of ~${span} words shared with its own skill`
      : `${(m.own * 100).toFixed(0)}% containment against ${item.skillName}`;
    reportFinding(item.file, `case ${item.id} [${role}]: ${why} — ${ROLE_NOTE[role]}`);
  }
}

// Co-movement: did THIS PR's guidance edit raise an item's overlap with the guidance?
let coMoved = 0;
if (BASE_REF) {
  for (const { file, skillName, doc, corpusFiles } of bySkill) {
    const base = readCorpusAtRef(corpusFiles, BASE_REF);
    const afterText = readCorpus(corpusFiles);
    if (!base.anyPresent) {
      console.log(
        `Co-movement: skipping ${skillName} — no guidance at base, so this PR adds the ` +
          `skill. Nothing moved; the static check above covers its items.`,
      );
      continue;
    }
    const beforeText = base.text;
    if (beforeText === afterText) continue; // guidance untouched in this PR
    const beforeGrams = ngrams(tokenize(beforeText), N);
    const afterGrams = ngrams(tokenize(afterText), N);
    for (const ev of doc.evals ?? []) {
      for (const [role, text] of Object.entries(itemFields(ev))) {
        const tokens = tokenize(text);
        if (tokens.length < N) continue;
        const grams = ngrams(tokens, N);
        const before = containment(grams, beforeGrams);
        const after = containment(grams, afterGrams);
        const delta = after - before;
        if (delta < CO_MOVEMENT_MIN_DELTA) continue;
        coMoved++;
        reportFinding(
          file,
          `CO-MOVEMENT case ${ev.id} [${role}]: this PR's edit to ${skillName}'s ` +
            `guidance raised containment ${before.toFixed(2)} → ${after.toFixed(2)} ` +
            `(+${delta.toFixed(2)}). Added guidance text that overlaps an eval item is ` +
            `teaching to the test, whatever the absolute number is.`,
        );
      }
    }
  }
} else {
  console.log(
    "Co-movement check skipped (no --base <ref>). It is the check that needs no held-out " +
      "set, so pass the PR base SHA in CI.",
  );
}

if (flagged === 0 && coMoved === 0) {
  console.log("No echoing items found.");
} else {
  console.log(
    `\n${flagged} static finding(s), ${coMoved} co-movement finding(s). Not automatically ` +
      "wrong — some overlap is expected for MongoDB vocabulary — but worth a second look: " +
      "does the item test whether the agent APPLIES the guidance, or just whether it can " +
      "quote it?",
  );
}

process.exit(STRICT && flagged + coMoved > 0 ? 1 : 0);
