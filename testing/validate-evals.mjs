#!/usr/bin/env node
/**
 * Validate every testing/<skill>/evals/evals.json against testing/evals.schema.json.
 *
 * Reports EVERY violation across all files, then exits 1 — deliberately not first-failure,
 * so an author fixes the whole set in one pass instead of rediscovering the next problem on
 * each CI run. Each violation prints the file path plus the JSON path within it (ajv's
 * instancePath), so a malformed eval case fails where it was authored.
 *
 * Run: `npm ci --prefix testing && node testing/validate-evals.mjs` — `ci`, not `install`,
 * to match .github/workflows/validate-eval-cases.yml exactly; a local run that resolves
 * different dependency versions than CI is a local run that can disagree with it.
 * CWD-independent: paths resolve relative to this file, so it works from the repo root or
 * from testing/.
 */
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { globSync } from "glob";
// draft 2020-12: the schema declares $schema 2020-12, so use Ajv2020 (default Ajv is draft-07).
import Ajv2020 from "ajv/dist/2020.js";

const here = dirname(fileURLToPath(import.meta.url));

/**
 * Parse JSON with the filename in the message. The whole point of this script is that a
 * broken case file produces a one-line error pointing at the problem in this PR; letting
 * JSON.parse throw bare gives a stack trace with no filename -- exactly the failure mode
 * it exists to prevent.
 */
function readJson(file) {
  const text = readFileSync(file, "utf8");
  try {
    return JSON.parse(text);
  } catch (err) {
    console.error(`\u2717 ${file}\n    not valid JSON: ${err.message}`);
    process.exit(1);
  }
}

// The seed/fixture naming contract comes from the schema (x-fixtureContract) rather than
// being hardcoded here, because agent-skills-evals/solvers/seed_db.py resolves fixtures
// against the same convention at run time. Two independent hardcoded copies is how a case
// starts passing this check and then failing to seed inside the harness.
function contractFrom(schema) {
  const contract = schema["x-fixtureContract"] ?? {};
  return {
    FIXTURE_DIR: contract.fixtureDir ?? "fixtures",
    FIXTURE_EXT: contract.fixtureExtension ?? ".js",
    RESERVED_SEEDS: new Set(contract.reservedSeeds ?? ["clean_slate"]),
  };
}

/**
 * Does a `files` entry escape the case's own evals dir? Pure (no fs), so the eval-integrity
 * rule the schema regex alone cannot express is unit-testable.
 *
 * The schema pattern rejects a leading '/' and any '..' segment, but a pattern cannot reason
 * about what a path RESOLVES to. This is the authoritative containment check. It is what
 * blocks cross-skill answer-key handover — a case pointing at ../mongodb-other-skill/evals/
 * or ../../skills/<name>/SKILL.md would hand the agent its own answer key, pass the schema
 * regex (no leading '/', and '..' is a segment the pattern already forbids — but a regex
 * forbidding '..' and a resolve() that catches '..' are two different defenses, and only the
 * latter reasons about the resolved target), and be invisible to lint-item-echo.mjs (which
 * excludes `files` from overlap analysis because they are provided input data).
 *
 * resolve() rather than join() because join() disagrees with the harness on absolute paths:
 * join('/a', '/etc/x') nests to '/a/etc/x', while Python's Path('/a') / '/etc/x' honours the
 * absolute and yields '/etc/x'. resolve() matches the harness, so the two agree on what is
 * being checked.
 */
export function filesEntryEscapes(evalsDir, ref) {
  const resolved = resolve(evalsDir, ref);
  const rel = relative(evalsDir, resolved);
  return isAbsolute(ref) || rel === "" || rel.startsWith("..") || isAbsolute(rel);
}

// A case's `files` entries and `seed` name point at real paths, but nothing in the schema
// itself can check a path exists. Missing here means agent-skills-evals's case_source.py
// (build_prompt) or seed_db.py would only discover it deep inside a harness run, as a
// FileNotFoundError instead of a one-line message pointing at the bad path in this PR.
//
// Exported (and takes the fixture contract as a param) so the containment rule is pinned by
// validate-evals.test.mjs — without that, the cross-skill-escape guard is code that only runs
// in CI and has no test that fails when it regresses.
export function checkAssetsExist(evalsDir, doc, contract) {
  const { FIXTURE_DIR, FIXTURE_EXT, RESERVED_SEEDS } = contract;
  const problems = [];
  for (const ev of doc.evals ?? []) {
    for (const ref of ev.files ?? []) {
      // Containment BEFORE existence. A path that escapes is rejected whether or not the
      // target happens to exist — the answer-key file under skills/<name>/ DOES exist.
      const resolved = resolve(evalsDir, ref);
      if (filesEntryEscapes(evalsDir, ref)) {
        problems.push(
          `case ${ev.id}: files entry escapes the evals dir: ${ref} -> ${resolved}. ` +
            `Assets must live under ${evalsDir}.`,
        );
      } else if (!existsSync(resolved)) {
        problems.push(`case ${ev.id}: files entry not found: ${resolved}`);
      } else {
        // And again after following symlinks. A symlink inside evals/ needs no '..' and no
        // leading '/', so it satisfies both the schema pattern and the resolve() check above
        // while still pointing anywhere -- verified: a `leak.md -> ../../../skills/<name>/
        // SKILL.md` symlink passed cleanly before this branch existed.
        const realEvalsDir = realpathSync(evalsDir);
        const realRel = relative(realEvalsDir, realpathSync(resolved));
        if (realRel.startsWith("..") || isAbsolute(realRel)) {
          problems.push(
            `case ${ev.id}: files entry resolves outside the evals dir via a symlink: ` +
              `${ref} -> ${realpathSync(resolved)}`,
          );
        }
      }
    }
    if (ev.seed && !RESERVED_SEEDS.has(ev.seed)) {
      const fixture = join(evalsDir, FIXTURE_DIR, `${ev.seed}${FIXTURE_EXT}`);
      if (!existsSync(fixture)) {
        problems.push(`case ${ev.id}: seed '${ev.seed}' has no fixture at ${fixture}`);
      }
    }
  }
  return problems;
}

function main() {
  const schema = readJson(join(here, "evals.schema.json"));
  const ajv = new Ajv2020({ allErrors: true, strict: false });
  const validate = ajv.compile(schema);
  const contract = contractFrom(schema);

  const files = globSync(join(here, "*/evals/evals.json")).sort();
  let failed = false;

  for (const file of files) {
    const doc = readJson(file);
    const schemaOk = validate(doc);
    const assetProblems = checkAssetsExist(dirname(file), doc, contract);

    if (schemaOk && assetProblems.length === 0) {
      console.log(`✓ ${file} (${doc.evals?.length ?? 0} cases)`);
    } else {
      failed = true;
      console.error(`✗ ${file}`);
      for (const e of (validate.errors ?? []).slice(0, 10)) {
        console.error(`    ${e.instancePath || "(root)"}: ${e.message}`);
      }
      for (const p of assetProblems) {
        console.error(`    ${p}`);
      }
    }
  }

  if (files.length === 0) {
    console.error("No testing/*/evals/evals.json found.");
    process.exit(1);
  }
  process.exit(failed ? 1 : 0);
}

// Run as a CLI only when invoked directly, not when imported by the test.
if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) main();
