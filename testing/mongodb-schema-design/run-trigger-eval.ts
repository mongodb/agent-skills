#!/usr/bin/env npx tsx

/**
 * Trigger eval runner for mongodb-schema-design skill.
 *
 * Uses the Claude CLI (`claude`) to send each prompt from trigger-eval.json
 * with all skill descriptions in the system prompt, then checks whether
 * Claude selected the mongodb-schema-design skill via structured JSON output.
 *
 * Usage:
 *   npx tsx run-trigger-eval.ts
 *   MODEL=sonnet npx tsx run-trigger-eval.ts
 *
 * Environment variables:
 *   MODEL    - Optional. Claude model to use (default: sonnet).
 *   DELAY_MS - Optional. Delay between CLI calls in ms (default: 500).
 */

import { readFileSync, readdirSync, existsSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SKILLS_DIR = join(__dirname, '../../skills');
const EVALS_FILE = join(__dirname, 'trigger-eval.json');
const TARGET_SKILL = 'mongodb-schema-design';

const MODEL = process.env.MODEL ?? 'sonnet';
const DELAY_MS = Number(process.env.DELAY_MS ?? 500);

interface Skill {
  name: string;
  description: string;
}

interface EvalCase {
  prompt: string;
  should_trigger: boolean;
}

interface EvalResult {
  index: number;
  prompt: string;
  expected: boolean;
  actual: boolean;
  triggered_skills: string[];
  pass: boolean;
  error?: string;
}

function parseSkillMeta(content: string): Skill {
  const fmMatch = content.match(/^---\n([\s\S]*?)\n---/);
  if (!fmMatch) {
    throw new Error('Missing frontmatter in SKILL.md');
  }

  const lines = fmMatch[1].split('\n');
  let name: string | null = null;
  let description = '';
  let collectingDesc = false;

  for (const line of lines) {
    const isIndented = line.startsWith('  ') || line.startsWith('\t');

    if (!isIndented && line.includes(':')) {
      if (collectingDesc) collectingDesc = false;

      const colonIdx = line.indexOf(':');
      const key = line.slice(0, colonIdx).trim();
      const value = line.slice(colonIdx + 1).trim();

      if (key === 'name') {
        name = value.replace(/^["']|["']$/g, '');
      } else if (key === 'description') {
        if (['>', '>-', '|', '|-'].includes(value)) {
          collectingDesc = true;
          description = '';
        } else {
          description = value.replace(/^["']|["']$/g, '');
        }
      }
    } else if (collectingDesc && isIndented) {
      description += (description ? " " : '') + line.trim();
    }
  }

  if (!name) {
    throw new Error('Missing frontmatter in SKILL.md');
  }

  return { name, description };
}

function loadSkills(): Skill[] {
  const skills: Skill[] = [];
  const dirs = readdirSync(SKILLS_DIR, { withFileTypes: true }).filter((d) =>
    d.isDirectory()
  );

  for (const dir of dirs) {
    const skillFile = join(SKILLS_DIR, dir.name, 'SKILL.md');
    if (!existsSync(skillFile)) continue;

    const content = readFileSync(skillFile, 'utf-8');
    skills.push(parseSkillMeta(content));
  }

  return skills;
}

function buildSystemPrompt(skills: Skill[]): string {
  const skillList = skills
    .map((s) => `- **${s.name}**: ${s.description}`)
    .join('\n');

  return `You are an expert assistant with access to specialized skills.
Given a user's question, determine which skills (if any) are relevant.

Available skills:
${skillList}

IMPORTANT: You must select skills based ONLY on the skill descriptions above.
Select zero, one, or multiple skills. Only select a skill if the user's question
clearly falls within that skill's described scope.`;
}

function buildJsonSchema(skills: Skill[]): object {
  return {
    type: 'object',
    properties: {
      selected_skills: {
        type: 'array',
        items: {
          type: 'string',
          enum: [...skills.map((s) => s.name), 'none'],
        },
        description:
          "List of skill names that are relevant to the user's question. Use an empty array if no skill applies.",
      },
    },
    required: ['selected_skills'],
    additionalProperties: false,
  };
}

interface CLIOutput {
  is_error: boolean;
  result: string;
  structured_output?: { selected_skills?: string[] };
  total_cost_usd: number;
  duration_ms: number;
}

let totalCostUsd = 0;

function callClaude(
  prompt: string,
  systemPrompt: string,
  jsonSchema: object
): string[] {
  const schemaStr = JSON.stringify(jsonSchema);

  const args = [
    '--print',
    '--model', MODEL,
    '--output-format', 'json',
    '--system-prompt', systemPrompt,
    '--json-schema', schemaStr,
    '--tools', '',
    '--no-session-persistence',
    prompt,
  ];

  const output = execFileSync('claude', args, {
    encoding: 'utf-8',
    timeout: 60_000,
    maxBuffer: 1024 * 1024,
  });

  const parsed: CLIOutput = JSON.parse(output);

  if (parsed.is_error) {
    throw new Error(`CLI error: ${parsed.result}`);
  }

  totalCostUsd += parsed.total_cost_usd ?? 0;

  // The CLI returns structured output directly when --json-schema is used.
  const skills = parsed.structured_output?.selected_skills ?? [];
  return skills.filter((s) => s !== 'none');
}

function main() {
  console.log(`\nLoading skills from ${SKILLS_DIR}`);
  const skills = loadSkills();
  console.log(
    `  Found ${skills.length} skills: ${skills.map((s) => s.name).join(', ')}`
  );

  const systemPrompt = buildSystemPrompt(skills);
  const jsonSchema = buildJsonSchema(skills);

  console.log(`\nLoading eval cases from trigger-eval.json`);
  const evalCases: EvalCase[] = JSON.parse(readFileSync(EVALS_FILE, 'utf-8'));
  console.log(`  Found ${evalCases.length} test cases\n`);

  console.log(`Model:        ${MODEL}`);
  console.log(`Target skill: ${TARGET_SKILL}`);
  console.log(`Delay:        ${DELAY_MS}ms between calls\n`);
  console.log("\u2500".repeat(100));

  const results: EvalResult[] = [];

  for (let i = 0; i < evalCases.length; i++) {
    const evalCase = evalCases[i];
    const shortPrompt =
      evalCase.prompt.length > 70
        ? evalCase.prompt.slice(0, 67) + '...'
        : evalCase.prompt;

    process.stdout.write(
      `[${String(i + 1).padStart(2)}/${evalCases.length}] ${shortPrompt.padEnd(72)}`
    );

    try {
      const triggeredSkills = callClaude(evalCase.prompt, systemPrompt, jsonSchema);
      const didTrigger = triggeredSkills.includes(TARGET_SKILL);
      const pass = didTrigger === evalCase.should_trigger;

      results.push({
        index: i + 1,
        prompt: evalCase.prompt,
        expected: evalCase.should_trigger,
        actual: didTrigger,
        triggered_skills: triggeredSkills,
        pass,
      });

      const icon = pass ? '\u2705' : '\u274C';
      const expectedStr = evalCase.should_trigger ? 'trigger' : 'skip   ';
      const actualStr = didTrigger ? 'triggered' : 'skipped  ';
      const skillList =
        triggeredSkills.length > 0 ? ` [${triggeredSkills.join(', ')}]` : '';
      console.log(` ${icon} expect=${expectedStr} got=${actualStr}${skillList}`);
    } catch (err) {
      const msg = (err as Error).message;
      console.log(` \u26A0\uFE0F  ERROR: ${msg.slice(0, 80)}`);
      results.push({
        index: i + 1,
        prompt: evalCase.prompt,
        expected: evalCase.should_trigger,
        actual: false,
        triggered_skills: [],
        pass: false,
        error: msg,
      });
    }

    if (i < evalCases.length - 1 && DELAY_MS > 0) {
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, DELAY_MS);
    }
  }

  console.log('\n' + '\u2500'.repeat(100));

  const passed = results.filter((r) => r.pass).length;
  const failed = results.filter((r) => !r.pass).length;
  const errors = results.filter((r) => r.error).length;
  const total = results.length;

  console.log(`\nResults: ${passed}/${total} passed, ${failed} failed${errors ? `, ${errors} errors` : ''}`);

  // True/false positive/negative breakdown.
  const tp = results.filter((r) => r.expected && r.actual).length;
  const tn = results.filter((r) => !r.expected && !r.actual).length;
  const fp = results.filter((r) => !r.expected && r.actual).length;
  const fn = results.filter((r) => r.expected && !r.actual).length;

  console.log(
    `\n  True positives:  ${tp}   (correctly triggered)`
  );
  console.log(
    `  True negatives:  ${tn}   (correctly skipped)`
  );
  console.log(
    `  False positives: ${fp}   (triggered when shouldn't)`
  );
  console.log(
    `  False negatives: ${fn}   (missed when should trigger)`
  );

  if (total > 0) {
    const precision = tp + fp > 0 ? tp / (tp + fp) : 1;
    const recall = tp + fn > 0 ? tp / (tp + fn) : 1;
    const f1 = precision + recall > 0 ? (2 * precision * recall) / (precision + recall) : 0;
    console.log(`\n  Precision: ${(precision * 100).toFixed(1)}%`);
    console.log(`  Recall:    ${(recall * 100).toFixed(1)}%`);
    console.log(`  F1 Score:  ${(f1 * 100).toFixed(1)}%`);
  }

  const failures = results.filter((r) => !r.pass);
  if (failures.length > 0) {
    console.log('\nFailures:');
    for (const f of failures) {
      const dir = f.expected ? 'MISSED (false negative)' : 'WRONG (false positive)';
      console.log(`  [${String(f.index).padStart(2)}] ${dir}`);
      console.log(`       "${f.prompt}"`);
      console.log(
        `       Skills called: [${f.triggered_skills.join(', ') || 'none'}]${f.error ? ` Error: ${f.error}` : ''}`
      );
    }
  }

  // Write the results to a json file.
  const outFile = join(__dirname, 'trigger-eval-results.json');
  writeFileSync(
    outFile,
    JSON.stringify(
      {
        model: MODEL,
        target_skill: TARGET_SKILL,
        timestamp: new Date().toISOString(),
        summary: { total, passed, failed, errors, tp, tn, fp, fn },
        results: results.map((r) => ({
          index: r.index,
          prompt: r.prompt,
          expected: r.expected,
          actual: r.actual,
          triggered_skills: r.triggered_skills,
          pass: r.pass,
          ...(r.error ? { error: r.error } : {}),
        })),
      },
      null,
      2
    )
  );
  console.log(`\nResults written to trigger-eval-results.json`);

  process.exit(failed > 0 ? 1 : 0);
}

main();
