# MongoDB Agent Skills

Collection of official MongoDB agent skills for use in agentic workflows. For more information, refer to the [MongoDB Agent Skills documentation](https://www.mongodb.com/docs/agent-skills/).

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

1. Install the plugin by running the following command from a Codex session:

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

### Install using Vercel's Agent Skills Directory

https://skills.sh/ is a popular directory and a CLI that automates the installation of skills.

1. Add the skills you want to your agent:

   ```bash
   npx skills add mongodb/agent-skills
   ```

2. Install the MCP server: `npx mongodb-mcp-server@1 setup` and follow the instructions.

### Local install from repository

1. Clone the repository:

   ```bash
   git clone https://github.com/mongodb/agent-skills.git
   ```

2. Install the skills for your platform:

   Copy the `skills/` directory to the location where your coding agent
   reads its skills or context files. Refer to your agent's documentation
   for the correct path.

3. Install the MCP server: `npx mongodb-mcp-server@1 setup` and follow the instructions.

## Configuration

Using the MCP Server to connect to MongoDB requires authentication - you can use the `mongodb-mcp-setup` skill to guide you through the process. Alternatively, refer to the [MongoDB MCP server documentation](https://www.mongodb.com/docs/mcp-server/configuration/options/) for a full list of configuration options.
