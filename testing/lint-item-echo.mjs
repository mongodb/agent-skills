#!/usr/bin/env node
/**
 * Flag eval items that echo their own skill's guidance text rather than testing whether
 * an agent can produce it unaided. An item authored by copy-pasting from SKILL.md or a
 * references/*.md file is grading "can the agent quote the instructions back," not
 * "did the agent apply them" — an easy mistake when the skill's author also writes its
 * tests, with no held-out curator to catch it.
 *
 * Three checks, in increasing order of how much they can actually prove:
 *
 * 1. **Static containment** (all items). 8-word-gram containment of the item's authored
 *    text against its own skill's body, flagged at or above an absolute floor
 *    (minAbsoluteContainment). Containment, not Jaccard, because the item is always much
 *    shorter than the skill body, so Jaccard would be swamped by that length asymmetry
 *    regardless of overlap. An earlier version also gated on a cross-skill null
 *    percentile; measured on this corpus the null collapses to 0.000 (two skills
 *    essentially never share an 8-gram), so that leg could never change an outcome and
 *    was removed — the floor is the threshold.
 *
 *    Reported per field, not pooled, because the two fields mean different things. High
 *    overlap in `prompt` is leakage: the question is carrying its own answer. High overlap
 *    in `expected_output`/`expectations` is often unavoidable and fine — if the correct
 *    answer IS the rule, an item that states the rule is correctly authored. Pooling them
 *    would mostly measure the second and call it the first.
 *
 * 2. **Verbatim span.** A shared run of ≥ maxVerbatimSpan tokens is a quotation whatever
 *    the containment score says. Computed as the true longest common token run (the rule
 *    that must never false-positive), over RAW tokens — a quotation includes the ordinary
 *    words, and stripping them would fragment the run and understate the copy.
 *
 * 3. **Co-movement** (`--base <ref>`, the check that needs no held-out set). If a PR edits
 *    a skill's guidance AND that edit raises an item's containment, that is teaching to the
 *    test — detectable from the diff alone, no curator and no golden corpus required. This
 *    is the highest-value check here and it is pure string processing.
 *
 * echo-thresholds.json is the complete shared contract with the Python analysis layer
 * (agent-skills-evals/inspect/analysis/echo.py): the constants AND the tokenizer
 * definition (regex, fenced-code stripping, stopword list). This file is a TRUE PORT —
 * both sides compute the same quantities, so the shared constants mean the same thing.
 * The one deliberate difference is reporting granularity: the lint scores `prompt` and
 * answer fields separately (leakage vs legitimate restatement read differently in
 * review); the Python module pools them.
 *
 * Advisory today (prints, exits 0) unless --strict is passed.
 * TODO: flip validate-eval-cases.yml to --strict once the thresholds have been checked
 * against a few real PRs of item additions, or record why advisory is the permanent
 * answer.
 */
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
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
const MIN_CONTAINMENT = T.minAbsoluteContainment;
const MAX_SPAN = T.maxVerbatimSpan;
const CO_MOVEMENT_MIN_DELTA = T.coMovementMinDelta;

// In GitHub Actions, surface findings as PR annotations (file-attached ::warning) so they
// appear in the Files Changed review view even while the lint is advisory (exit 0). A stdout
// line in a green workflow log is invisible to a reviewer; an annotation is not. The lint
// stays non-blocking — these are ::warning, not ::error — matching the advisory intent (see
// the --strict TODO above). Locally (no GITHUB_ACTIONS), keep the human-readable line so
// `node lint-item-echo.mjs` output is unchanged.
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

// The stopword list is part of the shared contract (echo-thresholds.json), not a local
// choice: two implementations with different tokenizers compute different containment
// values for the SAME shared floor, which is precisely the disagreement the file exists
// to prevent. Domain vocabulary (index, collection, schema, …) is stripped — those are
// the words an item MUST use to describe its task, so leaving them in makes legitimate
// items look like copies.
const STOPWORDS = new Set(T.domainStopwords ?? []);

/**
 * True port of agent-skills-evals/inspect/analysis/echo.py::tokenize — same fenced-code
 * stripping, same regex, same sigil/hyphen normalisation, same stopword list. Fenced code
 * blocks are stripped first: code examples in a skill are not prose to quote, and an item
 * restating a code block is legitimate reuse, not echo. Operator-ish tokens keep their
 * sigil through the split so they can be matched against the stopword list without it,
 * which is why the normalisation is a second pass.
 */
