#!/usr/bin/env node
/**
 * Validate every testing/<skill>/evals/evals.json against testing/evals.schema.json.
 * Fails (exit 1) on the first schema violation, printing the skill + JSON path — so a
 * malformed eval case fails in CI where the builder authors it.
 *
 * Wire into .github/workflows/validate-skills.yml, e.g.:
 *   - run: npm --prefix testing ci        # (or: npx ...) install ajv + glob
 *   - run: node testing/validate-evals.mjs
 *
 * Deps: ajv, ajv-formats, glob  (dev-only; add to testing/package.json).
 */
import { readFileSync } from "node:fs";
import { globSync } from "glob";
import Ajv from "ajv";

const schema = JSON.parse(readFileSync(new URL("./evals.schema.json", import.meta.url)));
const ajv = new Ajv({ allErrors: true, strict: false });
const validate = ajv.compile(schema);

const files = globSync("testing/*/evals/evals.json");
let failed = false;

for (const file of files.sort()) {
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
  console.error("No testing/*/evals/evals.json found — check the working directory.");
  process.exit(1);
}
process.exit(failed ? 1 : 0);
