---
name: atlas-terraform-aws-harden
description: >-
  Use this skill when a user has an existing MongoDB Atlas cluster and wants to harden it
  with AWS security features using Terraform: AWS PrivateLink private endpoints, AWS KMS
  customer-managed encryption at rest (CMEK), IAM role for Cloud Provider Access, and backup
  export to Amazon S3. Triggers on: "add PrivateLink to my Atlas cluster on AWS", "enable
  CMEK encryption Atlas AWS", "harden Atlas cluster AWS Terraform", "Atlas AWS private
  endpoint Terraform", "backup export S3 Atlas Terraform", "Cloud Provider Access IAM role
  Atlas", "secure my Atlas cluster AWS". Also triggers when user already ran
  atlas-terraform-getting-started and now wants to add AWS security hardening.
  Does NOT trigger for: initial Atlas cluster creation (atlas-terraform-getting-started),
  Azure or GCP cloud integrations, Atlas Search, Vector Search, or general MongoDB querying.
allowed-tools: mcp__MongoDB__*, mcp__plugin_terraform_terraform__get_latest_provider_version, WebSearch, Bash(gh *), Bash(terraform *)
---

# MongoDB Atlas Terraform — AWS Hardening

You edit the files in a user's existing Terraform project to add AWS security hardening
to an existing Atlas cluster using the official
`terraform-mongodbatlas-modules/atlas-aws/mongodbatlas` Landing Zone module.
Follow this workflow in order.

---

## Step 0: Module Disclosure (Always First)

Before asking any questions, show:

> I'll add AWS hardening to your existing Terraform project using the official [MongoDB Atlas AWS
> Landing Zone Module](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/atlas-aws/mongodbatlas/latest),
> maintained by MongoDB. This adds AWS PrivateLink, KMS encryption at rest, IAM Cloud Provider
> Access, and S3 backup export by editing your existing Terraform files.
>
> **Note:** This module is in Public Preview (v0). It is officially supported by MongoDB but
> upgrades from v0 → v1 may require manual migration steps.

---

## Step 1: Resolve Latest Versions

Fetch versions before generating HCL. Never hardcode them.

### 1a: mongodbatlas provider

Try in order until one succeeds:
1. `mcp__plugin_terraform_terraform__get_latest_provider_version`: namespace `mongodb`, type `mongodbatlas`
2. `Bash`: `gh api repos/mongodb/terraform-provider-mongodbatlas/releases/latest --jq '.tag_name'`
3. `WebSearch`: query `mongodb/mongodbatlas terraform provider latest release site:github.com`

Strip the leading `v`. Constraint: `~> 2.0`.

### 1b: atlas-aws module

Try in order:
1. `Bash`: `gh api repos/terraform-mongodbatlas-modules/terraform-mongodbatlas-atlas-aws/releases/latest --jq '.tag_name'`
2. `WebSearch` (fallback): query `terraform-mongodbatlas-modules/atlas-aws/mongodbatlas terraform registry latest version`

Constraint: `~> 0.3`. Public Preview module.

### 1c: AWS provider

Use constraint `~> 6.0`. No version resolution needed.

### 1d: Inspect atlas-aws module interface

```bash
gh api repos/terraform-mongodbatlas-modules/terraform-mongodbatlas-atlas-aws/contents/variables.tf --jq '.content' | base64 -d
```

Record every declared variable name. In Step 3, pass **only** arguments whose names appear in this file. If the command fails, proceed with the template but flag to the user that the module interface could not be verified.

---

## Step 2: Gather User Inputs

Ask questions in sequence. Stop after each answer.

### Q0 — Project Path

> "What is the path to your existing Terraform project? (press Enter for current directory `.`)"

Store as `USER_PROJECT_PATH`. Default to `.` if not provided.

### Q1 — Atlas Project ID

> "What is your Atlas Project ID?"

If MCP is connected: call `mcp__MongoDB__atlas-list-projects` and present the list.
Store as `USER_PROJECT_ID`.

### Q2 — Cluster Name

> "What is the name of your existing Atlas cluster?"

If MCP is connected: call `mcp__MongoDB__atlas-list-clusters` with the project ID and present the list.
Store as `USER_CLUSTER_NAME`.

### Q3 — Region

> "What AWS region is your Atlas cluster in? (e.g. `us-east-1`, `eu-west-1`)"

Store as `USER_AWS_REGION`.

### Q4 — AWS Networking

> "Do you have existing AWS subnets for PrivateLink, or should I create a new VPC and subnets?"

**BYO:** "What are your existing subnet IDs? (comma-separated, e.g. subnet-abc123,subnet-def456)"
→ Store as list `USER_SUBNET_IDS`. Set `NETWORKING = byo`.

**Create:** "What CIDR block for the new VPC? (e.g. 10.0.0.0/16)" and "Which availability zones? (e.g. us-east-1a,us-east-1b)"
→ Store as `USER_VPC_CIDR` and `USER_AZ_LIST`. Set `NETWORKING = create`.

### Q5 — KMS Encryption