export function tokenize(text, { stripDomain = true } = {}) {
  const noFences = (text ?? "").toLowerCase().replace(/```[\s\S]*?```/g, " ");
  const raw = noFences.match(/[a-z_$][a-z0-9_$-]*/g) ?? [];
  const tokens = raw
    .map((t) => t.replace(/^\$+/, "").replace(/^[-_]+|[-_]+$/g, ""))
    .filter(Boolean);
  return stripDomain ? tokens.filter((t) => !STOPWORDS.has(t)) : tokens;
}

export function ngrams(tokens, n) {
  const grams = new Set();
  for (let i = 0; i + n <= tokens.length; i++) {
    grams.add(tokens.slice(i, i + n).join(" "));
  }
  return grams;
}

// containment = fraction of the ITEM's n-grams that also appear in the corpus
export function containment(itemGrams, corpusGrams) {
  if (itemGrams.size === 0) return 0;
  let hits = 0;
  for (const g of itemGrams) if (corpusGrams.has(g)) hits++;
  return hits / itemGrams.size;
}

/**
 * True longest run of consecutive tokens present in both texts — the verbatim-span rule
 * is the one that must never false-positive, so this is the exact algorithm echo.py's
 * longest_verbatim_span uses (binary search over run length over rolling k-gram sets),
 * NOT a consecutive-n-gram-run approximation, which can stitch a "span" from matches at
 * different corpus locations.
 */
export function longestVerbatimSpan(a, b) {
  if (a.length === 0 || b.length === 0) return 0;
  const sharesRun = (k) => {
    if (k <= 0 || a.length < k || b.length < k) return false;
    const bRuns = new Set();
    for (let i = 0; i + k <= b.length; i++) bRuns.add(b.slice(i, i + k).join(" "));
    for (let i = 0; i + k <= a.length; i++) {
      if (bRuns.has(a.slice(i, i + k).join(" "))) return true;
    }
    return false;
  };
  if (!sharesRun(1)) return 0;
  let lo = 1;
  let hi = Math.min(a.length, b.length);
  while (lo < hi) {
    const mid = Math.floor((lo + hi + 1) / 2);
    if (sharesRun(mid)) lo = mid;
    else hi = mid - 1;
  }
  return lo;
}

/** Every markdown file that makes up a skill's guidance surface, as repo-relative paths. */
function skillCorpusFiles(skillName) {
  const dir = join(repoRoot, "skills", skillName);
  // Sorted recursive glob, matching the Python side's sorted(rglob("*.md")) — file order
  // shifts boundary n-grams, so it is part of the port, not a nicety.
  return [join(dir, "SKILL.md"), ...globSync(join(dir, "references", "**", "*.md")).sort()];
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

function main() {
  const args = process.argv.slice(2);
  const STRICT = args.includes("--strict");
  const baseIdx = args.indexOf("--base");
  const BASE_REF = baseIdx !== -1 ? args[baseIdx + 1] : null;

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
      corpusTokensRaw: tokenize(corpusText, { stripDomain: false }),
    };
  });

  const perItem = [];

  for (const { file, skillName, doc, corpusGrams: ownCorpus } of bySkill) {
    for (const ev of doc.evals ?? []) {
      const fields = itemFields(ev);
      const entry = { skillName, file, id: ev.id, fields: {} };
      for (const [role, text] of Object.entries(fields)) {
        // No minimum-length skip: containment of an item too short to form an n-gram is 0
        // (not a fabricated score), and the verbatim-span rule must still see short items —
        // a copied run long enough to trip maxVerbatimSpan on raw tokens can strip below N.
        const tokens = tokenize(text);
        entry.fields[role] = {
          rawTokens: tokenize(text, { stripDomain: false }),
          own: containment(ngrams(tokens, N), ownCorpus),
        };
      }
      perItem.push(entry);
    }
  }

  console.log(
    `Flagging needs containment >= ${MIN_CONTAINMENT} against the item's own skill, ` +
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
      const span = longestVerbatimSpan(m.rawTokens, own.corpusTokensRaw);
      const bySpan = span >= MAX_SPAN;
      const byContainment = m.own >= MIN_CONTAINMENT;
      if (!bySpan && !byContainment) continue;
      flagged++;
      const why = bySpan
        ? `verbatim span of ${span} words shared with its own skill`
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
          // No minimum-length skip: containment of an item too short to form an n-gram is
          // 0, so its delta is 0 — same outcome, one less special case.
          const grams = ngrams(tokenize(text), N);
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
}

// Run as a CLI only when invoked directly, not when imported by the test.
if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) main();
