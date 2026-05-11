# Design Spec: `atlas-terraform-getting-started` Skill

**Date:** 2026-05-11  
**Status:** Approved  
**Author:** Marco Suma

---

## Overview

A new agent skill that guides users through their first MongoDB Atlas deployment using Terraform. The skill is interactive — it asks the user 4–5 targeted questions, then generates a complete, ready-to-`terraform apply` configuration using the official MongoDB Atlas Landing Zone Modules. MCP enrichment is optional and enriches the output (pre-filling org/project IDs, suggesting regions) when a live Atlas connection is available.

This spec covers the **getting-started** scope only: project + cluster. Cloud-specific integrations (PrivateLink, KMS, backup export) are out of scope and will be addressed in a follow-up skill.

---

## Skill Identity

| Field | Value |
|---|---|
| **Name** | `atlas-terraform-getting-started` |
| **Location** | `skills/atlas-terraform-getting-started/SKILL.md` |
| **Allowed tools** | `mcp__mongodb__*` (optional), `web_search`, `github` |
| **Terraform registry tool** | `mcp__plugin_terraform_terraform__get_latest_provider_version` (optional, for version pinning) |

### Trigger Description

Triggers when a user wants to get started with the MongoDB Atlas Terraform provider, set up Atlas infrastructure using Terraform, create their first Atlas cluster via Terraform, or asks:

- "how do I use Terraform with MongoDB Atlas"
- "how do I create an Atlas cluster with Terraform"
- "Terraform Atlas getting started"
- "terraform mongodbatlas provider" + any setup/create/deploy intent

**Does NOT trigger for:**
- General Terraform questions unrelated to Atlas
- Optimizing or refactoring existing Atlas Terraform configs
- Atlas Search or Vector Search index management via Terraform
- Cloud-specific integrations (PrivateLink, KMS, backup export) — separate skill

---

## Interactive Flow

The skill always starts with a **module disclosure** before asking any questions. Then it asks at most 5 questions in sequence.

### Step 0 — Disclosure (always first)

> "I'll use the official [MongoDB Atlas Landing Zone Modules](https://github.com/terraform-mongodbatlas-modules) to generate your configuration. These are officially maintained by MongoDB and embed best practices as defaults."

### Step 1 — Project

> "Do you have an existing Atlas project, or do you need to create a new one?"

