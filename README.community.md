# MongoDB Agent Skills — Community & Enterprise Advanced

This guide covers the **`mongodb`** plugin, which runs the [MongoDB MCP server](https://www.mongodb.com/docs/mcp-server/) locally (via `npx`) and connects to a MongoDB deployment you manage yourself — **MongoDB Community**, **Enterprise Advanced**, or any self-hosted or Atlas deployment reachable by connection string. It bundles the official MongoDB agent skills, including `mongodb-mcp-setup` to help you configure the connection.

> Looking for the **MongoDB-hosted Atlas** experience — a hosted MCP server with OAuth and no local setup? Use the **`mongodb-atlas`** plugin instead; see the [main README](README.md).

## Installation

### Claude

Install the plugin from the [Claude marketplace](https://claude.com/plugins/mongodb), or run the following command from a Claude session:

1. Install the plugin:

   ```bash
   /plugin install mongodb
   ```

2. Follow the prompts to complete the installation, then run `/reload-plugins` to activate it.

### Cursor

Install the plugin from the [Cursor marketplace](https://cursor.com/marketplace/mongodb), or run the following command from a Cursor session:

1. Install the plugin:

   ```bash
   /add-plugin mongodb
   ```

2. Follow the prompts to complete the installation.

### Codex

1. Add the mongodb/agent-skills marketplace to Codex:

   ```bash
   codex plugin marketplace add mongodb/agent-skills
   ```

2. Start Codex and open the plugins browser:

   ```bash
   /plugins
   ```

3. Navigate to the "MongoDB Agent Skills" tab and install the `mongodb` plugin.

### Gemini

Install the extension from the [Gemini marketplace](https://geminicli.com/extensions/?name=mongodbagent-skills), or run the following command from Gemini CLI:

1. Install the extension:

   ```bash
   gemini extensions install https://github.com/mongodb/agent-skills
   ```

2. Follow the prompts to complete the installation.

### Copilot CLI

Install the plugin from the GitHub repository: `/plugin install https://github.com/mongodb/agent-skills.git`. Then restart Copilot CLI to activate the MCP server.

To install just the agent skills without a plugin — via the Agent Skills Directory or a local clone — see [Installing the skills directly](README.md#installing-the-skills-directly) in the main README.

## Configuration

Using the MCP Server to connect to MongoDB requires authentication - you can use the `mongodb-mcp-setup` skill to guide you through the process. Alternatively, refer to the [MongoDB MCP server documentation](https://www.mongodb.com/docs/mcp-server/configuration/options/) for a full list of configuration options.
