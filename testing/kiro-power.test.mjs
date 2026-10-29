// Validates the Kiro plugin at plugins/mongodb/.kiro-plugin/plugin.json:
//   - Agent Plugins manifest shape (required fields per
//     https://agent-plugins.org/schemas/1.0.0/plugin.schema.json)
//   - mcpServers entry with ${VAR} env interpolation (Kiro prompts at install)
//   - skills reference pointing to the synced plugins/mongodb/skills/ directory
// Plus repo-internal invariants: version lockstep with all other plugin
// manifests (tools/plugin-version.ts bumps them together).
//
// Uses node's built-in test runner — no new dependency on testing/ toolchain.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join } from "node:path";

const REPO_ROOT = join(import.meta.dirname, "..");
const PLUGINS_DIR = join(REPO_ROOT, "plugins");
const KIRO_PLUGIN_PATH = join(
  PLUGINS_DIR,
  "mongodb",
  ".kiro-plugin",
  "plugin.json",
);
const KIRO_ATLAS_PLUGIN_PATH = join(
  PLUGINS_DIR,
  "mongodb-atlas",
  ".kiro-plugin",
  "plugin.json",
);

const readJson = (path) => JSON.parse(readFileSync(path, "utf8"));

const plugin = readJson(KIRO_PLUGIN_PATH);
const atlasPlugin = readJson(KIRO_ATLAS_PLUGIN_PATH);

test("kiro-plugin.json: required Agent Plugins manifest fields", () => {
  assert.equal(
    plugin.$schema,
    "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
  );
  assert.match(plugin.name, /^[a-z0-9]+(-[a-z0-9]+)*$/, "kebab-case name");
  assert.match(plugin.version, /^\d+\.\d+\.\d+$/, "semver version");
  assert.ok(plugin.description.length > 0);
  assert.ok(plugin.author?.name, "author.name required");
  assert.ok(Array.isArray(plugin.keywords) && plugin.keywords.length > 0);
  assert.ok(plugin.skills, "skills field required");
  assert.ok(plugin.mcpServers, "mcpServers field required");
});

test("kiro-plugin.json: version in lockstep with all other plugin manifests", () => {
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
    `kiro-plugin.json@${plugin.version} out of sync: found ${[...versions]}`,
  );
});

test("kiro-plugin.json: mongodb server entry matches Kiro documented shape", () => {
  const server = plugin.mcpServers?.mongodb;
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

test("kiro-plugin.json: connection string env var present", () => {
  assert.ok(
    "MDB_MCP_CONNECTION_STRING" in (plugin.mcpServers.mongodb.env ?? {}),
    "power is useless without a connection string",
  );
});

test("kiro-plugin.json: skills directory exists and contains skills", () => {
  const skillsPath = join(PLUGINS_DIR, "mongodb", "skills");
  assert.ok(existsSync(skillsPath), "plugins/mongodb/skills/ must exist");
  const skills = readdirSync(skillsPath).filter((name) => {
    const skillDir = join(skillsPath, name);
    return statSync(skillDir).isDirectory() && existsSync(join(skillDir, "SKILL.md"));
  });
  assert.ok(
    skills.length > 0,
    "skills directory must contain at least one skill with a SKILL.md",
  );
});

test("kiro-atlas-plugin.json: required Agent Plugins manifest fields", () => {
  assert.equal(
    atlasPlugin.$schema,
    "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
  );
  assert.match(atlasPlugin.name, /^[a-z0-9]+(-[a-z0-9]+)*$/, "kebab-case name");
  assert.match(atlasPlugin.version, /^\d+\.\d+\.\d+$/, "semver version");
  assert.ok(atlasPlugin.description.length > 0);
  assert.ok(atlasPlugin.author?.name, "author.name required");
  assert.ok(Array.isArray(atlasPlugin.keywords) && atlasPlugin.keywords.length > 0);
  assert.ok(atlasPlugin.skills, "skills field required");
  assert.ok(atlasPlugin.mcpServers, "mcpServers field required");
});

test("kiro-atlas-plugin.json: mongodb server entry with OAuth config", () => {
  const server = atlasPlugin.mcpServers?.mongodb;
  assert.ok(server, "mcpServers.mongodb missing");
  assert.equal(server.url, "https://mcp.mongodb.com");
  assert.ok(server.oauth, "oauth config missing");
  assert.equal(server.oauth.clientId, "aws-kiro");
});

test("kiro-atlas-plugin.json: skills directory exists and contains skills", () => {
  const skillsPath = join(PLUGINS_DIR, "mongodb-atlas", "skills");
  assert.ok(existsSync(skillsPath), "plugins/mongodb-atlas/skills/ must exist");
  const skills = readdirSync(skillsPath).filter((name) => {
    const skillDir = join(skillsPath, name);
    return statSync(skillDir).isDirectory() && existsSync(join(skillDir, "SKILL.md"));
  });
  assert.ok(
    skills.length > 0,
    "skills directory must contain at least one skill with a SKILL.md",
  );
});
