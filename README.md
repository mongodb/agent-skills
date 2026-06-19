# MongoDB Agent Skills

Collection of official MongoDB agent skills for use in agentic workflows. For more information, refer to the [MongoDB Agent Skills documentation](https://www.mongodb.com/docs/agent-skills/).

This README covers the **`mongodb-atlas`** plugin, which connects your agent to the **MongoDB-hosted Atlas MCP server** over HTTP using OAuth. It bundles the official MongoDB agent skills for writing queries, designing schemas, optimizing queries, using Atlas Search and Vector Search, and more.

> **Connecting to MongoDB Community or Enterprise Advanced?**
> For self-managed deployments, use the **`mongodb`** plugin instead — it runs the MongoDB MCP server locally and connects to your own deployment. See **[Community & Enterprise Advanced setup](README.community.md)** for installation and configuration instructions.

The `mongodb-atlas` plugin is available on Claude, Cursor, Codex, GitHub Copilot (CLI and VS Code), and Grok.

## Installation

### Claude

Install `mongodb-atlas` from the [Claude marketplace](https://claude.com/plugins/mongodb-atlas), or run the following command from a Claude session:

1. Install the plugin:

   ```bash
   /plugin install mongodb-atlas
   ```

2. Follow the prompts to complete the installation, then run `/reload-plugins` to activate it.

### Cursor

Install `mongodb-atlas` from the [Cursor marketplace](https://cursor.com/marketplace/mongodb-atlas), or run the following command from a Cursor session:

1. Install the plugin:

   ```bash
   /add-plugin mongodb-atlas
   ```

2. Follow the prompts to complete the installation.

### Codex

1. Open the plugins browser:

   ```bash
   /plugins
   ```

2. Find the `mongodb-atlas` plugin and install it.

### GitHub Copilot CLI

1. Install the plugin:

   ```bash
   copilot plugin install mongodb-atlas
   ```

   To browse first, run `copilot plugin marketplace browse`.

### VS Code

Open the Extensions view (`⇧⌘X` / `Ctrl+Shift+X`), search for `@agentPlugins`,
find `mongodb-atlas`, and select **Install**.

### Grok

1. Open the marketplace browser in Grok Build:

   ```bash
   /marketplace
   ```

2. Find `mongodb-atlas` and press `i` to install it.

## Authentication

The `mongodb-atlas` plugin connects to the MongoDB-hosted Atlas MCP server using OAuth. The first time your agent uses the server, you'll be prompted to sign in to MongoDB Atlas in your browser.

## Installing the skills directly

The methods below install just the agent skills — the same skills both plugins bundle — for agents or workflows that don't use a plugin marketplace. They don't configure an MCP server; to add one, run `npx "mongodb-mcp-server@latest" setup`, which can configure either the hosted Atlas MCP server or a self-managed deployment. Installing the `mongodb-atlas` or `mongodb` plugin just does this for you as a convenience (bundling the MCP configuration); for self-managed specifics, see [Community & Enterprise Advanced setup](README.community.md).

### Vercel's Agent Skills Directory

[https://skills.sh/](https://skills.sh/) is a popular directory and CLI that automates installing skills:

```bash
npx skills add mongodb/agent-skills
```

### Local install from repository

1. Clone the repository:

   ```bash
   git clone https://github.com/mongodb/agent-skills.git
   ```

2. Copy the `skills/` directory to the location where your coding agent reads its skills or context files. Refer to your agent's documentation for the correct path.