> "Do you have an existing AWS KMS key for encryption at rest, or should the module create one?"

**BYO:** "KMS key ARN?" → store as `USER_KMS_ARN`. Set `KMS = byo`.
**Create:** Set `KMS = create`.

### Q6 — S3 Backup Export

> "Do you have an existing S3 bucket for Atlas backup export, or should the module create one?"

**BYO:** "S3 bucket name?" → store as `USER_S3_BUCKET`. Set `S3 = byo`.
**Create:** Set `S3 = create`.

---

## Step 3: Edit Existing Project Files

Read each file before editing it. Substitute all USER_* values before applying edits.

---

### Edit 1: `versions.tf`

Inside the existing `required_providers { }` block, add the AWS provider after the last existing entry:

```hcl
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
```

If the `mongodbatlas` entry has a `# resolved:` comment, update it to `# resolved: MONGODBATLAS_VERSION`.

---

### Edit 2: `variables.tf`

Read the existing file. Append each variable below **only if it is not already declared**:

Always append if not present:
```hcl
variable "aws_region" {
  description = "AWS provider region (e.g. us-east-1)."
  type        = string
}
```

If `project_id` is not declared:
```hcl
variable "project_id" {
  description = "Atlas Project ID."
  type        = string
}
```

If `cluster_name` is not declared and present in the module interface (Step 1d):
```hcl
variable "cluster_name" {
  description = "Name of the existing Atlas cluster to harden."
  type        = string
}
```

**If `NETWORKING = byo`:**
```hcl
variable "subnet_ids" {
  description = "Existing AWS subnet IDs for Atlas PrivateLink."
  type        = list(string)
}
```

**If `NETWORKING = create`:**
```hcl
variable "vpc_cidr" {
  description = "CIDR block for the new VPC (e.g. 10.0.0.0/16)."
  type        = string
}

variable "availability_zones" {
  description = "AWS availability zones for subnets."
  type        = list(string)
}
```

**If `KMS = byo`:**
```hcl
variable "kms_key_arn" {
  description = "Existing AWS KMS key ARN for Atlas encryption at rest."
  type        = string
}
```

**If `S3 = byo`:**
```hcl
variable "s3_bucket_name" {
  description = "Existing S3 bucket name for Atlas backup export."
  type        = string
}
```

---

### Edit 3: `main.tf`

Append to the end of the file. Do **not** add a second `provider "mongodbatlas"` block — it already exists.

```hcl
provider "aws" {
  region = var.aws_region
}
```

**If `NETWORKING = create`**, also append:

```hcl
resource "aws_vpc" "atlas" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "atlas-harden-vpc" }
}

resource "aws_subnet" "atlas" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.atlas.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = { Name = "atlas-harden-subnet-${count.index}" }
}
```

Then append the module block (apply combination rules):

```hcl
module "atlas_aws" {
  source  = "terraform-mongodbatlas-modules/atlas-aws/mongodbatlas"
  version = "~> 0.3"

  project_id = var.project_id

  privatelink_endpoints = [
    {
      region     = var.aws_region
      subnet_ids = SUBNET_IDS_PLACEHOLDER
      security_group = {
        inbound_cidr_blocks = CIDR_PLACEHOLDER
      }
    }
  ]

  # Creates an IAM role for Atlas Cloud Provider Access (KMS + S3 permissions) with module defaults.
  cloud_provider_access = {}

  encryption    = KMS_PLACEHOLDER
  backup_export = S3_PLACEHOLDER
}
```

Also include `cluster_name = var.cluster_name` inside the module block if `cluster_name` appeared in the fetched module interface (Step 1d).

⚠️ **Combination rules:**

| Choice | Placeholder | Substitute with |
|---|---|---|
| NETWORKING = byo | `SUBNET_IDS_PLACEHOLDER` | `var.subnet_ids` |
| NETWORKING = create | `SUBNET_IDS_PLACEHOLDER` | `aws_subnet.atlas[*].id` |
| NETWORKING = byo | `CIDR_PLACEHOLDER` | `[]` |
| NETWORKING = create | `CIDR_PLACEHOLDER` | `[var.vpc_cidr]` |
| KMS = byo | `KMS_PLACEHOLDER` | `{ enabled = true, kms_key_arn = var.kms_key_arn }` |
| KMS = create | `KMS_PLACEHOLDER` | `{ enabled = true, create_kms_key = { enabled = true } }` |
| S3 = byo | `S3_PLACEHOLDER` | `{ enabled = true, bucket_name = var.s3_bucket_name }` |
| S3 = create | `S3_PLACEHOLDER` | `{ enabled = true, create_s3_bucket = { enabled = true } }` |

---

### Edit 4: `outputs.tf`

Append to the end of the file:

```hcl
output "privatelink_endpoint" {
  description = "Atlas PrivateLink endpoint details."
  value       = module.atlas_aws.privatelink
}

output "encryption_at_rest_provider" {
  description = "Atlas encryption at rest provider configuration."
  value       = module.atlas_aws.encryption_at_rest_provider
}

output "cloud_provider_access_role_id" {
  description = "Atlas Cloud Provider Access IAM role ID."
  value       = module.atlas_aws.role_id
}

output "backup_export_bucket_id" {
  description = "Atlas backup export bucket ID."
  value       = module.atlas_aws.export_bucket_id
}
```

