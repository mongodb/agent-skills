#!/usr/bin/env node
/**
 * Validate every testing/<skill>/evals/evals.json against testing/evals.schema.json.
 * Fails (exit 1) on the first schema violation, printing the skill + JSON path — so a
 * malformed eval case fails in CI where the builder authors it.
 *
 * Run: `npm --prefix testing install && node testing/validate-evals.mjs` (see
 * .github/workflows/validate-eval-cases.yml). CWD-independent: paths resolve relative to
 * this file, so it works whether invoked from the repo root or testing/.
 */
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { globSync } from "glob";
// draft 2020-12: the schema declares $schema 2020-12, so use Ajv2020 (default Ajv is draft-07).
import Ajv2020 from "ajv/dist/2020.js";

const here = dirname(fileURLToPath(import.meta.url));
const schema = JSON.parse(readFileSync(join(here, "evals.schema.json"), "utf8"));
const ajv = new Ajv2020({ allErrors: true, strict: false });
const validate = ajv.compile(schema);

// A case's `files` entries and `seed` name point at real paths, but nothing in the schema
// itself can check a path exists. Missing here means agent-skills-evals's case_source.py
// (build_prompt) or seed_db.py would only discover it deep inside a harness run, as a
// FileNotFoundError instead of a one-line message pointing at the bad path in this PR.
function checkAssetsExist(evalsDir, doc) {
  const problems = [];
  for (const ev of doc.evals ?? []) {
    for (const ref of ev.files ?? []) {
      if (!existsSync(join(evalsDir, ref))) {
        problems.push(`case ${ev.id}: files entry not found: ${join(evalsDir, ref)}`);
      }
    }
    if (ev.seed && ev.seed !== "clean_slate") {
      const fixture = join(evalsDir, "fixtures", `${ev.seed}.js`);
      if (!existsSync(fixture)) {
        problems.push(`case ${ev.id}: seed '${ev.seed}' has no fixture at ${fixture}`);
      }
    }
  }
  return problems;
}

const files = globSync(join(here, "*/evals/evals.json")).sort();
let failed = false;

for (const file of files) {
  const doc = JSON.parse(readFileSync(file, "utf8"));
  const schemaOk = validate(doc);
  const assetProblems = checkAssetsExist(dirname(file), doc);

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
