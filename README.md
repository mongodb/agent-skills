# MongoDB Agent Skills

Collection of official MongoDB agent skills for use in agentic workflows.

## Installation

### Cursor

(TODO: not published yet) Install the plugin from the [Cursor marketplace](https://cursor.com/marketplace).

#### Local install from repository

TBD

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
