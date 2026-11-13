# MCP Server Troubleshooting

This skill requires the MongoDB MCP Server with Atlas Stream Processing tools enabled. If these tools are unavailable, follow the diagnostic steps below.

## Step 1: Verify MCP Server Connection

Check if the MongoDB MCP Server is connected to your environment.

**If not connected:**
- Install the MongoDB MCP Server
- Configure it with your Atlas API credentials (`apiClientId` and `apiClientSecret`)

## Step 2: Verify Tool Availability

Check that all four streams tools are available:
- `atlas-streams-discover`
- `atlas-streams-build`
- `atlas-streams-manage`
- `atlas-streams-teardown`

## Fallback Options (Limited Functionality)

If you cannot configure the MCP server immediately, you have limited alternatives:

### Option 1: Atlas CLI (Read-Only)
Use Atlas CLI API commands for exploration only:
```bash
atlas api streams listStreamWorkspaces --groupId <project-id>
atlas api streams getStreamWorkspace --tenantName <workspace-name> --groupId <project-id>
```

**Limitations:**
- Read-only operations only
- Cannot create or modify processors
- No automated validation or diagnostics

### Option 2: mongosh with sp.process() (Prototyping Only)
Use `sp.process()` in mongosh for ephemeral pipeline testing:
```javascript
sp.process([
  { $source: { connectionName: "sample_stream_solar" } },
  { $match: { temperature: { $gt: 50 } } }
])
```

**Limitations:**
- Ephemeral only — the processor is not persisted; connect mongosh to the workspace and results print in-session
- No deployed processor to bill
- Cannot exercise the MCP validation/diagnostics workflow
- Limited to simple pipeline validation

## Recommended Action

**For full Atlas Stream Processing capabilities, configure the MongoDB MCP Server with the streams tools enabled and Atlas API credentials set.** The fallback options above provide minimal functionality and are not suitable for production workflows.
