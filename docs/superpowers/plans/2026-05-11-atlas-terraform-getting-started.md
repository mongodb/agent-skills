# Atlas Terraform Getting Started — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the `atlas-terraform-getting-started` skill that interactively generates ready-to-apply Terraform configs using the official MongoDB Atlas Landing Zone Modules.

**Architecture:** A single `SKILL.md` containing the complete interactive workflow, HCL templates, and MCP enrichment instructions. Supporting test artifacts live under `testing/`. No application code — only Markdown and JSON.

**Tech Stack:** SKILL.md (Markdown + YAML frontmatter), HCL snippets embedded as code blocks, JSON test cases, `skill-validator` CLI for validation.

---

## File Map

| Action | Path | Purpose |
|---|---|---|
| Create | `skills/atlas-terraform-getting-started/SKILL.md` | The skill itself — the only runtime deliverable |
| Create | `testing/atlas-terraform-getting-started/evals/evals.json` | Eval prompts that validate skill behavior |
| Create | `testing/skills-boundaries/atlas-terraform-vs-existing-skills.json` | Boundary test cases |

---

## Task 1: Create skill directory and write SKILL.md

**Files:**
- Create: `skills/atlas-terraform-getting-started/SKILL.md`

- [ ] **Step 1.1: Create the skill directory**

```bash
mkdir -p skills/atlas-terraform-getting-started
```

- [ ] **Step 1.2: Write SKILL.md**

Create `skills/atlas-terraform-getting-started/SKILL.md` with the following exact content:

````markdown
---
name: atlas-terraform-getting-started
description: >-
  Use this skill when a user wants to get started with the MongoDB Atlas Terraform provider,
  set up Atlas infrastructure using Terraform, create their first Atlas cluster via Terraform,
  or asks "how do I use Terraform with MongoDB Atlas", "how do I create an Atlas cluster with
  Terraform", "Terraform Atlas getting started", or expresses intent to deploy/create/configure
  Atlas using Terraform. Also triggers on "terraform mongodbatlas provider" combined with any
  setup, create, or deploy intent.
  Does NOT trigger for: general Terraform questions unrelated to Atlas, optimizing or refactoring
  existing Atlas Terraform configs, Atlas Search or Vector Search index management via Terraform,
  or cloud-specific integrations (PrivateLink, KMS/CMEK, backup export) — those are separate skills.
allowed-tools: mcp__mongodb__*, WebSearch, Bash(gh *)
---

# MongoDB Atlas Terraform — Getting Started

You generate complete, ready-to-`terraform apply` Terraform configurations for MongoDB Atlas using the official Landing Zone Modules. Always follow this workflow in order.

---

## Step 0: Module Disclosure (Always First)

Before asking any questions or generating any code, show this message:

> I'll generate your Terraform configuration using the official [MongoDB Atlas Landing Zone Modules](https://github.com/terraform-mongodbatlas-modules). These modules are officially maintained by MongoDB, embed best practices as defaults, and are the recommended way to manage Atlas infrastructure with Terraform.

---

## Step 1: Resolve Latest Versions

Fetch the latest versions before generating any HCL. Never hardcode versions — always resolve at generation time.

### 1a: Provider version (`mongodb/mongodbatlas`)

Try each source in order until one succeeds:

1. `WebSearch`: query `mongodb/mongodbatlas terraform provider latest release site:github.com`
2. `Bash`: `gh api repos/mongodb/terraform-provider-mongodbatlas/releases/latest --jq '.tag_name'`

Strip the leading `v`. Use this as `PROVIDER_VERSION`. Constraint in HCL: `~> 2.0`.

### 1b: Project module version (`terraform-mongodbatlas-modules/terraform-mongodbatlas-project`)

Try each source in order:

1. `WebSearch`: query `terraform-mongodbatlas-modules terraform-mongodbatlas-project latest release`
2. `Bash`: `gh api repos/terraform-mongodbatlas-modules/terraform-mongodbatlas-project/releases/latest --jq '.tag_name'`