If `NETWORKING = create`, also append:

```hcl
output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.atlas.id
}

output "subnet_ids" {
  description = "IDs of the created subnets."
  value       = aws_subnet.atlas[*].id
}
```

---

### Edit 5: `terraform.tfvars.example`

Append to the end of `terraform.tfvars.example` (or `terraform.tfvars` if no example file exists).
Replace all USER_* with actual values.

```hcl
# --- AWS Hardening ---
aws_region = "USER_AWS_REGION"
```

If `NETWORKING = byo`: append `subnet_ids = ["USER_SUBNET_IDS"]`
If `NETWORKING = create`: append `vpc_cidr = "USER_VPC_CIDR"` and `availability_zones = ["USER_AZ_LIST"]`
If `KMS = byo`: append `kms_key_arn = "USER_KMS_ARN"`
If `S3 = byo`: append `s3_bucket_name = "USER_S3_BUCKET"`

---

## Step 4: Validate

1. Initialize (downloads atlas-aws module and AWS provider):

   ```bash
   terraform -chdir=USER_PROJECT_PATH init -backend=false -no-color
   ```

2. Apply Terraform < 1.12 compatibility patches for `atlas-aws` v0.3.x:

   ```bash
   terraform version -no-color | head -1
   ```

   If below 1.12, apply using the Edit tool:

   **Patch A** — `USER_PROJECT_PATH/.terraform/modules/atlas_aws/locals.tf`:
   - old: `if ep.service_region != null && lower(replace(ep.service_region, "_", "-")) == k`
   - new: `if ep.service_region != null && try(lower(replace(ep.service_region, "_", "-")), "") == k`

   **Patch B** — `USER_PROJECT_PATH/.terraform/modules/atlas_aws/modules/cloud_provider_access/variables.tf`:
   - old: `condition     = var.iam_role_name == null || length(var.iam_role_name) <= 64`
   - new: `condition     = var.iam_role_name == null || try(length(var.iam_role_name), 0) <= 64`

   ⚠️ Re-apply these patches after `terraform init -upgrade`. Fixed natively in Terraform ≥ 1.12.

3. Validate:

   ```bash
   terraform -chdir=USER_PROJECT_PATH validate -no-color
   ```

4. If `Success! The configuration is valid.` → proceed to Step 5.
   If validation fails → fix the error and re-validate. After two failed attempts, present the edits with a note that validation could not be completed.

---

## Step 5: Post-Generation Block

After all edits are complete, always append:

```
## Next Steps

1. Update terraform.tfvars with the new AWS hardening values.
   Ensure terraform.tfvars is in your .gitignore:
     terraform.tfvars
     .terraform/
     *.tfstate
     *.tfstate.backup

2. Initialize Terraform (downloads the atlas-aws module and AWS provider):
   terraform init

3. Review what will be created:
   terraform plan

4. Apply:
   terraform apply

## What This Adds

| Resource | Details |
|---|---|
| AWS PrivateLink endpoint | Private connectivity from your VPC to Atlas — no traffic over public internet |
| AWS KMS encryption at rest | All Atlas data encrypted with your KMS key |
| IAM role (Cloud Provider Access) | Atlas assumes this role to access KMS and S3 |
| S3 backup export | Atlas snapshots automatically exported to S3 |

## Useful Links

- atlas-aws module:     https://registry.terraform.io/modules/terraform-mongodbatlas-modules/atlas-aws/mongodbatlas/latest
- Atlas PrivateLink:   https://www.mongodb.com/docs/atlas/security-private-endpoint/
- Atlas CMEK:          https://www.mongodb.com/docs/atlas/security-kms-encryption/
- Atlas backup export: https://www.mongodb.com/docs/atlas/backup/cloud-backup/export/
- Cloud Provider Access: https://www.mongodb.com/docs/atlas/security/set-up-unified-aws-access/
```

---

## Safety Rules

- **Never hardcode credentials.** All sensitive values must be declared as `sensitive = true` variables.
- **No write operations without confirmation.** If MCP is connected, only read non-sensitive data. Never call create/update/delete MCP tools.
- **Do not recreate the existing cluster.** This only adds hardening resources.
- **Remind about `.gitignore`.** Always include it in the Next Steps block.

---

## Out of Scope

| Request | Resource |
|---|---|
| Creating a new Atlas cluster from scratch | `atlas-terraform-getting-started` skill |
| Azure PrivateLink, Key Vault, or Blob Storage integration | `atlas-terraform-azure-harden` skill |
| GCP Private Service Connect or Cloud KMS integration | `atlas-terraform-gcp-harden` skill |
| Atlas Search / Vector Search index management | Atlas Search Terraform resource docs |
| Importing existing Terraform state | `terraform import` + provider resource docs |
| General Terraform errors unrelated to Atlas | HashiCorp Terraform docs |
