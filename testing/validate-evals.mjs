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
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { globSync } from "glob";
// draft 2020-12: the schema declares $schema 2020-12, so use Ajv2020 (default Ajv is draft-07).
import Ajv2020 from "ajv/dist/2020.js";

const here = dirname(fileURLToPath(import.meta.url));
const schema = JSON.parse(readFileSync(join(here, "evals.schema.json"), "utf8"));
const ajv = new Ajv2020({ allErrors: true, strict: false });
const validate = ajv.compile(schema);

const files = globSync(join(here, "*/evals/evals.json")).sort();
let failed = false;

for (const file of files) {
  const doc = JSON.parse(readFileSync(file, "utf8"));
  if (validate(doc)) {
    console.log(`✓ ${file} (${doc.evals?.length ?? 0} cases)`);
  } else {
    failed = true;
    console.error(`✗ ${file}`);
    for (const e of validate.errors.slice(0, 10)) {
      console.error(`    ${e.instancePath || "(root)"}: ${e.message}`);
    }
  }
}

if (files.length === 0) {
  console.error("No testing/*/evals/evals.json found.");
  process.exit(1);
}
process.exit(failed ? 1 : 0);
