#!/usr/bin/env node
// Reads/validates/bumps the shared version across every plugin manifest in the
// repo. All plugin manifests are kept in lockstep on one version:
//   - gemini-extension.json (root community Gemini extension)
//   - every plugin.json under plugins/ (each client's manifest, wherever it lives)
//
// Manifests are discovered by finding every plugin.json under plugins/ (plus the
// known root manifests), rather than assuming a `.<client>-plugin/` layout — so a
// future client using a different directory convention is picked up automatically.
//
// This is the single source of truth for the release version logic. The release
// GitHub Actions workflows call it; you can run the exact same thing locally:
//   node tools/plugin-version.ts check                 # validate lockstep, print version
//   node tools/plugin-version.ts bump <patch|minor|major>
//   node tools/plugin-version.ts bump exact 1.2.3
//
// When run in CI it appends the computed values (version / current_version /
// target_version / branch_name / release_tag) to $GITHUB_OUTPUT; locally it just
// prints them. Version edits are a targeted text replacement so each manifest
// keeps its own formatting/indentation. `check` is dependency-free; only `bump`
// loads the `semver` dependency (lazily).
//
// Runs directly on Node >= 23.6 (e.g. Node 24) via type-stripping; erasable
// TypeScript syntax only, no transpile step.

import { execSync } from "node:child_process";
import { appendFileSync, existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

type BumpKind = "major" | "minor" | "patch" | "exact";

// Versioned manifests that live at the repo root and aren't named plugin.json.
const ROOT_MANIFESTS = ["gemini-extension.json"];
// Directories never worth descending into when hunting for plugin.json.
const SKIP_DIRS = new Set(["node_modules", ".git"]);
// Targeted, format-preserving edit of just the version value (not a semver parse).
const VERSION_FIELD_RE = /("version"\s*:\s*")[^"]*(")/;

const repoRoot = execSync("git rev-parse --show-toplevel").toString().trim();
process.chdir(repoRoot);

function findPluginManifests(dir: string): string[] {
  const found: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (SKIP_DIRS.has(entry.name)) {
      continue;
    }

    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      found.push(...findPluginManifests(full));
    } else if (entry.name === "plugin.json") {
      found.push(full);
    }
  }

  return found;
}

// Every versioned manifest: known root manifests + all plugin.json under plugins/.
function discoverManifests(): string[] {
  const manifests: string[] = ROOT_MANIFESTS.filter((m) => existsSync(m));
  if (existsSync("plugins")) {
    manifests.push(...findPluginManifests("plugins"));
  }

  return manifests.sort();
}

function readVersion(file: string): string {
  const parsed = JSON.parse(readFileSync(file, "utf8"));
  if (typeof parsed.version !== "string") {
    throw new Error(`${file}: missing string "version" field`);
  }

  return parsed.version;
}

// Returns the single shared version, or exits 1 listing all versions on mismatch.
function readLockstepVersion(manifests: string[]): string {
  const versions = manifests.map((file) => ({ file, version: readVersion(file) }));
  const reference = versions[0].version;
  if (versions.some((v) => v.version !== reference)) {
    console.error("Plugin version mismatch detected (all manifests must share one version):");
    for (const { file, version } of versions) {
      console.error(`  ${version}  ${file}`);
    }

    process.exit(1);
  }

  return reference;
}

async function computeTarget(current: string, kind: BumpKind, exact?: string): Promise<string> {
  const semver = await import("semver");
  if (kind === "exact") {
    if (!exact) {
      throw new Error('bump exact requires a version, e.g. "bump exact 1.2.3"');
    }

    const valid = semver.valid(exact);
    if (!valid) {
      throw new Error(`invalid exact version: ${exact}`);
    }
    return valid;
  }

  const next = semver.inc(current, kind);
  if (!next) {
    throw new Error(`current version is not valid semver: ${current}`);
  }

  return next;
}

function writeVersion(file: string, version: string): void {
  const text = readFileSync(file, "utf8");
  if (!VERSION_FIELD_RE.test(text)) {
    throw new Error(`${file}: no "version" field to update`);
  }

  writeFileSync(file, text.replace(VERSION_FIELD_RE, `$1${version}$2`));
}

function emit(outputs: Record<string, string>): void {
  const ghOutput = process.env.GITHUB_OUTPUT;
  if (ghOutput) {
    appendFileSync(
      ghOutput,
      Object.entries(outputs)
        .map(([k, v]) => `${k}=${v}\n`)
        .join(""),
    );
  }

  for (const [key, value] of Object.entries(outputs)) {
    console.log(`${key}=${value}`);
  }
}

function usage(): never {
  console.error("usage: plugin-version.ts <check | bump <major|minor|patch|exact> [version]>");
  process.exit(1);
}

try {
  const [command, kindArg, exactArg] = process.argv.slice(2);
  const manifests = discoverManifests();
  if (manifests.length === 0) {
    console.error("No plugin manifests found.");
    process.exit(1);
  }

  if (command === "check") {
    const version = readLockstepVersion(manifests);
    console.error(`All ${manifests.length} manifests at ${version}.`);
    emit({ version, release_tag: `v${version}` });
  } else if (command === "bump") {
    if (!kindArg || !["major", "minor", "patch", "exact"].includes(kindArg)) {
      usage();
    }

    const kind = kindArg as BumpKind;
    const current = readLockstepVersion(manifests);
    const target = await computeTarget(current, kind, exactArg);
    if (target === current) {
      console.error(`Target version (${target}) matches current; nothing to release.`);
      process.exit(1);
    }

    for (const file of manifests) {
      writeVersion(file, target);
    }

    console.error(`Bumped ${manifests.length} manifests: ${current} -> ${target}`);
    emit({
      current_version: current,
      target_version: target,
      branch_name: `release/v${target}`,
      release_tag: `v${target}`,
    });
  } else {
    usage();
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
