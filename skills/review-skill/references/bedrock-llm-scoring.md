# AWS Bedrock LLM Scoring Flow

Bedrock-specific prerequisites and LLM scoring steps. Only follow this if the
user selected AWS Bedrock access in Step 0.

## Bedrock Prerequisites

Complete after Step 1a (binary check) passes.

### Check for config file

```bash
cat .skill-validator-ent.yaml 2>/dev/null || cat ~/.config/skill-validator-ent/config.yaml 2>/dev/null
```

If the config exists with `model`, `region`, and `profile` keys, skip to the
AWS authentication check.

If missing, ask for their AWS profile (`aws configure list-profiles` to show
options) and region (default: `us-east-1`), then create
`~/.config/skill-validator-ent/config.yaml`:

```yaml
model: us.anthropic.claude-sonnet-4-5-20250929-v1:0
region: <user's region>
profile: <user's profile>
```

### Verify AWS authentication

```bash
aws sts get-caller-identity --profile <profile>
```

If this fails, follow [aws-auth-troubleshooting.md](aws-auth-troubleshooting.md)
to diagnose and fix. Re-run the check after the user acts.

Do NOT proceed until authentication succeeds.

## Run LLM Scoring (after structural validation passes)

Check for cached scores:

```bash
skill-validator-ent score report <path> -o json 2>/dev/null
```

If scored output exists, use `--rescore` to generate fresh scores (content may
have changed since the last run):

```bash
skill-validator-ent score evaluate <path> --full-content --display files -o json --rescore
```

If no cached scores exist, run without `--rescore`:

```bash
skill-validator-ent score evaluate <path> --full-content --display files -o json
```

If scoring fails with an authentication error, invalidate saved state:

```bash
rm -f ~/.config/skill-validator-ent/review-state.yaml
```

Then re-run the AWS authentication check.

After scoring completes, run the comparison report:

```bash
skill-validator-ent score report <path> -o json
```

Capture both outputs for interpretation.

## Interpret LLM Scores

Read [../assets/report.md](../assets/report.md) for the full interpretation
framework, then present results to the user following that structure.

### Quality thresholds

There are no hard pass/fail gates on most dimensions. Use these guidelines:

- **Overall >= 3.5**: The skill is in good shape across most dimensions.
- **Overall 2.5-3.5**: The skill needs work in specific areas. Identify which
  dimensions are dragging the score down and advise accordingly.
- **Overall < 2.5**: The skill needs significant revision across multiple areas.
- **Any dimension at 2 or below**: Flag this specifically as an area needing
  attention. Explain what a low score on that dimension means and suggest
  concrete improvements.

### Novelty is the key differentiator

If mean novelty across all files is below 3, the skill may not justify its
context window cost. A low-novelty skill restates what models already know.
The critical question: **does this skill teach the agent something it genuinely
doesn't know?**

### Surface `novel_info` for SME review

Each scored file includes a `novel_info` field describing what the LLM judge
identified as genuinely novel content. Present these details to the SME for
each file, because:

- **Verification**: The LLM may misidentify something as novel or miss truly
  novel content. The SME should confirm the claims are accurate.
- **Focus**: Items listed in `novel_info` represent the skill's highest-value
  content. If these details are wrong or missing, the novelty score is
  unreliable.
- **Trimming guidance**: Content NOT mentioned in `novel_info` is likely
  restating common knowledge and is a candidate for compression or removal.

If novelty is low, advise the SME to:

1. Identify which sections contain information that is NOT available in public
   documentation or model training data (proprietary APIs, internal conventions,
   non-obvious gotchas, organization-specific workflows).
2. Cut or compress sections that merely restate common knowledge.
3. Focus the skill on the genuinely novel content.

For more context on why novelty matters and how to think about skill quality,
refer the SME to: https://agentskillreport.com/

### Important scoring caveat

Scores are generated using Anthropic Claude, so novelty reflects what Claude
knows from training data. Other model families may produce different novelty
scores due to different training data coverage.

## Full Review Summary

When LLM scoring was performed, present the review summary with:

1. **Structural validation result**: Pass/fail, with any errors or warnings.
2. **LLM score summary**: Overall score and per-dimension breakdown for SKILL.md
   and references (if any).
3. **Areas to address**: Specific dimensions that need improvement, with concrete
   suggestions.
4. **Novelty assessment**: Whether the skill provides sufficient novel value,
   with specific guidance if it doesn't. Include the `novel_info` details for
   each file so the SME can verify accuracy and identify what to keep or cut.
5. **Recommendation**: Whether the skill is ready to publish, needs minor
   revisions, or needs significant rework.
