#!/usr/bin/env node
// Validates every plugin under plugins/ that ships a .gemini-plugin/plugin.json
// against the package-level rules of the Gemini Partner Plugin guide:
//   - manifest metadata, kebab-case `name`, semver `version`, `./` paths
//   - README.md, CHANGELOG.md, and LICENSE at the plugin root
//   - only plugin.json inside .gemini-plugin/
//   - `mcpServers` is inline in the manifest, each server an https:// URL on
//     the author.url domain (no stdio)
//   - no .mcp.json or mcp.json at the plugin root: Copilot, Grok, and Codex
//     load those files automatically, ahead of their own manifest config
//   - SKILL.md frontmatter: name <= 64 chars with the brand prefix, matching
//     its directory; description <= 1,024 chars
//   - no symlinks and no `../` paths in plugin Markdown or JSON
//
// Usage: node tools/validate-gemini-plugin.ts
// Runs directly on Node >= 23.6 via type-stripping; erasable TypeScript only.

import { execSync } from "node:child_process";
import { existsSync, lstatSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";

const PLUGINS_DIR = "plugins";
const GEMINI_DIR = ".gemini-plugin";
const BRAND_PREFIX = "mongodb-";
const REQUIRED_FILES = ["README.md", "CHANGELOG.md", "LICENSE"];
const REQUIRED_FIELDS = [
  "displayName",
  "description",
  "repository",
  "homepage",
  "license",
];
const SHARED_MCP_FILES = [".mcp.json", "mcp.json"];
const KEBAB_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const SEMVER_RE = /^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/;
const PARENT_PATH_RE = /(^|[\s("'`])\.\.\//;
const MAX_SKILL_NAME = 64;
const MAX_DESCRIPTION = 1024;

const repoRoot = execSync("git rev-parse --show-toplevel").toString().trim();
process.chdir(repoRoot);

const errors: string[] = [];
const fail = (where: string, message: string): void => {
  errors.push(`${where}: ${message}`);
};

function walk(dir: string): string[] {
  const files: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    files.push(full);
    if (entry.isDirectory() && !entry.isSymbolicLink()) {
      files.push(...walk(full));
    }
  }
  return files;
}

// Reads a top-level scalar from YAML frontmatter, including `|` and `>` blocks.
function frontmatterValue(text: string, key: string): string | undefined {
  const match = text.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!match) return undefined;
  const lines = match[1].split(/\r?\n/);
  const start = lines.findIndex((line) => line.startsWith(`${key}:`));
  if (start === -1) return undefined;
  const inline = lines[start].slice(key.length + 1).trim();
  const block = inline.match(/^([|>])[-+]?$/);
  if (!block) return inline.replace(/^(["'])([\s\S]*)\1$/, "$2");
  const body: string[] = [];
  for (const line of lines.slice(start + 1)) {
    if (line.trim() !== "" && !/^\s/.test(line)) break;
    body.push(line.trim());
  }
  return body.join(block[1] === "|" ? "\n" : " ").trim();
}

function hostOf(url: string): string | undefined {
  try {
    return new URL(url).hostname;
  } catch {
    return undefined;
  }
}

function checkMcpServers(
  where: string,
  servers: unknown,
  authorHost: string,
): void {
  if (
    typeof servers !== "object" ||
    servers === null ||
    Array.isArray(servers)
  ) {
    fail(where, "mcpServers must be an inline object of servers");
    return;
  }
  if (Object.keys(servers).length === 0)
    fail(where, "no servers in mcpServers");
  const domain = authorHost.replace(/^www\./, "");
  for (const [name, server] of Object.entries(
    servers as Record<string, Record<string, unknown>>,
  )) {
    const url = typeof server.url === "string" ? server.url : "";
    const host = hostOf(url);
    if ("command" in server)
      fail(where, `server "${name}" is a local stdio server`);
    if (!url.startsWith("https://") || !host)
      fail(where, `server "${name}" needs an https:// url`);
    else if (host !== domain && !host.endsWith(`.${domain}`)) {
      fail(where, `server "${name}" host ${host} is not on ${domain}`);
    }
  }
}

function checkSkill(where: string, skillFile: string): void {
  const text = readFileSync(skillFile, "utf8");
  const name = frontmatterValue(text, "name");
  const description = frontmatterValue(text, "description");
  const dirName = dirname(skillFile).split("/").pop();
  if (!name) fail(where, "missing frontmatter name");
  else {
    if (!KEBAB_RE.test(name) || name.length > MAX_SKILL_NAME)
      fail(where, `invalid name "${name}"`);
    if (!name.startsWith(BRAND_PREFIX))
      fail(where, `name "${name}" lacks prefix ${BRAND_PREFIX}`);
    if (name !== dirName)
      fail(where, `name "${name}" does not match directory "${dirName}"`);
  }
  if (!description) fail(where, "missing frontmatter description");
  else if (description.length > MAX_DESCRIPTION) {
    fail(
      where,
      `description is ${description.length} chars (max ${MAX_DESCRIPTION})`,
    );
  }
}

function checkPlugin(pluginDir: string): void {
  const manifestPath = join(pluginDir, GEMINI_DIR, "plugin.json");
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));

  if (!KEBAB_RE.test(manifest.name ?? ""))
    fail(manifestPath, "name must be kebab-case");
  if (!SEMVER_RE.test(manifest.version ?? ""))
    fail(manifestPath, "version must be semver");
  for (const field of REQUIRED_FIELDS) {
    if (!manifest[field]) fail(manifestPath, `missing "${field}"`);
  }
  for (const field of ["name", "email", "url"]) {
    if (!manifest.author?.[field])
      fail(manifestPath, `missing "author.${field}"`);
  }
  const authorHost = hostOf(manifest.author?.url ?? "") ?? "";

  for (const extra of readdirSync(join(pluginDir, GEMINI_DIR))) {
    if (extra !== "plugin.json")
      fail(join(pluginDir, GEMINI_DIR), `unexpected entry "${extra}"`);
  }
  for (const file of REQUIRED_FILES) {
    if (!existsSync(join(pluginDir, file))) fail(pluginDir, `missing ${file}`);
  }

  const skills: unknown = manifest.skills;
  if (!Array.isArray(skills) || skills.length === 0)
    fail(manifestPath, "skills must be a non-empty array");
  for (const skill of Array.isArray(skills) ? skills : []) {
    if (
      typeof skill !== "string" ||
      !skill.startsWith("./") ||
      !skill.endsWith("/SKILL.md")
    ) {
      fail(manifestPath, `invalid skill path ${JSON.stringify(skill)}`);
    } else if (!existsSync(join(pluginDir, skill)))
      fail(manifestPath, `skill not found: ${skill}`);
    else checkSkill(join(pluginDir, skill), join(pluginDir, skill));
  }

  checkMcpServers(manifestPath, manifest.mcpServers, authorHost);
  for (const file of SHARED_MCP_FILES) {
    if (existsSync(join(pluginDir, file))) {
      fail(
        join(pluginDir, file),
        "other clients load this file; define servers in each manifest instead",
      );
    }
  }

  for (const file of walk(pluginDir)) {
    if (lstatSync(file).isSymbolicLink())
      fail(file, "symlinks are not allowed");
    else if (
      /\.(md|json)$/.test(file) &&
      PARENT_PATH_RE.test(readFileSync(file, "utf8"))
    ) {
      fail(file, "contains a ../ path");
    }
  }
}

const plugins = readdirSync(PLUGINS_DIR).filter((name) =>
  existsSync(join(PLUGINS_DIR, name, GEMINI_DIR, "plugin.json")),
);
for (const plugin of plugins) checkPlugin(join(PLUGINS_DIR, plugin));

if (errors.length > 0) {
  console.error(errors.map((e) => `- ${e}`).join("\n"));
  console.error(
    `\nGemini plugin validation failed with ${errors.length} error(s).`,
  );
  process.exit(1);
}
console.log(
  `Gemini plugin validation passed: ${plugins.join(", ") || "(none)"}`,
);