This is a v1 stable module. Use constraint `~> 1.0`.

### 1c: Cluster module version (`terraform-mongodbatlas-modules/terraform-mongodbatlas-cluster`)

Try each source in order:

1. `WebSearch`: query `terraform-mongodbatlas-modules terraform-mongodbatlas-cluster latest release`
2. `Bash`: `gh api repos/terraform-mongodbatlas-modules/terraform-mongodbatlas-cluster/releases/latest --jq '.tag_name'`

This is a Public Preview (v0) module. Use constraint `>= 0.1, < 1.0`.

---

## Step 2: Gather User Inputs

Ask questions in sequence. Stop after each answer before asking the next.

### Question 1 — Project

> "Do you have an existing Atlas project, or do you need to create a new one?"

- **Existing project:**
  - If MCP is connected: call `mcp__MongoDB__atlas-list-projects` and present the list so the user can pick. Store the selected project ID as `USER_PROJECT_ID`.
  - If MCP is not connected: ask "What is your Atlas Project ID?" (Atlas UI → Project Settings → Project ID).
- **New project:**
  - Ask "What would you like to name your new project?"
  - If MCP is connected: call `mcp__MongoDB__atlas-list-orgs` to get the org ID automatically and confirm with the user.
  - If MCP is not connected: ask "What is your Atlas Organization ID?" (Atlas UI → Organization Settings → Organization ID).

### Question 2 — Cloud provider

> "Which cloud provider are you deploying to? (AWS / Azure / GCP)"

### Question 3 — Region

> "Which region would you like to deploy to?"

- **If MCP is connected:** call `mcp__MongoDB__atlas-list-clusters` to find regions already in use by other clusters in the org. Present those as suggestions plus "other".
- **If MCP is not connected:** show this table and ask the user to pick or type their own:

| Provider | Common regions to try |
|---|---|
| AWS | `US_EAST_1`, `EU_WEST_1`, `AP_SOUTHEAST_1` |
| Azure | `US_EAST_2`, `EUROPE_WEST`, `ASIA_PACIFIC_SOUTHEAST` |
| GCP | `CENTRAL_US`, `WESTERN_EUROPE`, `EASTERN_ASIA_PACIFIC` |

Full region reference: https://www.mongodb.com/docs/atlas/cloud-providers-regions/

### Question 4 — Depth

> "Do you want a **minimal** config (M10, fastest to run, no backup) or a **production-ready** config (M60+, backup enabled, autoscaling tuned for production)?"

| Option | Instance size | Backup | Autoscaling `compute_min` |
|---|---|---|---|
| Minimal | M10 | Off | M10 (default) |
| Production-ready | M60 | On | M60 |

### Question 5 — Cluster name (optional)

> "What would you like to name your cluster?" (press Enter to use `my-cluster`)

---

## Step 3: Generate the 5 Files

⚠️ **Important constraints from the cluster module:**
- Minimum instance size is **M10**. M0, M2, and M5 are not supported by this module.
- All clusters generated by this skill use a **sharded topology**. Set `shard_number = 0` on region blocks.
- The cluster module is in **Public Preview (v0)**. Show this notice once: _"Note: the cluster module is in Public Preview. It is officially supported by MongoDB but upgrades from v0 → v1 may require manual migration steps."_

---

### File 1: `versions.tf`

```hcl
terraform {
  required_providers {
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = "~> 2.0"  # latest resolved: PROVIDER_VERSION
    }
  }
  required_version = ">= 1.0"
}
```

---

### File 2: `variables.tf`

