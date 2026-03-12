# MongoDB Gemini Extension

This extension provides tools for managing and optimizing MongoDB databases using the official MongoDB MCP server.

## Configuration

The extension may require authentication to connect to a MongoDB instance. You can configure this using one of the following methods:

1. **Connection String (Direct Connection):**
   Set `MDB_MCP_CONNECTION_STRING` to the MongoDB connection string (e.g., `mongodb+srv://user:password@cluster.mongodb.net/`).

2. **Atlas Admin API Credentials:**
   Set `MDB_MCP_API_CLIENT_ID` and `MDB_MCP_API_CLIENT_SECRET` for MongoDB Atlas Admin API access.

3. **Atlas Local:**
   If Docker is installed, the Atlas Local tools can be used to create and connect to a local MongoDB instance. In this case, no additional configuration is required.

4. **Read-Only Mode:**
   Set `MDB_MCP_READ_ONLY=true` to enable read-only mode for the MCP server.

If the user needs help configuring the MCP server, use the `mongodb-mcp-setup` skill to guide them through the process.
