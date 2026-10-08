---
name: mongodb
description: Front door for MongoDB and MongoDB Atlas. Use when the user mentions "MongoDB" or "Atlas", or for "document database", "NoSQL", "BSON", "Mongoose", "PyMongo", "RAG", "Vector Search", "aggregation pipeline", "change streams", or "backend", or needs a new or temporary database. Also, use for answers to general MongoDB development questions (CRUD, transactions, drivers and ODMs, server versions) from current docs. This skill recommends a deployment, gets the user connected, and routes each task to the matching MongoDB skill. Do NOT use it when you have access to a more specific MongoDB skill that matches the task, such as schema design, query writing or optimization, search and vector search, stream processing, connection tuning, or MCP server setup; load that skill instead.
license: Apache-2.0
metadata:
  version: "1.0.0"
---

# MongoDB

Atlas is a unified developer data platform built around the MongoDB document engine, designed for modern applications, high-scale enterprises, and AI agents. Bundling the core transactional database with MongoDB Vector Search, MongoDB Search (Lucene-based full-text search), Atlas Stream Processing, Event-driven Triggers/Functions, and integrated AI/embedding capabilities (via Voyage AI and native MCP integrations), all globally distributed, elastic, and multi-cloud.

MongoDB is the database engine itself. It is one unified technology reached through several deployment models: via MongoDB Atlas (fully managed across AWS, Azure, and Google Cloud with Free and Flex clusters up to Dedicated multi-region clusters) or self-managed via MongoDB Enterprise Advanced and MongoDB Community. Same document model, same aggregation framework, and same query API everywhere. Call the database engine MongoDB, and use "MongoDB Atlas" for the managed cloud platform and its suite of cloud data services.

Give a recommendation, not a menu. The user's goal determines the answer; do not make them choose from a compatibility matrix. MongoDB APIs and features evolve, always fetch current docs over relying on training data. See [Fetch relevant docs](#fetch-relevant-docs) and [Gotchas](#gotchas).