```hcl
# Authentication — Service Account (preferred)
# Atlas UI → Access Manager → Service Accounts → Create Service Account
variable "atlas_client_id" {
  description = "MongoDB Atlas Service Account client ID."
  type        = string
  sensitive   = true
}

variable "atlas_client_secret" {
  description = "MongoDB Atlas Service Account client secret."
  type        = string
  sensitive   = true
}

variable "org_id" {
  description = "MongoDB Atlas Organization ID. Atlas UI → Organization Settings → Organization ID."
  type        = string
}

# Only include this block when using an EXISTING project (omit when creating a new one)
variable "project_id" {
  description = "Existing MongoDB Atlas Project ID. Atlas UI → Project Settings → Project ID."
  type        = string
}

variable "region" {
  description = "Atlas cloud region name, e.g. US_EAST_1 (AWS), EUROPE_WEST (Azure), CENTRAL_US (GCP)."
  type        = string
}
```

Omit `variable "project_id"` entirely when the user is creating a new project.

---

### File 3a: `main.tf` — creating a new project

```hcl
provider "mongodbatlas" {
  client_id     = var.atlas_client_id
  client_secret = var.atlas_client_secret
}

module "project" {
  source  = "terraform-mongodbatlas-modules/terraform-mongodbatlas-project/mongodbatlas"
  version = "~> 1.0"

  org_id = var.org_id
  name   = "PROJECT_NAME"
}

module "cluster" {
  source  = "terraform-mongodbatlas-modules/terraform-mongodbatlas-cluster/mongodbatlas"
  version = ">= 0.1, < 1.0"

  name       = "CLUSTER_NAME"
  project_id = module.project.id

  provider_name = "PROVIDER"  # AWS, AZURE, or GCP

  regions = [
    {
      name         = var.region
      node_count   = 3
      shard_number = 0
    }
  ]

  # MINIMAL ONLY — omit for production (autoscaling handles instance size)
  instance_size = "M10"
}
```

For **production-ready**, replace the `instance_size` line with:

```hcl
  auto_scaling = {
    compute_enabled            = true
    compute_max_instance_size  = "M200"
    compute_min_instance_size  = "M60"
    compute_scale_down_enabled = true
    disk_gb_enabled            = true
  }

  backup_enabled = true
```

### File 3b: `main.tf` — using an existing project

Replace the `module "project"` block with a `locals` block:

```hcl
provider "mongodbatlas" {
  client_id     = var.atlas_client_id
  client_secret = var.atlas_client_secret
}

locals {
  project_id = var.project_id
}

module "cluster" {
  source  = "terraform-mongodbatlas-modules/terraform-mongodbatlas-cluster/mongodbatlas"
  version = ">= 0.1, < 1.0"

  name       = "CLUSTER_NAME"
  project_id = local.project_id

  provider_name = "PROVIDER"  # AWS, AZURE, or GCP

  regions = [
    {
      name         = var.region
      node_count   = 3
      shard_number = 0
    }
  ]

  # MINIMAL ONLY
  instance_size = "M10"
}
```

---

### File 4: `outputs.tf`

When creating a **new project**:

```hcl
output "connection_string" {
  description = "MongoDB SRV connection string."
  value       = tolist(module.cluster.connection_strings)[0].standard_srv
}

output "project_id" {
  description = "Atlas project ID."
  value       = module.project.id
}

output "cluster_id" {
  description = "Atlas cluster ID."
  value       = module.cluster.cluster_id
}
```

When using an **existing project**, replace `module.project.id` with `var.project_id`:

```hcl
output "connection_string" {
  description = "MongoDB SRV connection string."
  value       = tolist(module.cluster.connection_strings)[0].standard_srv
}

output "project_id" {
  description = "Atlas project ID."
  value       = var.project_id
}

output "cluster_id" {
  description = "Atlas cluster ID."
  value       = module.cluster.cluster_id
}
```

---

### File 5: `terraform.tfvars.example`

