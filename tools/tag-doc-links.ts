#!/usr/bin/env node
// Adds `utm_source=agent-skills` to mongodb.com links in the canonical skills/
// directory so docs traffic from skills can be attributed.
//
// Skipped on purpose:
//   - llms.txt URLs: the docs server returns 404 when they carry a query string.
//   - Link labels like `[https://...](https://...)`: only the target is tagged.
//   - Other hosts (cloud.mongodb.com, dochub.mongodb.org, third parties).
//
// Usage:
//   node tools/tag-doc-links.ts          rewrite files in place
//   node tools/tag-doc-links.ts --check  exit 1 if any link is untagged
//
// Run `node tools/sync-plugin-skills.ts` afterwards to update plugin copies.

import { readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const PARAM = "utm_source=agent-skills";
const ROOT = new URL("../skills/", import.meta.url).pathname;
const URL_RE = /(?<!\[)https?:\/\/(?:www\.)?mongodb\.com\/[^\s)\]>"'`]*/g;

function tag(url: string): string {
  // Leave trailing sentence punctuation outside the URL.
  const trail = url.match(/[.,;:]+$/)?.[0] ?? "";
  let core = trail ? url.slice(0, -trail.length) : url;
  if (core.includes("utm_source=") || /llms\.txt(?:[?#]|$)/.test(core)) {
    return url;
  }
  const hashAt = core.indexOf("#");
  const hash = hashAt === -1 ? "" : core.slice(hashAt);
  core = hashAt === -1 ? core : core.slice(0, hashAt);
  return `${core}${core.includes("?") ? "&" : "?"}${PARAM}${hash}${trail}`;
}

function* markdownFiles(dir: string): Generator<string> {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) yield* markdownFiles(path);
    else if (name.endsWith(".md")) yield path;
  }
}

const check = process.argv.includes("--check");
let untagged = 0;

for (const file of markdownFiles(ROOT)) {
  const before = readFileSync(file, "utf8");
  const after = before.replace(URL_RE, (url) => {
    const tagged = tag(url);
    if (tagged !== url) {
      untagged++;
      if (check) console.log(`${file.slice(ROOT.length)}: ${url}`);
    }
    return tagged;
  });
  if (!check && after !== before) writeFileSync(file, after);
}

if (check && untagged > 0) {
  console.error(`\n${untagged} mongodb.com link(s) missing ${PARAM}.`);
  process.exit(1);
}
console.log(check ? "All mongodb.com links tagged." : `Tagged ${untagged} link(s).`);
