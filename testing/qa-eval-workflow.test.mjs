import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const workflow = readFileSync(
  new URL("../.github/workflows/qa-eval.yml", import.meta.url),
  "utf8",
);

test("QA eval isolates and gates the exact Inspect log", () => {
  assert.match(workflow, /LOG_DIR="\$RUNNER_TEMP\/inspect-logs\/\$SKILL"/);
  assert.match(workflow, /--log-dir "\$LOG_DIR"/);
  assert.match(
    workflow,
    /uv run python \.\.\/scripts\/ci_gate\.py "\$LOG_FILE" --mode strict/,
  );
  assert.doesNotMatch(workflow, /ci_gate\.py logs/);
});

test("QA eval exports and validates per-sample diagnostics", () => {
  assert.match(workflow, /uv run python public_report\.py/);
  assert.match(workflow, /\(\.samples \| type == "array"\)/);
  assert.match(workflow, /\(\.validTotal \| type == "number"\)/);
  assert.match(workflow, /mv "\$REPORT_TMP" "\$REPORT"/);
  assert.match(
    workflow,
    /path: \$\{\{ runner\.temp \}\}\/reports\/qa-eval-report-\*\.json/,
  );
});

test("jq arguments use separate name and value tokens", () => {
  assert.doesNotMatch(workflow, /--arg [A-Za-z0-9_]+=/);
});