```hcl
# Copy this file to terraform.tfvars and fill in your values.
# ⚠️  NEVER commit terraform.tfvars to version control — it contains secrets.

# Service Account credentials
# Atlas UI → Access Manager → Service Accounts → Create Service Account
atlas_client_id     = "<replace-me>"
atlas_client_secret = "<replace-me>"

# Organization ID
# Atlas UI → (org name in top-left) → Settings → Organization ID
org_id = "<replace-me>"

# Existing project ID (remove this line if you are creating a new project)
# Atlas UI → Project Settings → Project ID
project_id = "<replace-me>"

# Cloud region — must match Atlas format, e.g.:
#   AWS:   US_EAST_1, EU_WEST_1, AP_SOUTHEAST_1
#   Azure: US_EAST_2, EUROPE_WEST, ASIA_PACIFIC_SOUTHEAST
#   GCP:   CENTRAL_US, WESTERN_EUROPE, EASTERN_ASIA_PACIFIC
region = "<replace-me>"
```

If MCP is connected, replace `<replace-me>` with real values for `org_id` and `project_id`.

---

## Step 4: Post-Generation Block

After presenting all 5 files, always append this section verbatim:

```
## Next Steps

1. Copy `terraform.tfvars.example` → `terraform.tfvars` and fill in your credentials.
   Add these lines to your `.gitignore` to avoid committing secrets:
     terraform.tfvars
     .terraform/
     *.tfstate
     *.tfstate.backup

2. Initialize Terraform (downloads the provider and modules):
   terraform init

3. Review what will be created:
   terraform plan

4. Apply:
   terraform apply

## Useful Links

- Atlas Provider docs:    https://registry.terraform.io/providers/mongodb/mongodbatlas/latest/docs
- Cluster module:         https://github.com/terraform-mongodbatlas-modules/terraform-mongodbatlas-cluster
- Project module:         https://github.com/terraform-mongodbatlas-modules/terraform-mongodbatlas-project
- Atlas regions:          https://www.mongodb.com/docs/atlas/cloud-providers-regions/
- Service Account setup:  https://www.mongodb.com/docs/atlas/configure-api-access/
```

---

## Safety Rules

- **Never hardcode credentials.** All sensitive values must be in `sensitive = true` variables.
- **Minimum tier is M10.** Always tell the user if they ask for M0/M2/M5 that the module requires M10+.
- **Always sharded.** Set `shard_number = 0` on all region blocks — never omit it.
- **No write operations without confirmation.** If MCP is connected, only pre-fill non-sensitive data (org ID, project ID). Never call create/update/delete MCP tools.
- **Remind about `.gitignore`.** Always include the `.gitignore` note in the next-steps block.

---

## Out of Scope

If the user asks about any of the following, explain this skill covers getting-started only and point them to the right resource:

| Request | Resource |
|---|---|
| PrivateLink, KMS/CMEK, backup export, S3 log integration | `atlas-terraform-cloud-integration` skill (coming soon) — covers `terraform-mongodbatlas-atlas-aws/azure/gcp` modules |
| Optimizing or importing existing Terraform configs | `terraform import` docs + provider resource docs |
| Organization management | `terraform-mongodbatlas-organization` module README |
| Atlas Search / Vector Search indexes | Atlas Search Terraform resource docs |
| General Terraform errors unrelated to Atlas | HashiCorp Terraform docs |
````

- [ ] **Step 1.3: Verify the file was created**

```bash
ls -la skills/atlas-terraform-getting-started/
```

Expected output: `SKILL.md` present.

- [ ] **Step 1.4: Commit**

```bash
git add skills/atlas-terraform-getting-started/SKILL.md
git commit -m "feat: add atlas-terraform-getting-started skill"
```

---

## Task 2: Write eval tests

**Files:**
- Create: `testing/atlas-terraform-getting-started/evals/evals.json`

- [ ] **Step 2.1: Create the testing directory**

```bash
mkdir -p testing/atlas-terraform-getting-started/evals
```

- [ ] **Step 2.2: Write evals.json**

