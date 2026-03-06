---
name: mongodb-mcp-setup
description: Guide users through configuring the MongoDB MCP server. Use this skill when a user has the MongoDB MCP server installed but hasn't configured the required environment variables, or when they ask about connecting to MongoDB/Atlas and don't have the credentials set up. Also trigger immediately after the user installs the MongoDB plugin. This skill helps users choose between direct database connection (connection string) or Atlas Admin API access (service account credentials), then walks them through the setup process.
---

# MongoDB MCP Server Setup

This skill guides users through configuring the MongoDB MCP server for use with an agentic client.

## Overview

The MongoDB MCP server requires authentication credentials to work. Users have three options:

1. **Connection String** (Option A): Direct connection to a specific MongoDB cluster
   - Quick setup for single cluster access
   - Requires manual connection string with database credentials
   - Requires `MDB_MCP_CONNECTION_STRING` environment variable

2. **Service Account Credentials** (Option B): MongoDB Atlas Admin API access
   - **Recommended for Atlas users** - manages authentication internally and simplifies data access
   - Access to Atlas Admin API (limited by service account permissions)
   - Ability to connect to any cluster dynamically using the `atlas-connect-cluster` tool
   - No need to manually create DB Users or manage their credentials
   - Requires both `MDB_MCP_API_CLIENT_ID` and `MDB_MCP_API_CLIENT_SECRET` environment variables

3. **Atlas Local** (Option C): Local development with Docker
   - **Best for local development and testing** - no configuration required
   - Runs an Atlas cluster locally in Docker
   - No environment variables or credentials needed
   - Requires Docker to be installed
   - No access to cloud clusters, Admin API

## Execution Modes

This skill supports two execution modes:

1. **Interactive Mode** (preferred): Directly modifies the user's shell profile when Bash access is available
2. **Documentation Mode** (fallback): Creates example configuration files and instructions when Bash access is restricted

Always attempt Interactive Mode first. If Bash permission is denied, automatically switch to Documentation Mode without asking the user.

## Step 1: Check Existing Configuration

Before starting the setup, check if the user already has the required environment variables configured.

**Try to run** this command to check for existing configuration:

```bash
env | grep -E "MDB_MCP_(CONNECTION_STRING|API_CLIENT_ID|API_CLIENT_SECRET)"
```

**If Bash access is denied:** Skip to Documentation Mode (see Step 4b). You can't check existing configuration interactively, so proceed with creating documentation files.

**Interpretation (if Bash succeeded):**
- If `MDB_MCP_CONNECTION_STRING` is set, the user has connection string auth configured
- If both `MDB_MCP_API_CLIENT_ID` and `MDB_MCP_API_CLIENT_SECRET` are set, the user has service account auth configured
- If the user has either valid configuration, exit gracefully unless they explicitly need Atlas Admin API access but only have the connection string configured

**Important**: If the user is asking to perform an Atlas Admin API action (like managing clusters, creating database users, getting performance advisor recommendations) but only has `MDB_MCP_CONNECTION_STRING` configured, explain that they need service account credentials for Atlas Admin API access and offer to help them set it up.

## Step 2: Present Configuration Options

If no valid configuration exists, present the options to the user and help them understand which one suits their needs:

**Connection String (Option A)** is best when:
- They're working with a single, specific cluster
- They already have database credentials (username/password)
- They don't need Atlas Admin API access
- They're working with self-hosted MongoDB

**Service Account Credentials (Option B)** is best when:
- They're using MongoDB Atlas (recommended approach)
- They want to switch between multiple clusters
- They need Atlas Admin API access (cluster management, user creation, performance monitoring)

**Atlas Local (Option C)** is best when:
- They want to develop and test locally without cloud setup
- They have Docker installed
- They don't need real Atlas resources (just a local MongoDB instance)
- They want the fastest setup with no credentials required

Use the AskUserQuestion tool to let them choose.

## Step 3a: Connection String Setup

If the user chooses Option A:

### 3a.1: Obtain Connection String

Ask the user for their MongoDB connection string. It should look like one of these formats:
- `mongodb://username:password@host:port/database`
- `mongodb+srv://username:password@cluster.mongodb.net/database`
- `mongodb://host:port` (for local instances)

### 3a.2: Validate Connection String

Perform basic validation to ensure the connection string follows MongoDB URI format:
- Must start with `mongodb://` or `mongodb+srv://`
- Should contain host information
- Warn if it doesn't look valid, but allow the user to proceed if they insist

### 3a.3: Update Shell Profile

Proceed to Step 4 (Update Shell Profile) with the environment variable:
```bash
export MDB_MCP_CONNECTION_STRING="<user-provided-connection-string>"
```

## Step 3b: Service Account Setup

If the user chooses Option B:

### 3b.1: Explain the Process

Explain that they need to create a MongoDB Atlas Service Account to get API credentials. This involves:
1. Logging into MongoDB Atlas
2. Creating a service account (or using an existing one)
3. Getting the Client ID and Client Secret
4. Configuring appropriate permissions

