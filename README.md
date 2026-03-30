# MongoDB Agent Skills

Collection of official MongoDB agent skills for use in agentic workflows. For more information, refer to the [MongoDB Agent Skills documentation](https://www.mongodb.com/docs/agent-skills/).

## Installation

### Claude

1. Add the plugin marketplace to Claude locally:

   ```bash
   claude plugin marketplace add https://github.com/mongodb/agent-skills.git
   ```

2. Use the `/plugin` command to look for the `mongodb` plugin.
3. Install the plugin, then run `/reload-plugins` to activate it.

### Cursor

Install the plugin from the [Cursor marketplace](https://cursor.com/marketplace/mongodb).

### Gemini

Install the extension from the [Gemini marketplace](https://geminicli.com/extensions/?name=mongodbagent-skills).

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
