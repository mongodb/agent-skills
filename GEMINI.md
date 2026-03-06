# MongoDB Gemini Extension

This extension provides tools for managing and optimizing MongoDB databases using the official MongoDB MCP server.

## Configuration

The extension requires authentication with your MongoDB instance. You can configure this using one of the following methods:

1. **Connection String (Direct Connection):**
   Set `MDB_MCP_CONNECTION_STRING` to your MongoDB connection string (e.g., `mongodb+srv://user:password@cluster.mongodb.net/`).

2. **Atlas Admin API Credentials:**
   Set `MDB_MCP_API_CLIENT_ID` and `MDB_MCP_API_CLIENT_SECRET` for MongoDB Atlas Admin API access.

These settings can be configured during extension installation or in your environment.
