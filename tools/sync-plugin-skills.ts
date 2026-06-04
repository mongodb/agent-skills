#!/usr/bin/env node
// Syncs the canonical repo-root skills/ (and assets/) into each plugin under
// plugins/, according to the PLUGINS table below.
//
// The repo-root skills/ directory is the single source of truth (it is what the
// `skills` CLI, the VS Code submodule sync, validate-skills, and the Gemini
// community extension all read). Each plugin needs its own physical copy of the
// skills it ships, because Claude/Cursor/Codex install the plugin from git and
// resolve `skills: "./skills/"` relative to the plugin root.
//
// This script is idempotent: it fully regenerates each plugin's skills/ and
// assets/ directories from the canonical sources. CI runs it and fails if the
// committed copies drift from what this script produces.
//
// Runs directly on Node >= 23.6 (e.g. Node 24): `node tools/sync-plugin-skills.ts`.
// Uses only erasable TypeScript syntax (type annotations), so Node strips the
// types at load time and no transpile step is needed.

import { execSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  rmSync,
  statSync,
} from "node:fs";
import { join } from "node:path";

type SkillSelection = "all" | { include: string[] } | { exclude: string[] };
type PluginsConfig = Record<string, { skills: SkillSelection }>;

// Declares which canonical skills (from the repo-root skills/ directory) each
// plugin under plugins/ ships:
//   "all"               -> every canonical skill
//   { include: [...] }  -> only the listed skills
//   { exclude: [...] }  -> all except the listed skills
const PLUGINS: PluginsConfig = {
  mongodb: { skills: "all" },
  "mongodb-atlas": { skills: { exclude: ["mongodb-mcp-setup"] } },
};

const SKILLS_SRC = "skills";
const ASSETS_SRC = "assets";
const PLUGINS_DIR = "plugins";

// Never copy these into the published plugin copies.
const EXCLUDE_NAMES = new Set([".score_cache", ".DS_Store"]);
const copyFilter = (src: string): boolean => {
  const name = src.slice(src.lastIndexOf("/") + 1);
  return !EXCLUDE_NAMES.has(name);
};

const repoRoot = execSync("git rev-parse --show-toplevel").toString().trim();
process.chdir(repoRoot);

// Canonical skills are directories under skills/ that contain a SKILL.md.
const canonicalSkills: string[] = readdirSync(SKILLS_SRC)
  .filter((name: string): boolean => {
    const p = join(SKILLS_SRC, name);
    return statSync(p).isDirectory() && existsSync(join(p, "SKILL.md"));
  })
  .sort();

function selectSkills(plugin: string, spec: SkillSelection): string[] {
  if (spec === "all") return canonicalSkills;
  if ("include" in spec) return [...spec.include].sort();
  if ("exclude" in spec) {
    const excluded = new Set(spec.exclude);
    return canonicalSkills.filter((s) => !excluded.has(s));
  }
  throw new Error(`[${plugin}] invalid "skills" spec: ${JSON.stringify(spec)}`);
}

let totalErrors = 0;
for (const [plugin, cfg] of Object.entries(PLUGINS)) {
  const pluginDir = join(PLUGINS_DIR, plugin);
  if (!existsSync(pluginDir)) {
    console.error(`[${plugin}] plugin directory not found: ${pluginDir}`);
    totalErrors++;
    continue;
  }

  const selected = selectSkills(plugin, cfg.skills);
  const unknown = selected.filter((s) => !canonicalSkills.includes(s));
  if (unknown.length > 0) {
    console.error(`[${plugin}] unknown skills: ${unknown.join(", ")}`);
    totalErrors++;
    continue;
  }

  // Regenerate skills/.
  const destSkills = join(pluginDir, SKILLS_SRC);
  rmSync(destSkills, { recursive: true, force: true });
  mkdirSync(destSkills, { recursive: true });
  for (const skill of selected) {
    cpSync(join(SKILLS_SRC, skill), join(destSkills, skill), {
      recursive: true,
      filter: copyFilter,
    });
  }

  // Regenerate assets/.
  if (existsSync(ASSETS_SRC)) {
    const destAssets = join(pluginDir, ASSETS_SRC);
    rmSync(destAssets, { recursive: true, force: true });
    mkdirSync(destAssets, { recursive: true });
    cpSync(ASSETS_SRC, destAssets, { recursive: true, filter: copyFilter });
  }

  console.log(`[${plugin}] synced ${selected.length} skills: ${selected.join(", ")}`);
}

if (totalErrors > 0) {
  console.error(`\nSync failed with ${totalErrors} error(s).`);
  process.exit(1);
}