- **Existing** → ask for the Project ID (or, if MCP is connected, present a list of the user's projects to pick from)
- **New** → ask for a project name

### Step 2 — Cloud provider

> "Which cloud provider are you deploying to?"

Options: **AWS** / **Azure** / **GCP**

### Step 3 — Region

> "Which region would you like to deploy to?"

- **MCP connected:** surface the org's most-used regions as suggestions, plus an "other" option
- **MCP not connected:** show the 3 most common defaults per cloud provider (e.g., `US_EAST_1`, `EU_WEST_1`, `AP_SOUTHEAST_1` for AWS), plus "other" with a link to the full region list

### Step 4 — Depth

> "Do you want a minimal config or a production-ready config?"

| Option | Cluster tier | Backup | Security defaults |
|---|---|---|---|
| **Minimal** | M0 (free) or M10 | Off | Basic |
| **Production-ready** | M60+ | Enabled | Full recommended set + autoscaling |

### Step 5 — Cluster name (optional)

> "What would you like to name your cluster?" (defaults to `"my-cluster"` if skipped)

### MCP shortcutting

When MCP is connected, Steps 1 and 3 are pre-answered where possible and **shown to the user for confirmation** rather than asked blind. This keeps the user in control while reducing friction.

---

## Generated Output

The skill produces 5 files. All module versions are pinned to the latest available tag at generation time.

### `versions.tf`

```hcl
terraform {
  required_providers {
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = "~> 2.0"  # pinned to latest 2.x at generation time
    }
  }
  required_version = ">= 1.0"
}
```

The provider version is always `~> 2.0`, with the exact latest `2.x` patch fetched at generation time via `mcp__plugin_terraform_terraform__get_latest_provider_version` (if available), the Terraform registry API, or `web_search` / `github` as a fallback. The same freshness strategy applies to all module version pins — the skill actively resolves the latest release rather than hardcoding a version.

### `main.tf`

Contains two module blocks:

1. **`module "project"`** (only when creating a new project):
   ```hcl
   module "project" {
     source  = "terraform-mongodbatlas-modules/terraform-mongodbatlas-project/mongodbatlas"
     version = "~> 1.0"  # v1 stable, 2-year no-breaking-changes commitment
     # ...
   }
   ```

2. **`module "cluster"`**:
   ```hcl
   module "cluster" {
     source  = "terraform-mongodbatlas-modules/terraform-mongodbatlas-cluster/mongodbatlas"
     version = ">= 0.1, < 1.0"  # Public Preview — see note below
     # ...
   }
   ```

**Cluster topology rules (both tiers):**
- Clusters are **always sharded** (no single-region replica sets). The cluster module's `regions` variable drives sharding topology.
- **Autoscaling is always enabled for production-ready configs** (`auto_scaling_disk_gb_enabled = true`, compute autoscaling enabled with appropriate min/max bounds).
- Minimal configs (M0/M10) use the simplest valid sharded topology. Production-ready configs use M60+, enable backup, autoscaling, and all recommended security defaults exposed by the cluster module.

### `variables.tf`

Declares:
- `atlas_client_id` / `atlas_client_secret` (preferred — Service Account)
- `atlas_public_key` / `atlas_private_key` (alternative — API key)
- `org_id`
- `project_id` (only when using an existing project)
- `region`

### `outputs.tf`

```hcl
output "connection_string" { value = module.cluster.connection_strings[0].standard_srv }
output "project_id"        { value = module.project.project_id }  # or var.project_id
output "cluster_id"        { value = module.cluster.cluster_id }
```

### `terraform.tfvars.example`

A filled-in example the user copies and renames to `terraform.tfvars`. When MCP is connected, `org_id` and `project_id` are pre-filled with real values. All credential fields are left as `"<replace-me>"` placeholders with inline comments pointing to the Atlas UI.

---

## Post-Generation Block

After producing files, the skill always appends a "next steps" section:

```
# Next steps:
# 1. Copy terraform.tfvars.example → terraform.tfvars and fill in your credentials
#    Credentials: Atlas UI → Access Manager → Service Accounts (preferred)
#    or: Atlas UI → Access Manager → API Keys
# 2. terraform init
# 3. terraform plan
# 4. terraform apply
```

---

## Module Versioning & Preview Notices

| Module | Status | Version constraint | Notice shown |
|---|---|---|---|
| `terraform-mongodbatlas-project` | v1 stable | `~> 1.0` | None |
| `terraform-mongodbatlas-cluster` | Public Preview (v0) | `>= 0.1, < 1.0` | "Note: the cluster module is in Public Preview. It is officially supported by MongoDB but upgrades from v0 → v1 may require manual steps." |
| `terraform-mongodbatlas-organization` | Public Preview (v0) | Out of scope | N/A |
| `terraform-mongodbatlas-atlas-aws/azure/gcp` | v1 stable | Out of scope (follow-up skill) | N/A |

---

## MCP Enrichment Summary

| Data point | Source | Used for |
|---|---|---|
| Org ID | `mcp__MongoDB__atlas-list-orgs` | Pre-fills `org_id` in `terraform.tfvars.example` |
| Project list | `mcp__MongoDB__atlas-list-projects` | Step 1 — lets user pick instead of typing |
| Cluster regions | Existing clusters in org | Step 3 — surfaces already-used regions as suggestions |

If MCP is not connected, all placeholders include inline comments explaining where to find the values in the Atlas UI.

---

## Out of Scope (This Skill)

- Cloud integrations: PrivateLink, AWS KMS/CMEK, backup export, log integration → follow-up `atlas-terraform-cloud-integration` skill
- Managing existing Atlas Terraform configs (optimization, refactoring)
- Organization management (`terraform-mongodbatlas-organization` module)
- Atlas Search / Vector Search index resources
- Importing existing Atlas infrastructure into Terraform state

---

## Follow-up Skill (Future)

`atlas-terraform-cloud-integration` — covers the `terraform-mongodbatlas-atlas-aws`, `atlas-azure`, and `atlas-gcp` modules for users who need PrivateLink, CMEK, backup export, or log integration after their cluster is running.
