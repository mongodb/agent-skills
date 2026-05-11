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
allowed-tools: mcp__MongoDB__*, mcp__plugin_terraform_terraform__get_latest_provider_version, WebSearch, Bash(gh *), Bash(terraform *), Bash(mkdir *), Bash(rm -rf /tmp/atlas-tf-validate-*)
---

# MongoDB Atlas Terraform — Getting Started

You generate complete, ready-to-`terraform apply` Terraform configurations for MongoDB Atlas using the official Landing Zone Modules. Always follow this workflow in order.

---

## Step 0: Module Disclosure (Always First)

Before asking any questions or generating any code, show this message:

> I'll generate your Terraform configuration using the official [MongoDB Atlas Landing Zone Modules](https://registry.terraform.io/namespaces/terraform-mongodbatlas-modules), published on the Terraform Registry. These modules are officially maintained by MongoDB, embed best practices as defaults, and are the recommended way to manage Atlas infrastructure with Terraform.

---

## Step 1: Resolve Latest Versions

Fetch the latest versions before generating any HCL. Never hardcode versions — always resolve at generation time.

### 1a: Provider version (`mongodb/mongodbatlas`)

Try each source in order until one succeeds:

1. `mcp__plugin_terraform_terraform__get_latest_provider_version`: namespace `mongodb`, type `mongodbatlas`
2. `WebSearch`: query `mongodb/mongodbatlas terraform provider latest release site:github.com`
3. `Bash`: `gh api repos/mongodb/terraform-provider-mongodbatlas/releases/latest --jq '.tag_name'`

Strip the leading `v`. Use this as `PROVIDER_VERSION`. Constraint in HCL: `~> 2.0`.

### 1b: Project module version (`terraform-mongodbatlas-modules/project/mongodbatlas`)

Try each source in order:

1. `WebSearch`: query `terraform-mongodbatlas-modules/project/mongodbatlas terraform registry latest version`
2. `Bash`: `gh api repos/terraform-mongodbatlas-modules/terraform-mongodbatlas-project/releases/latest --jq '.tag_name'`

This is a Public Preview (v0) module. Use constraint `>= 0.1, < 1.0`.

### 1c: Cluster module version (`terraform-mongodbatlas-modules/cluster/mongodbatlas`)

Try each source in order:

1. `WebSearch`: query `terraform-mongodbatlas-modules/cluster/mongodbatlas terraform registry latest version`
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

Before rendering any file, substitute all placeholders using the user's answers:

| Placeholder | Replace with |
|---|---|
| `CLUSTER_NAME` | Cluster name from Question 5 (default: `my-cluster`) |
| `PROJECT_NAME` | Project name from Question 1 (new-project path only) |
| `PROVIDER` | Uppercase provider string from Question 2: `AWS`, `AZURE`, or `GCP` |
| `PROVIDER_VERSION` | Provider version resolved in Step 1a |

⚠️ **Important constraints from the cluster module:**
- Minimum instance size is **M10**. M0, M2, and M5 are not supported by this module.
- All clusters generated by this skill use a **sharded topology**. Set `shard_number = 0` on region blocks.
- Both modules are in **Public Preview (v0)**. Show this notice once: _"Note: both the project and cluster modules are in Public Preview. They are officially supported by MongoDB but upgrades from v0 → v1 may require manual migration steps."_

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
  required_version = ">= 1.9"
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

# Authentication — API Key (alternative to Service Account)
# Atlas UI → Access Manager → API Keys → Create API Key
variable "atlas_public_key" {
  description = "MongoDB Atlas API public key. Alternative to Service Account credentials."
  type        = string
  sensitive   = true
}

variable "atlas_private_key" {
  description = "MongoDB Atlas API private key. Alternative to Service Account credentials."
  type        = string
  sensitive   = true
}
```

Omit `variable "project_id"` entirely when the user is creating a new project. Omit `variable "org_id"` when using an existing project (it is not consumed in that path). Omit the API key variables if using a Service Account (and vice versa).

---

### File 3a: `main.tf` — creating a new project

```hcl
provider "mongodbatlas" {
  client_id     = var.atlas_client_id
  client_secret = var.atlas_client_secret
}

module "project" {
  source  = "terraform-mongodbatlas-modules/project/mongodbatlas"
  version = ">= 0.1, < 1.0"

  org_id = var.org_id
  name   = "PROJECT_NAME"
}

module "cluster" {
  source  = "terraform-mongodbatlas-modules/cluster/mongodbatlas"
  version = ">= 0.1, < 1.0"

  name         = "CLUSTER_NAME"
  project_id   = module.project.id
  cluster_type = "SHARDED"

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
  source  = "terraform-mongodbatlas-modules/cluster/mongodbatlas"
  version = ">= 0.1, < 1.0"

  name         = "CLUSTER_NAME"
  project_id   = local.project_id
  cluster_type = "SHARDED"

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
  value       = module.cluster.connection_strings.standard_srv
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
  value       = module.cluster.connection_strings.standard_srv
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

# API Key credentials (alternative to Service Account — use one or the other, not both)
# atlas_public_key  = "<replace-me>"
# atlas_private_key = "<replace-me>"
```

If MCP is connected, replace `<replace-me>` with real values for `org_id` and `project_id`.

---

## Step 4: Validate the Generated Configuration

Before presenting the files to the user, validate the HCL to catch syntax errors.

1. Create a temp directory:

   ```bash
   mkdir -p /tmp/atlas-tf-validate-tmp
   ```

2. Write versions.tf, variables.tf, main.tf, and outputs.tf to `/tmp/atlas-tf-validate-tmp/`. Omit `terraform.tfvars.example` — it is not valid HCL.

3. Initialize without backend (downloads providers and modules for schema validation — takes ~30 s):

   ```bash
   terraform -chdir=/tmp/atlas-tf-validate-tmp init -backend=false -no-color
   ```

4. Validate:

   ```bash
   terraform -chdir=/tmp/atlas-tf-validate-tmp validate -no-color
   ```

5. If output is `Success! The configuration is valid.` → proceed to Step 5.
   If validation fails → read the error, fix the affected generated file, and re-validate before presenting anything to the user.

6. Always clean up:

   ```bash
   rm -rf /tmp/atlas-tf-validate-tmp
   ```

---

## Step 5: Post-Generation Block

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
- All Landing Zone Modules: https://registry.terraform.io/namespaces/terraform-mongodbatlas-modules
- Cluster module:           https://registry.terraform.io/modules/terraform-mongodbatlas-modules/cluster/mongodbatlas/latest
- Project module:           https://registry.terraform.io/modules/terraform-mongodbatlas-modules/project/mongodbatlas/latest
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