### 3b.2: Provide Setup Instructions

Tell the user they need to follow the official MongoDB documentation to create service account credentials. Provide the link:

**MongoDB MCP Server Prerequisites**: https://www.mongodb.com/docs/mcp-server/prerequisites/

Offer to open this URL in their browser to make it easier.

### 3b.3: Guide Through Key Steps

While they work through the documentation, remind them of the key steps:

1. **Navigate to MongoDB Atlas** - Go to cloud.mongodb.com and sign in
2. **Access Organization Settings** - Find the organization where they want to create the service account
3. **Create Service Account** - Go to Access Manager → Service Accounts → Create Service Account
4. **Set Permissions** - Grant appropriate permissions (they'll need at least Organization Member or Project Owner for most operations)
5. **Generate Credentials** - Create the Client ID and Secret (they can only see the secret once!)
6. **Save Credentials** - Keep the Client ID and Secret somewhere safe

**⚠️ IMPORTANT: API Access List Configuration**

Before using the service account, the user MUST add their IP address to the service account's API Access List. Without this:
- All Atlas Admin API operations will fail with authentication errors
- The service account credentials won't work even if they're valid

To configure the API Access List (recommended - more secure):
1. After creating the service account, stay on the service account details page
2. Find the "API Access List" section
3. Click "Add Access List Entry"
4. Either add their current IP address or use 0.0.0.0/0 for testing (not recommended for production)
5. Save the changes

This approach is more secure than using the global Network Access settings because it only affects this specific service account's API access, not database connections.

Without proper API Access List configuration, they'll encounter errors when trying to use Atlas Admin API tools.

### 3b.4: Collect Credentials

Once they've completed the Atlas setup, ask them to provide:
- Client ID
- Client Secret

Use the AskUserQuestion tool with appropriate input fields for these credentials.

### 3b.5: Update Shell Profile

Proceed to Step 4 (Update Shell Profile) with both environment variables:
```bash
export MDB_MCP_API_CLIENT_ID="<user-provided-client-id>"
export MDB_MCP_API_CLIENT_SECRET="<user-provided-client-secret>"
```

## Step 3c: Atlas Local Setup

If the user chooses Option C:

### 3c.1: Check Docker Installation

Verify that Docker is installed and running:

```bash
docker --version
```

If Docker is not installed, inform the user they need to install Docker Desktop (or Docker Engine for Linux) before using Atlas Local. Provide the link: https://www.docker.com/get-started

### 3c.2: Confirm Setup Complete

Inform the user that they're all set! No environment variables or credentials are needed for Atlas Local:
- The MongoDB MCP server is already configured to work with Atlas Local
- They can create a local deployment using the `atlas-local-create-deployment` tool
- Or list existing deployments they may have created with the Atlas CLI using `atlas-local-list-deployments`
- All Atlas Local operations work out of the box with Docker installed

After confirming Docker is available, **skip Step 4** (no shell profile configuration needed) and proceed directly to Step 5 (Next Steps).

## Step 4: Update Shell Profile

Now that you have the environment variable(s) to configure, update the user's shell profile.

**Note:** This step only applies to Option A (Connection String) and Option B (Service Account). If the user chose Option C (Atlas Local), skip this step.

**Try Interactive Mode first (4a). If Bash is denied at any point, switch to Documentation Mode (4b).**

### Step 4a: Interactive Mode (Automatic Configuration)

Use this mode when you have Bash access.

#### 4a.1: Detect Shell and Profile

**Try to detect** the user's current shell:
```bash
echo $SHELL
```

**If Bash is denied:** Switch immediately to Documentation Mode (Step 4b).

Based on the shell, determine the appropriate profile file to update:

| Shell | Profile File |
|-------|-------------|
| `/bin/zsh` or `/usr/bin/zsh` | `~/.zshrc` |
| `/bin/bash` or `/usr/bin/bash` | `~/.bashrc` or `~/.bash_profile` (check which exists, prefer `~/.bashrc`) |
| `/bin/fish` or `/usr/bin/fish` | `~/.config/fish/config.fish` |
| Others | `~/.profile` (fallback) |

**For Windows users** (if you detect Windows OS):
- PowerShell: Use the PowerShell profile (check `$PROFILE` variable)
- Inform them they may need to create the profile if it doesn't exist

#### 4a.2: Check for Existing Configuration

Before adding new environment variables, check if these variables are already defined in the profile file. If they are, offer to update them rather than adding duplicates.

#### 4a.3: Add Environment Variables

Add the environment variables to the appropriate profile file. Add a comment to make it clear what these are for:

```bash
# MongoDB MCP Server Configuration
export MDB_MCP_CONNECTION_STRING="<value>"
```

or

```bash
# MongoDB MCP Server Configuration (Atlas Service Account)
export MDB_MCP_API_CLIENT_ID="<value>"
export MDB_MCP_API_CLIENT_SECRET="<value>"
```

Use the Edit tool to append these lines to the profile file. If the file doesn't exist, create it with Write tool.

#### 4a.4: Set Permissions

Ensure the profile file has appropriate permissions (especially important for files containing secrets):
```bash
chmod 600 ~/.zshrc  # or whatever profile file was used
```

After completing Interactive Mode, proceed to Step 5 (Apply Configuration).

### Step 4b: Documentation Mode (Manual Configuration)

Use this mode when Bash access is restricted or denied.

**CRITICAL: Create ONLY ONE file called `SETUP.md`. Do NOT create additional files like README.md, summary.md, session_log.txt, resolution_summary.md, etc. Just SETUP.md.**

#### 4b.1: Create ONE Setup File

Create a single file called `SETUP.md` with concise, actionable instructions. Keep it under 100 lines. Structure:

```markdown
# MongoDB MCP Setup

## What to do

Add this to your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
export MDB_MCP_CONNECTION_STRING="<their-exact-value>"
```

(or for service account, include both API credentials)

## Steps

1. Open your shell profile: `nano ~/.zshrc` (or vim/code)
2. Paste the export line(s) at the end
3. Save the file
4. Restart the agentic client (fully quit and reopen) - the environment variables will be loaded when the client starts
5. Verify: `env | grep MDB_MCP` in a new terminal to confirm the variables are set

## Finding your shell profile

- Run `echo $SHELL` to check your shell
- zsh → `~/.zshrc`
- bash → `~/.bashrc` or `~/.bash_profile`

## Troubleshooting

If it doesn't work after restart:
- Make sure you used the exact variable name (MDB_MCP_CONNECTION_STRING or MDB_MCP_API_CLIENT_ID/SECRET)
- Check the variable is set: `env | grep MDB_MCP`
- Verify the client was fully restarted, not just reloaded

**Keep it direct and scannable.** Don't create separate files for "overview", "architecture", "workflow guide", etc. One file with clear steps.

#### 4b.2: Explain to User (Brief Summary)

Tell the user in your response:
- "I've created SETUP.md with instructions to configure the MongoDB MCP server"
- "The key step: add this line to your ~/.zshrc file: `export MDB_MCP_CONNECTION_STRING='<value>'`"
- "Then source the file and restart the client"
- Point them to the SETUP.md file for full details

**Do not** create multiple README files, architecture documents, comparison guides, or verbose explanations. Keep the user-facing communication concise and the documentation minimal.

After completing Documentation Mode, proceed to Step 5 (Next Steps).

After completing Interactive Mode, proceed to Step 5 (Next Steps).

## Step 5: Next Steps

Inform the user about what to do next based on their chosen option:

### For Option A (Connection String) and Option B (Service Account):

1. **Restart the client**: The MCP server runs when the agentic client starts, so they need to fully restart it (not just reload the window) for the new environment variables to be picked up. The shell profile will be sourced when they open a new terminal or when the client starts in a new process.

2. **Verify MCP Server**: After restarting, they can verify the MongoDB MCP server is working by asking the agent to connect to MongoDB or perform MongoDB operations.

3. **Using the Tools**:
   - If they configured a connection string (Option A), they'll have direct database access tools available
   - If they configured service account credentials (Option B), they'll additionally have:
     - Atlas Admin API tools
     - The `atlas-connect-cluster` tool to switch between clusters dynamically
   - **Important for service account users**: Make sure their IP address is added to the service account's API Access List (found in the service account settings), otherwise all API operations will fail

### For Option C (Atlas Local):

1. **Ready to use**: No restart or configuration needed - the MCP server works with Atlas Local out of the box!

2. **Next steps**: They can now:
   - Create a local deployment with `atlas-local-create-deployment`
   - List existing deployments with `atlas-local-list-deployments`
   - Once connected to a deployment, use all standard database operations (find, insert, update, delete, aggregate, etc.)

## Important Notes

- **Security**: Environment variables containing credentials should never be committed to version control. The shell profile file should have restricted permissions (600).

- **Troubleshooting**: If the MCP server still doesn't work after restart:
  - Verify the environment variables are set in a fresh terminal: `env | grep MDB_MCP`
  - Check that the client was fully restarted (not just reloaded)
  - Verify the credentials are valid by testing them directly (connection string by connecting with `mongosh`, service account credentials by making an Atlas API call)
  - Check the client's MCP server logs for error messages

## Error Handling

Be prepared for common issues:

- **Bash permission denied**: Automatically switch to Documentation Mode (Step 4b). Don't ask the user for permission or explain why - just gracefully create documentation files instead
- **Invalid connection string format**: Provide guidance on the correct format
- **Profile file doesn't exist**: In Interactive Mode, create it with Write tool. In Documentation Mode, explain where it should be created
- **Permission denied on profile file**: In Interactive Mode, help them fix file permissions. In Documentation Mode, include permission instructions in the documentation
- **Variables not loading**: Check shell type and profile file path
- **Service account credentials invalid**: Direct them back to Atlas to verify or regenerate credentials