Create `testing/atlas-terraform-getting-started/evals/evals.json`:

```json
{
  "skill_name": "atlas-terraform-getting-started",
  "evals": [
    {
      "id": 1,
      "name": "basic-getting-started",
      "prompt": "I want to deploy MongoDB Atlas using Terraform. How do I get started?",
      "expected_output": "Shows module disclosure, asks 5 interactive questions (project, cloud provider, region, depth, cluster name), resolves latest provider and module versions via WebSearch or gh CLI, generates all 5 files (versions.tf, variables.tf, main.tf, outputs.tf, terraform.tfvars.example), appends next-steps block",
      "files": []
    },
    {
      "id": 2,
      "name": "create-new-project-aws-minimal",
      "prompt": "Create a Terraform config for a new Atlas project and cluster on AWS us-east-1, minimal setup",
      "expected_output": "Generates main.tf with both module 'project' and module 'cluster' blocks, provider_name=AWS, region=US_EAST_1, instance_size=M10, shard_number=0 in regions block, no backup_enabled, no auto_scaling override. Project module source is terraform-mongodbatlas-modules/terraform-mongodbatlas-project/mongodbatlas. Cluster module source is terraform-mongodbatlas-modules/terraform-mongodbatlas-cluster/mongodbatlas. outputs.tf uses module.project.id (not project_id). Includes Public Preview notice for cluster module.",
      "files": []
    },
    {
      "id": 3,
      "name": "existing-project-production-azure",
      "prompt": "I already have an Atlas project. Set up a production Terraform config for Azure West Europe.",
      "expected_output": "Asks for existing project ID, generates main.tf with locals block (no module 'project'), provider_name=AZURE, region=EUROPE_WEST, auto_scaling block with compute_min_instance_size=M60 and compute_max_instance_size=M200 and disk_gb_enabled=true, backup_enabled=true, shard_number=0. variables.tf includes project_id variable. outputs.tf uses var.project_id.",
      "files": []
    },
    {
      "id": 4,
      "name": "always-sharded-topology",
      "prompt": "Generate a Terraform config for an Atlas cluster on GCP",
      "expected_output": "regions block contains shard_number=0. No replica set topology. cluster_type is not explicitly set (module defaults to SHARDED when shard_number is present).",
      "files": []
    },
    {
      "id": 5,
      "name": "version-resolution",
      "prompt": "Set up Atlas with Terraform",
      "expected_output": "Attempts to resolve latest mongodbatlas provider version using WebSearch or gh API before generating versions.tf. Provider version constraint is ~> 2.0. Does not hardcode a specific patch version without resolving it first.",
      "files": []
    },
    {
      "id": 6,
      "name": "m0-rejection",
      "prompt": "Create an Atlas Terraform config with an M0 free tier cluster",
      "expected_output": "Explains that the cluster module (terraform-mongodbatlas-cluster) does not support M0, M2, or M5 — minimum is M10. Offers M10 as the minimal alternative and asks if the user wants to proceed with M10.",
      "files": []
    },
    {
      "id": 7,
      "name": "out-of-scope-privatelink",
      "prompt": "Set up Atlas Terraform with PrivateLink on AWS",
      "expected_output": "Explains this skill covers getting-started (project + cluster) only. PrivateLink is handled by the atlas-terraform-cloud-integration skill (coming soon) which uses the terraform-mongodbatlas-atlas-aws module. Offers to generate the base cluster config first if desired.",
      "files": []
    },
    {
      "id": 8,
      "name": "mcp-project-list",
      "prompt": "Help me create an Atlas Terraform config. I already have a project.",
      "expected_output": "If MCP is connected: calls mcp__MongoDB__atlas-list-projects to show available projects before asking the user to type a project ID. If MCP is not connected: asks for the project ID and tells user where to find it (Atlas UI → Project Settings).",
      "files": []
    },
    {
      "id": 9,
      "name": "gitignore-reminder",
      "prompt": "Generate a Terraform config for Atlas on GCP central US",
      "expected_output": "Post-generation next-steps block includes .gitignore instructions covering terraform.tfvars, .terraform/, *.tfstate, *.tfstate.backup",
      "files": []
    },
    {
      "id": 10,
      "name": "service-account-auth",
      "prompt": "Create a Terraform config for a new Atlas cluster",
      "expected_output": "Provider block uses client_id and client_secret (Service Account, preferred). variables.tf declares atlas_client_id and atlas_client_secret as sensitive string variables. Comments explain these come from Atlas UI → Access Manager → Service Accounts.",
      "files": []
    }
  ]
}
```

