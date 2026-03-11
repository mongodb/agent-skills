---
name: mongodb-mcp-setup
description: Guide users through configuring key MongoDB MCP server options. Use this skill when a user has the MongoDB MCP server installed but hasn't configured the required environment variables, or when they ask about connecting to MongoDB/Atlas and don't have the credentials set up.
---

# MongoDB MCP Server Setup

This skill guides users through configuring the MongoDB MCP server for use with an agentic client.

## Overview

The MongoDB MCP server requires authentication. Users have three options:

1. **Connection String** (Option A): Direct connection to a specific cluster
   - Quick setup for single cluster
   - Requires `MDB_MCP_CONNECTION_STRING` environment variable

2. **Service Account Credentials** (Option B): MongoDB Atlas Admin API access
   - **Recommended for Atlas users** - simplifies authentication and data access
   - Access to Atlas Admin API and dynamic cluster connection via `atlas-connect-cluster`
   - No manual DB user credential management
   - Requires `MDB_MCP_API_CLIENT_ID` and `MDB_MCP_API_CLIENT_SECRET` environment variables

3. **Atlas Local** (Option C): Local development with Docker
   - **Best for local testing** - zero configuration required
   - Runs Atlas locally in Docker, requires Docker installed
   - No credentials or cloud cluster access

**Important**: Code snippets use bash/zsh syntax. For other shells (PowerShell, fish, etc.), adjust commands to the user's shell.

## Execution Modes

This skill supports two execution modes:

1. **Interactive Mode** (preferred): Directly modifies the user's shell profile when Bash access is available
2. **Documentation Mode** (fallback): Creates example configuration files and instructions when Bash access is restricted

Always attempt Interactive Mode first. If Bash permission is denied, automatically switch to Documentation Mode without asking the user.

## Step 1: Check Existing Configuration

Before starting the setup, check if the user already has the required environment variables configured.

**Try to run** this command to check for existing configuration:

```bash
env | grep -E "MDB_MCP_(CONNECTION_STRING|API_CLIENT_ID|API_CLIENT_SECRET|READ_ONLY)"
```

**Interpretation (if Bash succeeded):**

- If `MDB_MCP_CONNECTION_STRING` is set, the user has connection string auth configured
- If both `MDB_MCP_API_CLIENT_ID` and `MDB_MCP_API_CLIENT_SECRET` are set, the user has service account auth configured. If only one of these is set, the configuration is incomplete and treat it as if neither is set.
- If `MDB_MCP_READ_ONLY` is set to `true`, the user has read-only mode enabled

**Partial Configuration Handling:**

- If user wants to add read-only mode to existing setup (has auth but no `MDB_MCP_READ_ONLY`), skip to Step 4
- If user wants to switch authentication methods, explain they should remove the old variables from their shell profile first, then proceed with Steps 2-5
- If user wants to update existing credentials, offer to update the configuration in their shell profile

**Important**: If the user is asking to perform an Atlas Admin API action (like managing clusters, creating database users, getting performance advisor recommendations) but only has `MDB_MCP_CONNECTION_STRING` configured, explain that they need service account credentials for Atlas Admin API access and offer to help them set it up.

## Step 2: Present Configuration Options

If no valid configuration exists, present the options:

**Connection String (Option A)** - Best for:

- Single cluster access
- Existing database credentials
- Self-hosted MongoDB or no Atlas Admin API needs

**Service Account Credentials (Option B)** - Best for:

- MongoDB Atlas users (recommended)
- Multi-cluster switching
- Atlas Admin API access (cluster management, user creation, performance monitoring)

**Atlas Local (Option C)** - Best for:

- Local development/testing without cloud setup
- Fastest setup with Docker, no credentials required

Use the agent's interactive question capability to let them choose.

## Step 3a: Connection String Setup

If the user chooses Option A:

### 3a.1: Obtain Connection String

Ask the user for their MongoDB connection string. Expected formats:

- `mongodb://username:password@host:port/database`
- `mongodb+srv://username:password@cluster.mongodb.net/database`
- `mongodb://host:port` (for local instances)

### 3a.2: Validate Connection String

Validate the connection string:

- Must start with `mongodb://` or `mongodb+srv://`
- Should contain host information
- Warn if invalid, but allow user to proceed

