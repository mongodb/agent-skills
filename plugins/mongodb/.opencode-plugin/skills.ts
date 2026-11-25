// Loads the skills bundled in this package's skills/ directory and parses each
// SKILL.md's YAML frontmatter. Pure Node only (no @opencode/plugin import) so
// this module is unit-testable with `node --test skills.test.ts` without
// installing any dependencies.
//
// The package root is the plugin root (plugins/<name>), so "this package's
// skills/" is the same generated copy every other harness installs (produced
// from the repo-root skills/ by tools/sync-plugin-skills.ts); never edit it by
// hand.

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

export type BundledSkill = {
  /** OpenCode skill ID — the skill's directory name, the same ID every other harness uses. */
  id: string;
  /** Display name (OpenCode treats frontmatter `name` as a display label only). */
  name: string;
  /** Advertised to the model on every step; skills without one are never advertised. */
  description: string;
  /** Absolute path to SKILL.md — OpenCode reads supporting files from its directory. */
  path: string;
  /** SKILL.md body (everything after the frontmatter), injected when the skill loads. */
  content: string;
};

export function loadBundledSkills(pluginDir: string): BundledSkill[] {
  const skillsDir = join(pluginDir, "skills");
  return readdirSync(skillsDir)
    .filter((entry) => existsSync(join(skillsDir, entry, "SKILL.md")))
    .sort()
    .map((name) => {
      const path = join(skillsDir, name, "SKILL.md");
      const { description, content } = parseFrontmatter(readFileSync(path, "utf8"), name);
      return { id: name, name, description, path, content };
    });
}

export function parseFrontmatter(
  raw: string,
  source: string,
): { description: string; content: string } {
  const match = raw.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/);
  if (!match) {
    throw new Error(`Missing skill frontmatter: ${source}`);
  }

  const description = readDescription(match[1].split(/\r?\n/));
  if (!description) {
    throw new Error(`Missing "description" in frontmatter: ${source}`);
  }

  return { description, content: match[2] };
}

// Reads the top-level `description` scalar. Deliberately not a full YAML parser
// (keeps this module dependency-free), but it must handle every scalar style the
// canonical skills actually use — several use block scalars (`>`, `>-`, `|`):
//   description: plain text            (optionally continued on indented lines)
//   description: "double-quoted"       (JSON-compatible escapes)
//   description: 'single-quoted'       ('' is an escaped quote)
//   description: > / >- / >+           (folded: lines joined with spaces)
//   description: | / |- / |+           (literal: newlines kept)
// The result is trimmed: OpenCode advertises it as one string, so YAML chomping
// indicators don't matter here.
function readDescription(lines: string[]): string | undefined {
  const start = lines.findIndex((line) => /^description:/.test(line));
  if (start === -1) {
    return undefined;
  }

  const head = lines[start].slice("description:".length).trim();
  // Continuation lines: everything indented (or blank) until the next top-level key.
  const continuation: string[] = [];
  for (const line of lines.slice(start + 1)) {
    if (line.trim() !== "" && !/^\s/.test(line)) {
      break;
    }

    continuation.push(line.trim());
  }

  while (continuation.length > 0 && continuation[continuation.length - 1] === "") {
    continuation.pop();
  }

  const block = head.match(/^([|>])[-+]?$/);
  if (block) {
    if (block[1] === "|") {
      return continuation.join("\n").trim();
    }

    // Folded: single newlines become spaces; blank lines become newlines.
    return continuation
      .join("\n")
      .replace(/([^\n])\n(?!\n)/g, "$1 ")
      .replace(/\n\n/g, "\n")
      .trim();
  }

  const joined = [head, ...continuation].filter((l) => l !== "").join(" ");
  if (joined.startsWith('"')) {
    return JSON.parse(joined);
  }

  if (joined.startsWith("'")) {
    return joined.slice(1, -1).replace(/''/g, "'");
  }

  return joined.trim();
}