- [ ] **Step 2.3: Commit**

```bash
git add testing/atlas-terraform-getting-started/
git commit -m "test: add evals for atlas-terraform-getting-started skill"
```

---

## Task 3: Write skill-boundary tests

**Files:**
- Create: `testing/skills-boundaries/atlas-terraform-vs-existing-skills.json`

- [ ] **Step 3.1: Write boundary test file**

Create `testing/skills-boundaries/atlas-terraform-vs-existing-skills.json`:

```json
{
  "test_suite": "Atlas Terraform Getting Started — Skill Boundary Tests",
  "description": "Validates that atlas-terraform-getting-started triggers on the correct prompts and does NOT trigger when another skill is more appropriate.",
  "version": "1.0",
  "skills_tested": [
    "atlas-terraform-getting-started",
    "mongodb-natural-language-querying",
    "mongodb-query-optimizer",
    "atlas-stream-processing"
  ],
  "test_cases": [
    {
      "id": 1,
      "category": "clear_terraform_trigger",
      "prompt": "How do I create a MongoDB Atlas cluster using Terraform?",
      "expected_skill": "atlas-terraform-getting-started",
      "should_not_trigger": "mongodb-natural-language-querying",
      "reasoning": "Explicit Terraform + Atlas cluster creation intent",
      "trigger_keywords": ["Terraform", "Atlas cluster", "create"]
    },
    {
      "id": 2,
      "category": "clear_terraform_trigger",
      "prompt": "Set up MongoDB Atlas infrastructure as code with Terraform",
      "expected_skill": "atlas-terraform-getting-started",
      "should_not_trigger": "atlas-stream-processing",
      "reasoning": "Infrastructure-as-code setup intent with explicit Terraform mention",
      "trigger_keywords": ["Terraform", "infrastructure as code"]
    },
    {
      "id": 3,
      "category": "clear_terraform_trigger",
      "prompt": "Generate a terraform.tf file to deploy Atlas on AWS",
      "expected_skill": "atlas-terraform-getting-started",
      "should_not_trigger": "mongodb-query-optimizer",
      "reasoning": "Explicit request to generate Terraform config for Atlas",
      "trigger_keywords": ["terraform.tf", "Atlas", "AWS"]
    },
    {
      "id": 4,
      "category": "clear_terraform_trigger",
      "prompt": "I want to use the mongodbatlas Terraform provider to create my first cluster",
      "expected_skill": "atlas-terraform-getting-started",
      "should_not_trigger": "mongodb-natural-language-querying",
      "reasoning": "Explicit mention of mongodbatlas provider with first cluster intent",
      "trigger_keywords": ["mongodbatlas", "Terraform provider", "first cluster"]
    },
    {
      "id": 5,
      "category": "boundary_not_terraform",
      "prompt": "Find all users in my MongoDB Atlas cluster who logged in today",
      "expected_skill": "mongodb-natural-language-querying",
      "should_not_trigger": "atlas-terraform-getting-started",
      "reasoning": "Query generation request, no Terraform intent",
      "trigger_keywords": ["find", "users", "query"]
    },
    {
      "id": 6,
      "category": "boundary_not_terraform",
      "prompt": "Why is my MongoDB query slow? How do I add an index?",
      "expected_skill": "mongodb-query-optimizer",
      "should_not_trigger": "atlas-terraform-getting-started",
      "reasoning": "Query optimization request, no Terraform intent",
      "trigger_keywords": ["query slow", "index"]
    },
    {
      "id": 7,
      "category": "boundary_not_terraform",
      "prompt": "Create an Atlas Stream Processing workspace for Kafka",
      "expected_skill": "atlas-stream-processing",
      "should_not_trigger": "atlas-terraform-getting-started",
      "reasoning": "Stream Processing workspace creation, not Terraform IaC",
      "trigger_keywords": ["Stream Processing", "Kafka", "workspace"]
    },
    {
      "id": 8,
      "category": "boundary_existing_config",
      "prompt": "My Terraform Atlas config is failing with a 403 error on terraform apply",
      "expected_skill": "atlas-terraform-getting-started",
      "should_not_trigger": "mongodb-query-optimizer",
      "reasoning": "Terraform + Atlas troubleshooting falls within skill scope even for existing configs",
      "trigger_keywords": ["Terraform", "terraform apply", "Atlas", "error"]
    },
    {
      "id": 9,
      "category": "boundary_out_of_scope",
      "prompt": "How do I configure PrivateLink for Atlas using Terraform?",
      "expected_skill": "atlas-terraform-getting-started",
      "should_not_trigger": "atlas-stream-processing",
      "reasoning": "PrivateLink is out of scope for this skill but still a Terraform+Atlas question — skill should handle it gracefully by explaining scope and redirecting",
      "trigger_keywords": ["PrivateLink", "Terraform", "Atlas"]
    },
    {
      "id": 10,
      "category": "boundary_general_terraform",
      "prompt": "How do I write a for_each loop in Terraform?",
      "expected_skill": null,
      "should_not_trigger": "atlas-terraform-getting-started",
      "reasoning": "General Terraform HCL question, no Atlas context",
      "trigger_keywords": ["for_each", "Terraform"]
    }
  ]
}
```