Proceed to Step 4 (Determine Read-Only Access).

## Step 3b: Service Account Setup

If the user chooses Option B:

### 3b.1: Provide Setup Instructions

Direct the user to create a MongoDB Atlas Service Account following the official documentation:

**MongoDB MCP Server Prerequisites**: https://www.mongodb.com/docs/mcp-server/prerequisites/

Offer to open this URL in their browser.

### 3b.2: Key Steps Summary

Remind them of the key steps:

1. **Navigate to MongoDB Atlas** - cloud.mongodb.com
2. **Create Service Account** - Access Manager → Service Accounts → Create Service Account
3. **Set Permissions** - Grant Organization Member or Project Owner (see docs for exact mappings)
4. **Generate Credentials** - Create Client ID and Secret (secret visible only once!)
5. **Save Credentials** - Keep both values safe

**⚠️ CRITICAL: API Access List Configuration**

The user MUST add their IP address to the service account's API Access List before using it, or all Atlas Admin API operations will fail.

To configure:

1. On the service account details page, find "API Access List"
2. Click "Add Access List Entry"
3. Add current IP or 0.0.0.0/0 for testing (not for production)
4. Save changes

This is more secure than global Network Access settings as it only affects API access, not database connections.

### 3b.3: Collect Credentials

Once Atlas setup is complete, ask for Client ID and Client Secret using the agent's user-input capability. Ensure values are not empty.

Proceed to Step 4 (Determine Read-Only Access).

## Step 3c: Atlas Local Setup

If the user chooses Option C:

### 3c.1: Check Docker Installation

Verify Docker is installed:

```bash
docker info
```

If not installed, direct them to: https://www.docker.com/get-started

### 3c.2: Confirm Setup Complete

Inform the user they're all set! Atlas Local requires no credentials:

- Create deployments using `atlas-local-create-deployment`
- List deployments using `atlas-local-list-deployments`
- All operations work out of the box with Docker

**Skip Steps 4 and 5** (no configuration needed) and proceed to Step 6 (Next Steps).

## Step 4: Determine Read-Only vs Read-Write Access

**Only applies to Options A and B. Skip to Step 6 for Option C.**

Ask whether they want read-only or read-write access:

- **Read-Write** (default): Full data access, modifications allowed
  - Best for: Development, testing, administrative tasks

- **Read-Only**: Data reads only, no modifications
  - Best for: Production data safety, reporting, compliance

Use the agent's interactive question capability.

**If read-only**: Set `MDB_MCP_READ_ONLY=true` in Step 5.
**If read-write**: Do NOT set `MDB_MCP_READ_ONLY` (defaults to read-write).

Proceed to Step 5 (Update Shell Profile).

## Step 5: Update Shell Profile

Now that you have the environment variable(s) to configure, update the user's shell profile.

**Try Interactive Mode first (5a). If Bash is denied at any point, switch to Documentation Mode (5b).**

### Step 5a: Interactive Mode (Automatic Configuration)

Use this mode when you have Bash access.

#### 5a.1: Detect Shell and Profile

**Try to detect** the user's current shell:

```bash
echo $SHELL
```

**If Bash is denied:** Switch immediately to Documentation Mode (Step 5b).

Based on the shell, determine the appropriate profile file to update from training data. If necessary, refer to the shell docs.

#### 5a.2: Add Environment Variables

Check if variables already exist in the profile file. If so, replace rather than duplicate.

Add the environment variables with a descriptive comment:

For Connection String (Option A):

```bash
# MongoDB MCP Server Configuration
export MDB_MCP_CONNECTION_STRING="<value>"
```

For Service Account (Option B):

```bash
# MongoDB MCP Server Configuration (Atlas Service Account)
export MDB_MCP_API_CLIENT_ID="<value>"
export MDB_MCP_API_CLIENT_SECRET="<value>"
```

**If the user chose read-only access** (Step 4), add this additional line:

```bash
export MDB_MCP_READ_ONLY="true"
```

Use file-editing capabilities to append to the profile file. If the file doesn't exist, create it. Append to the end to avoid disrupting existing configurations.

#### 5a.3: Set Permissions

Set restrictive permissions on the profile file:

```bash
chmod 600 ~/.zshrc
```

#### 5a.4: Verify Configuration

Source the profile and verify:

