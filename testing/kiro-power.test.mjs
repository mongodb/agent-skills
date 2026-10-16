// Validates the kiro/ power against Kiro's two supported formats:
//   - plugin.json: Agent Plugins manifest (required fields per
//     https://agent-plugins.org/schemas/1.0.0/plugin.schema.json)
//   - POWER.md: legacy format frontmatter (name/displayName/description/
//     keywords/mcpServers, matching firebase/agent-skills kiro power)
//   - mcp.json: server entry shape Kiro documents ($schema/type/args/env
//     ${VAR} interpolation)
// Plus repo-internal invariants: version lockstep with the other plugin
// manifests (tools/plugin-version.ts bumps them together), and POWER.md
// frontmatter agreeing with plugin.json/mcp.json so neither format drifts.
//
// Uses node's built-in test runner — no new dependency on testing/ toolchain.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const REPO_ROOT = join(import.meta.dirname, "..");
const KIRO_DIR = join(REPO_ROOT, "kiro");

const readJson = (path) => JSON.parse(readFileSync(path, "utf8"));

const plugin = readJson(join(KIRO_DIR, "plugin.json"));
const mcp = readJson(join(KIRO_DIR, "mcp.json"));
const powerMd = readFileSync(join(KIRO_DIR, "POWER.md"), "utf8");

// Minimal frontmatter parser: kiro frontmatter is flat scalars plus a
// keywords list and an mcpServers list — no nested YAML, so no yaml dep.
function parseFrontmatter(md) {
  const match = md.match(/^---\n([\s\S]*?)\n---\n/);
  assert.ok(match, "POWER.md must start with a YAML frontmatter block");
  const fields = {};
  let currentKey = null;
  for (const line of match[1].split("\n")) {
    const listItem = line.match(/^\s+-\s+"?([^"]+)"?$/);
    if (listItem && currentKey) {
      fields[currentKey].push(listItem[1]);
      continue;
    }
    const kv = line.match(/^(\w+):\s*(.*)$/);
    if (!kv) continue;
    const [, key, raw] = kv;
    if (raw === "") {
      currentKey = key;
      fields[key] = [];
    } else if (raw.startsWith("[")) {
      currentKey = null;
      fields[key] = JSON.parse(raw.replace(/'/g, '"'));
    } else {
      currentKey = null;
      fields[key] = raw.replace(/^"|"$/g, "");
    }
  }
  return fields;
}

const frontmatter = parseFrontmatter(powerMd);

test("plugin.json: required Agent Plugins manifest fields", () => {
  assert.equal(
    plugin.$schema,
    "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
  );
  assert.match(plugin.name, /^[a-z0-9]+(-[a-z0-9]+)*$/, "kebab-case name");
  assert.match(plugin.version, /^\d+\.\d+\.\d+$/, "semver version");
  assert.ok(plugin.description.length > 0);
  assert.ok(plugin.author?.name, "author.name required");
  assert.ok(Array.isArray(plugin.keywords) && plugin.keywords.length > 0);
});

test("plugin.json: version in lockstep with all other plugin manifests", () => {
  const versions = new Set([plugin.version]);
  const walk = (dir) => {
    for (const entry of readdirSync(dir)) {
      const full = join(dir, entry);
      if (statSync(full).isDirectory()) walk(full);
      else if (entry === "plugin.json") versions.add(readJson(full).version);
    }
  };
  walk(join(REPO_ROOT, "plugins"));
  versions.add(readJson(join(REPO_ROOT, "gemini-extension.json")).version);
  assert.deepEqual(
    [...versions],
    [plugin.version],
    `kiro/plugin.json@${plugin.version} out of sync: found ${[...versions]}`,
  );
});

test("mcp.json: mongodb server entry matches Kiro documented shape", () => {
  const server = mcp.mcpServers?.mongodb;
  assert.ok(server, "mcpServers.mongodb missing");
  assert.equal(server.command, "npx");
  assert.ok(
    server.args.some((a) => a.startsWith("mongodb-mcp-server@")),
    "args must pin the mongodb-mcp-server package",
  );
  for (const [key, value] of Object.entries(server.env ?? {})) {
    assert.equal(
      value,
      `\${${key}}`,
      `env.${key} must use \${${key}} interpolation so Kiro prompts for it`,
    );
  }
});

test("mcp.json: connection string env var present", () => {
  assert.ok(
    "MDB_MCP_CONNECTION_STRING" in (mcp.mcpServers.mongodb.env ?? {}),
    "power is useless without a connection string",
  );
});

test("POWER.md: frontmatter required by the legacy Kiro format", () => {
  for (const field of ["name", "displayName", "description"]) {
    assert.ok(frontmatter[field], `frontmatter.${field} missing`);
  }
  assert.ok(frontmatter.keywords.length > 0, "keywords drive activation");
  assert.deepEqual(frontmatter.mcpServers, ["mongodb"]);
});

test("POWER.md and plugin.json do not drift", () => {
  assert.equal(frontmatter.name, plugin.name);
  assert.equal(frontmatter.description, plugin.description);
  assert.deepEqual([...frontmatter.keywords].sort(), [...plugin.keywords].sort());
});

test("POWER.md: env vars in mcp.json are documented for onboarding", () => {
  for (const key of Object.keys(mcp.mcpServers.mongodb.env ?? {})) {
    assert.ok(
      powerMd.includes(`\`${key}\``),
      `${key} is required by mcp.json but never documented in POWER.md`,
    );
  }
});

test("POWER.md: skills table only references skills that exist in the repo", () => {
  const skillsDir = join(REPO_ROOT, "skills");
  const referenced = [...powerMd.matchAll(/`#(mongodb[a-z0-9-]*)`/g)].map(
    (m) => m[1],
  );
  assert.ok(referenced.length > 0, "no #skill invocations found");
  for (const name of referenced) {
    assert.ok(
      statSync(join(skillsDir, name), { throwIfNoEntry: false })?.isDirectory(),
      `POWER.md references #${name} but skills/${name} does not exist`,
    );
  }
});