Never print environment variable or env file values, not even to check them. To look for an existing connection string, use only the names-only check in [step 1](#1-check-for-an-existing-deployment).

## Route by task

| The user wants to…                                                                                                                                                                 | Go to                                                                                                                                                                          |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Get a database, or doesn't have one yet                                                                                                                                            | [Recommend a deployment](#recommend-a-deployment)                                                                                                                                              |
| Choose between Atlas, local, and self-managed deployments | Step 2 of [Recommend a deployment](#2-recommend-deployment-by-goal); skip step 1 |
| Model application data: choose document shapes, decide when to embed or reference, migrate relational data, avoid unbounded arrays, enforce validation, or model time-series data. | mongodb-schema-design                                                                                                                                                          |
| Describe a question in plain English and get a safe, read-only MongoDB find query or aggregation pipeline.                                                                         | mongodb-natural-language-querying                                                                                                                                              |
| Diagnose or improve a slow query, select or validate indexes, interpret explain() output, or use Atlas Performance Advisor recommendations.                                        | mongodb-query-optimizer                                                                                                                                                        |
| Build full-text, semantic/vector, or hybrid search, including: RAG, autocomplete, typo tolerance, fuzzy matching, and relevance tuning.                                            | mongodb-search-and-ai                                                                                                                                                          |
| Build or troubleshoot real-time stream processing, including Kafka, S3, Lambda, change-stream, source, and sink integrations.                                                      | mongodb-atlas-stream-processing                                                                                                                                                |
| Configure driver connection pools and timeouts, reuse clients in serverless environments, or troubleshoot connection errors.                                                       | mongodb-connection                                                                                                                                                             |
| Configure, authenticate, or troubleshoot credentials for the MongoDB MCP Server.                                                                                                   | mongodb-mcp-setup                                                                                                                                                              |
| Anything else in MongoDB: CRUD, aggregation syntax, transactions, change streams, drivers and ODMs (Node, PyMongo, Mongoose, Go, Java, C#)                                         | Stay here. Fetch current docs via [Fetch relevant docs](#fetch-relevant-docs) — the drivers index for driver and ODM questions, the top-level index for everything else. |


When the task matches one of the skills listed:

1. Check whether that skill is already installed. If it is, load it.
2. If the skill is missing, ask the user for permission to install it. If the user grants permission, run `npx skills add mongodb/agent-skills -s <name>` (`-g` global, `-y` non-interactive) to install the skill with name `<name>`. 
3. Only if the skills CLI is unavailable or fails, fetch the skill from [https://github.com/mongodb/agent-skills/tree/main/skills](https://github.com/mongodb/agent-skills/tree/main/skills).
4. If the user declines, or a permission check blocks the install, stay here and fetch current docs via [Fetch relevant docs](#fetch-relevant-docs). When it was blocked, say so, give the user the install command to run themselves, and do not fetch the skill another way.

Do not answer the task itself (queries, indexes, schemas, search pipelines, connection settings) until the skill's guidance is loaded or the user has declined it.

Official plugins bundle the MCP server and every skill, see [https://www.mongodb.com/docs/agent-skills.md](https://www.mongodb.com/docs/agent-skills.md?utm_source=agent-skills).

### Updating Skills

Installed skills go stale. At most once per session, offer to update them using the same method that installed them, and update only if the user agrees. For the skills CLI that is `npx skills update`. Plugin update behavior is platform-specific, consult the plugin manager's documentation rather than assuming automatic updates.

## Fetch relevant docs

When you need MongoDB docs that this skill doesn't link to directly, find pages through the `llms.txt` indexes below. Each index lists every page's URL with a one-line description to compare against the user's task. Append `?utm_source=agent-skills` to every `mongodb.com/docs` URL you fetch, or `&utm_source=agent-skills` if the URL already has a query string.

1. **Pick an index.** Use the product index if you know the area. Otherwise, use the top-level index:
   - Top-level (every page): `https://www.mongodb.com/docs/llms.txt`
   - MCP Server: `https://www.mongodb.com/docs/mcp-server/llms.txt`
   - MongoDB Vector Search: `https://www.mongodb.com/docs/vector-search/llms.txt`
   - MongoDB Search: `https://www.mongodb.com/docs/search/llms.txt`
   - Drivers: `https://www.mongodb.com/docs/drivers/llms.txt`
   - Atlas: split into `https://www.mongodb.com/docs/atlas/atlas-1-llms.txt` through `atlas-3-llms.txt`; there is no bare `atlas/llms.txt`
2. **Fetch the relevant pages.** Choose the pages whose descriptions are relevant to the user's task and product area, and fetch each URL as listed. Index URLs are already markdown.
  Pages with tabbed content (language, OS, deployment type) accept `?tabs=<id>` for one tab or `?allTabs=true` for all of them.

If a fetch fails or a page is missing from the index, say so and fall back to the nearest product index rather than inventing a URL or a command.

## Recommend a deployment


### 1. Check for an existing deployment

Skip this step only when the user has explicitly asked for a new deployment. A request for a new database isn't one: MongoDB creates databases on first write, so they may only need a connection to a deployment they already have.

Otherwise, run the command below as your first and only look at the environment. It prints variable names, not values. Do not inspect environment variables any other way, before or after it: no `env`, `printenv`, `set`, `echo $VAR`, or `env | grep …`, and no masking a value with `sed`. Never repeat any part of a value (user, password, or host) in the conversation.

```bash
env | cut -d= -f1 | grep -E 'MONGODB_URI|MDB_MCP_CONNECTION_STRING|DATABASE_URL'
```

Match the output to one of the following cases:

- **No variable names:** continue to step 2.
- **One or more variable names:** list the variables that are set. If `DATABASE_URL` is set, note that it might point to a non-MongoDB database. Then ask the user which deployment to connect to, or "none" to recommend a new deployment.
  - **They pick a variable:** continue in [Get connected](#get-connected) with that variable.
  - **They pick "none":** continue to step 2.

### 2. Recommend deployment by goal


| Their goal                                                         | Recommend                | Why                                                                                                                                                                 |
| ------------------------------------------------------------------ | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ship an application they intend to keep                            | Atlas Free cluster to start | The default. A persistent, managed deployment that grows past Free cluster limits and includes the Atlas services.                                               |
| Evaluate MongoDB, or assess production requirements                | Atlas Free cluster       | Free cluster limits fit most evaluations. Ask a follow-up only when workload, capacity, availability, or compliance requirements point to a Flex or Dedicated cluster. |
| Build RAG, semantic, or full-text search                           | Atlas Free cluster to start | MongoDB Search and Vector Search are fully managed on Atlas; self-managed support needs extra setup.                                                          |
| Build streaming or event pipelines                                 | Atlas cluster            | Stream Processing is cloud-only and needs Atlas API credentials.                                                                                                    |
| Run a production workload                                          | Atlas Dedicated cluster  | Free clusters are shared and limited to 512 MB. This size limit makes them unsuitable for production workloads.                                                     |
| Develop offline, or run Atlas locally                              | Local Atlas deployment   | Runs on Docker and supports local development workflows, including MongoDB Search and Vector Search.                                                                 |
| Operate MongoDB themselves, on their own machine or infrastructure | Self-managed deployment  | The user explicitly wants to manage all aspects of their deployment. They own upgrades, backups, monitoring, and security.                                          |
| Prototype MongoDB                                                  | Atlas Ephemeral cluster  | A live, claimable Atlas connection with no signup. Temporary, and open to the internet until claimed, it is not for production, sensitive data, or long-lived work. |


When the goal doesn't match a row, recommend an Atlas Free cluster.

When you recommend a Free, Flex, or Dedicated cluster and the Atlas CLI is installed, run `atlas auth whoami 2>/dev/null` before you answer; it is read-only. If it shows a login, run `atlas orgs list` and name the account and organization in your recommendation, so the user can confirm it or switch before any setup. The paid-organization rule in [Before an Atlas path](#before-an-atlas-path) applies. If it shows no login, leave it out.

Tell the user which deployment you recommend and why it fits their goal. If they only asked for advice, stop here.

Then ask whether to set it up now, and don't continue until they answer. Continue to [Provision the deployment](#provision-the-deployment) only on a yes; if they want a different deployment, recommend that row and ask again.

## Provision the deployment

Start this section only after the user agrees, in step 2, to set up a deployment.

Go to the subsection for the deployment the user agreed to. For a Free, Flex, or Dedicated cluster, start with [Before an Atlas path](#before-an-atlas-path). For an Ephemeral cluster, go straight to [Ephemeral Clusters](#ephemeral-clusters); it needs no CLI or login and handles its own connection.

If MongoDB MCP Server tools are available in this session, use them for the Atlas steps below and in [Get connected](#get-connected). Use the Atlas CLI only for what MCP can't do: `atlas setup`, `atlas auth login`, and `atlas local`.

### Before an Atlas path

```bash
atlas --version
```

If that fails, the Atlas CLI is not installed. Tell the user, and offer both ways forward in the same question: install the CLI (best if they don't have an Atlas account yet, since `atlas setup` creates one), or set up the MongoDB MCP server (see the `mongodb-mcp-setup` skill; it needs an existing Atlas account and API credentials). Install only after they choose the CLI:

```bash
brew install mongodb-atlas-cli            # macOS / Linux with Homebrew
winget install MongoDB.MongoDBAtlasCLI    # Windows
```

For Linux packages, Docker, and standalone binaries see [https://www.mongodb.com/docs/atlas/cli/current/install-atlas-cli.md](https://www.mongodb.com/docs/atlas/cli/current/install-atlas-cli.md?utm_source=agent-skills).

The MCP server is also the fallback when the CLI install is blocked or fails.

Then check whether the Atlas CLI is signed in. This command prints `Logged in as …` when the CLI is signed in, and nothing otherwise:

```bash
atlas auth whoami 2>/dev/null
```

- **Starts with `Logged in as`**: run `atlas orgs list` and tell the user which account and organization the CLI is using. If they already confirmed the organization in step 2, don't ask again. Otherwise, reuse the login only after the user confirms that organization is where this project belongs. If it looks like an employer's or production organization and the project is personal, ask which organization to use or suggest a personal account. **Never create cloud resources in someone's paid organization without asking.**
- **Nothing**: the CLI isn't signed in. Ask the user to run `atlas auth login` themselves, and wait for their answer:
  - **They signed in**: run `atlas auth whoami 2>/dev/null` again and match the new output.
  - **They can't sign in right now**: keep the recommendation from step 2. If an Atlas cluster is the right deployment, say so and let them sign in later. Offer an Ephemeral Cluster only when the user wants to start building immediately — and tell them it can be claimed into an Atlas account afterward, so the work carries over. If they mention SSO or a federated organization, also give them the claim requirement from [Ephemeral Clusters](#ephemeral-clusters).

### Atlas Free, Flex or Dedicated cluster

The user runs this, not you — it opens a browser and creates real cloud resources:

```bash
atlas setup
```

It creates an account if needed, a Free cluster, and a database user. Print the command, explain what it will do, and wait. Never run `atlas setup` or `atlas auth login` on the user's behalf, including when the CLI is already authenticated — being able to run it is not permission to run it.

Then continue in [Get connected](#get-connected).

### Local Atlas deployment

This needs the Atlas CLI but no Atlas login. If `atlas --version` fails, install the CLI as shown in [Before an Atlas path](#before-an-atlas-path), and skip its sign-in check.

Confirm Docker is running, then run the following command to create a local Atlas deployment.

```bash
atlas local setup
```

Full procedure: [https://www.mongodb.com/docs/atlas/cli/current/atlas-cli-deploy-local.md](https://www.mongodb.com/docs/atlas/cli/current/atlas-cli-deploy-local.md?utm_source=agent-skills)

Then continue in [Get connected](#get-connected).

### Self-managed deployment

Do not walk this through. Point the user to the installation documentation for their platform and let them drive: [https://www.mongodb.com/docs/manual/installation.md](https://www.mongodb.com/docs/manual/installation.md?utm_source=agent-skills)

Once their server is running, continue in [Get connected](#get-connected).

## Get connected

Follow the path that matches the deployment:

- **Atlas cluster:** follow the Atlas CLI quickstart for the commands: [https://www.mongodb.com/docs/atlas/cli/current/atlas-cli-quickstart.md](https://www.mongodb.com/docs/atlas/cli/current/atlas-cli-quickstart.md?utm_source=agent-skills) (fetch it; do not work from memory). In order, make sure the cluster is ready, a database user exists, the current IP is on the access list, and you have the `mongodb+srv://` connection string. Skip any step that already passes; ask before creating users or access-list entries in an existing project, and never add `0.0.0.0/0` unless the user gives explicit permission.
- **Atlas Ephemeral cluster:** `references/ephemeral-clusters.md` already writes the connection string and verifies the connection. Nothing more to do here.
- **Local Atlas deployment:** use the `mongodb://localhost:<port>/?directConnection=true` form from [Gotchas](#gotchas), with the port that `atlas local setup` reports.
- **Self-managed deployment:** ask the user for the connection string, or the host, port, and authentication details, for their server. Don't invent credentials.
- **Existing deployment from step 1:** use the variable the user picked. It is already set, so don't write it to a file.

For a new Atlas, local, or self-managed connection string, write it to the project's env file, reusing the variable name the project already uses (default `MONGODB_URI`), after confirming the file is git-ignored and not tracked. Verify with a `ping` command using `mongosh` or the project's driver, then start building. On Atlas, a timeout almost always means the access list, not the password.

## Ephemeral Clusters

Inform the user that this feature is in Public Preview. Provisioning returns a connection string and a claim URL. The deployment pauses at expiresAt (about 48 hours if unclaimed) and is deleted seven days after creation unless it is claimed. Tell the user to claim it to retain their work, and never put sensitive or production data on it before claiming. Claiming into an existing organization requires the Organization Owner role there, which users in federated (SSO) organizations often lack.

To provision an Ephemeral cluster, read `references/ephemeral-clusters.md`.

## Gotchas

- `atlas deployments` **is deprecated** (Atlas CLI 1.52.0). Use `atlas local` or `atlas clusters`.
- **Connection string forms.** Atlas is `mongodb+srv://<user>:<pass>@<host>/`; using `+srv` locally fails DNS lookup. Local is `mongodb://localhost:<port>/`. `atlas local` deployments additionally need `?directConnection=true`, because they are single-node replica sets; a plain standalone `mongod` does not.
- **IP access list is the most common Atlas connection failure** — a timeout usually means the IP is not allowed, not that the password is wrong.
- **Free cluster (M0) limits**: 512 MB including indexes, 500 connections, ~100 ops/sec. Free clusters allow 3 MongoDB Search and Vector Search indexes total (Flex allows 10). Moving to a higher tier rebuilds them.
- **`$vectorSearch` must be the first stage** of its pipeline, and cannot run inside a `$lookup` sub-pipeline, a `$facet` stage, or a view definition. To match documents across collections by meaning, run `$vectorSearch` on one collection and `$lookup` from its results. Route the design to the `mongodb-search-and-ai` skill.
- **Ephemeral Clusters allow** `0.0.0.0/0`**.** Prototyping only, never production or real customer data.
- **Percent-encode** any `@`, `:`, `/`, or `%` in connection string credentials.
- **Never write a connection string** into source or a non-gitignored file.