- [ ] **Step 3.2: Commit**

```bash
git add testing/skills-boundaries/atlas-terraform-vs-existing-skills.json
git commit -m "test: add skill-boundary tests for atlas-terraform-getting-started"
```

---

## Task 4: Validate with skill-validator

**Files:** None created — validation only.

- [ ] **Step 4.1: Run validation against the new skill**

```bash
./tools/validate-skills.sh skills/atlas-terraform-getting-started/
```

Expected output: all checks pass, no errors or warnings. If `skill-validator` is not installed:

```bash
brew tap agent-ecosystem/homebrew-tap && brew install skill-validator
```

Then re-run.

- [ ] **Step 4.2: Fix any validation errors**

Common issues and fixes:

| Error | Fix |
|---|---|
| `description too short` | Expand the `description` field in frontmatter |
| `name does not match directory` | Ensure `name: atlas-terraform-getting-started` matches `skills/atlas-terraform-getting-started/` |
| `invalid allowed-tools pattern` | Check that `allowed-tools` values match the validator's accepted patterns |
| `missing required frontmatter field` | Add the missing field (name, description are required) |

- [ ] **Step 4.3: Commit any fixes**

```bash
git add skills/atlas-terraform-getting-started/SKILL.md
git commit -m "fix: address skill-validator issues in atlas-terraform-getting-started"
```

_(Skip this step if Step 4.1 passed cleanly.)_

---

## Task 5: Final validation — all skills pass

- [ ] **Step 5.1: Run full validation suite**

```bash
./tools/validate-skills.sh
```

Expected: all 8 skills pass (7 existing + 1 new). Zero errors.

- [ ] **Step 5.2: Confirm git log**

```bash
git log --oneline -5
```

Expected: 3–4 commits from this implementation on branch `marcosuma-terraform-provider-skill`.