```bash
source ~/.zshrc
env | grep MDB_MCP
```

Confirm the expected environment variables appear.

Proceed to Step 6 (Next Steps).

### Step 5b: Documentation Mode (Manual Configuration)

Use this mode when Bash access is restricted or denied.

**CRITICAL: Create ONLY ONE file called `SETUP.md`. Do NOT create additional files like README.md, summary.md, session_log.txt, resolution_summary.md, etc. Just SETUP.md.**

#### 5b.1: Create ONE Setup File

Create a single file called `SETUP.md` with concise, actionable instructions. Keep it under 100 lines.

**Security rule:** Never write real credentials to `SETUP.md`. Use placeholders only.

Adapt instructions to the user's shell if known (PowerShell, bash, etc.). If unknown, default to bash on Unix, PowerShell on Windows, and include a shell reference section for common shells at the end.

````markdown
# MongoDB MCP Setup

## What to do

Add this to your shell profile (e.g., `~/.zshrc`/`~/.bashrc`/`$PROFILE`):

For Connection String (Option A):

```bash
export MDB_MCP_CONNECTION_STRING="<paste-your-connection-string-here>"
```

For Service Account (Option B):

```bash
export MDB_MCP_API_CLIENT_ID="<paste-your-client-id-here>"
export MDB_MCP_API_CLIENT_SECRET="<paste-your-client-secret-here>"
```

**If you chose read-only access**, also add:

```bash
export MDB_MCP_READ_ONLY="true"
```

## Steps

1. Open your shell profile: `code ~/.zshrc` (or vim/nano)
2. Paste the export line(s) at the end
3. Save the file
4. Restart the agentic client (fully quit and reopen) - the environment variables will be loaded when the client starts
5. Verify: `env | grep MDB_MCP` in a new terminal to confirm the variables are set

## Troubleshooting

If it doesn't work after restart:

- Make sure you used the exact variable names (MDB_MCP_CONNECTION_STRING, MDB_MCP_API_CLIENT_ID/SECRET, or MDB_MCP_READ_ONLY)
- Check the variable is set: `env | grep MDB_MCP` or equivalent for your shell
- Verify the client was fully restarted, not just reloaded

## Security reminder

- Never commit credentials to git
- Keep secrets in your shell profile only (not in project files)
````

**Keep it direct and scannable.** Don't create separate files for "overview", "architecture", "workflow guide", etc. One file with clear steps.

#### 5b.2: Explain to User

Tell the user:

- "I've created SETUP.md with configuration instructions"
- "Add the environment variable(s) to your shell profile, then restart the client"
- Point them to SETUP.md for details

Proceed to Step 6 (Next Steps).

## Step 6: Next Steps

### For Options A & B (Connection String / Service Account):

1. **Restart the client**: Fully restart (not reload) for environment variables to be picked up.

2. **Verify MCP Server**: After restart, test by performing MongoDB operations.

3. **Using the Tools**:
   - Option A: Direct database access tools available
   - Option B: Additionally has Atlas Admin API tools and `atlas-connect-cluster`
   - **Important (Option B)**: Ensure IP is added to service account's API Access List or all API operations will fail

### For Option C (Atlas Local):

1. **Ready to use**: No restart or configuration needed!

2. **Next steps**:
   - Create deployments: `atlas-local-create-deployment`
   - List deployments: `atlas-local-list-deployments`
   - Use standard database operations once connected

## Important Notes

- **Security**: Never commit credentials to version control. Set shell profile permissions to 600.

- **Troubleshooting** if MCP server doesn't work after restart:
  - Verify variables: `env | grep MDB_MCP`
  - Confirm full restart (not reload)
  - Test credentials directly (mongosh for connection string, API call for service account)
  - For read-only mode, verify `MDB_MCP_READ_ONLY=true`
  - Check MCP server logs for errors

## Error Handling

Common issues:

- **Bash permission denied**: Automatically switch to Documentation Mode (Step 5b)
- **Invalid connection string**: Provide correct format guidance
- **Profile file doesn't exist**: Create it (Interactive) or explain where to create it (Documentation)
- **Permission denied on profile**: Fix permissions (Interactive) or include instructions (Documentation)
- **Variables not loading**: Check shell type and profile path
- **Invalid service account credentials**: Direct to Atlas to verify/regenerate
