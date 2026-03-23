# MongoDB Agent Skills

Collection of official MongoDB agent skills for use in agentic workflows.

## Installation

### Claude

Install the plugin from the [Claude marketplace](https://claude.com/plugins).

### Cursor

Install the plugin from the [Cursor marketplace](https://cursor.com/marketplace).

### Gemini

Install the extension from the [Gemini marketplace](https://geminicli.com/extensions/).

#### Local install from repository

1. Clone the repository:

   .. code-block:: bash

      git clone https://github.com/mongodb/agent-skills.git

2. Install the skills for your platform:

   **Supported platforms (Claude Code, Cursor, Gemini CLI)**

   Copy the appropriate plugin directory to your project root:

   - For Claude Code: Copy the ``.claude-plugin/`` directory
   - For Cursor: Copy the ``.cursor-plugin/`` directory
   - For Gemini CLI: Copy the ``skills/`` directory

   **Other platforms**

   Copy the ``skills/`` directory to the location where your coding agent
   reads its skills or context files. Refer to your agent's documentation
   for the correct path.

3. Copy ``mcp.json`` to your project root (if using MCP Server).

4. Configure the MCP Server with your MongoDB connection details.

## Configuration

### MCP server environment variables

The MongoDB MCP server requires authentication. Set one of the following:

**Option A - Connection string** (direct MongoDB connection):

```bash
export MDB_MCP_CONNECTION_STRING="mongodb+srv://user:password@cluster.mongodb.net/"
```

**Option B - API credentials** (MongoDB Atlas Admin API):

```bash
export MDB_MCP_API_CLIENT_ID="your-client-id"
export MDB_MCP_API_CLIENT_SECRET="your-client-secret"
```

Add these to your shell profile (`~/.zshrc`, `~/.bashrc`, or equivalent) so they are available when your IDE starts. For a complete list of configuration options, see the [MongoDB MCP server documentation](https://github.com/mongodb-js/mongodb-mcp-server#configuration-options).
