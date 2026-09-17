# Quick Start

**Scope**: This guide is a step-by-step walkthrough that demonstrates semantic search (using Automated Embedding), keyword search (using MongoDB Search), and hybrid search against the `sample_mflix` sample dataset in the user's cluster. Use it when the user wants a guided tour of MongoDB Search and Vector Search — it prescribes an exact interaction sequence, index names, and queries. For the underlying reference material behind each step, see `automated-embedding.md`, `vector-search.md`, `lexical-search-indexing.md`, `lexical-search-querying.md`, and `hybrid-search.md`.

## Table of Contents

- [Interaction Principle](#interaction-principle)
- [Step 0 — Check MCP Connection](#step-0--check-mcp-connection)
- [Step 1 — Load Sample Data](#step-1--load-sample-data)
- [Step 2 — Choose Your Path](#step-2--choose-your-path)
- [Path A: Semantic Search (Automated Embedding)](#path-a-semantic-search-automated-embedding)
- [Path A2: Semantic Search (Bring Your Own Embeddings)](#path-a2-semantic-search-bring-your-own-embeddings)
- [Path B: Keyword Search (Atlas Search)](#path-b-keyword-search-atlas-search)
- [Path C: Hybrid Search](#path-c-hybrid-search)
- [Wrap Up](#wrap-up)
- [Troubleshooting](#troubleshooting)

## Interaction Principle

**Act first. Explain second. Then ask.**

Every step follows the same rhythm:
1. Do something automatically (create an index, run a query)
2. Explain what just happened in plain language
3. Ask if the user wants to go one step further

Never ask the user to decide something they haven't seen yet.

**Never end a turn without the next step.** Every turn closes with an AskUserQuestion or a completed action. Explaining a result and stopping is a dead end — the user is following, not driving, and has no way to know what comes next. If a step contains a question, ask it in the same turn as the explanation. Drive the step sequence to the end; the only valid stopping points are the user choosing to stop, or Wrap Up.

## Step 0 — Check MCP Connection

Verify the MongoDB MCP is connected by calling `list-databases`.

- If it **succeeds**: proceed silently to Step 1.
- If it **fails**: get the connection working before continuing. If the `mongodb-mcp-setup` skill is available, invoke it inline. If it is not available (it does not ship in every plugin), tell the user:
  > "I can't reach your cluster through the MongoDB MCP server. Check that the server is running and that `MDB_MCP_CONNECTION_STRING` (or your Atlas service account credentials) is set in your client config, then restart the client and tell me when it's ready."

  Do not continue until `list-databases` succeeds.

## Step 1 — Load Sample Data

Use `list-databases` to check if `sample_mflix` exists on the cluster.

**If it does not exist:** tell the user:
> "We'll use a sample movies dataset that Atlas provides. To load it: go to cloud.mongodb.com → your cluster → click the vertical ellipses → select **Load Sample Dataset**. Come back once it's loaded."

Wait for confirmation, then re-run `list-databases` to verify `sample_mflix` now appears. If it does not appear yet, tell the user:
> "It's not available yet. Give it another moment and let me know when it's loaded."

Repeat until `sample_mflix` is confirmed present before continuing.

**For everyone (whether dataset was just loaded or already present):**

Use `collection-schema` on `sample_mflix.movies` and tell the user:
> "Here's what your data looks like — each document is a movie with a title, plot description, and genre. These are the fields we'll make searchable."

Show a condensed example document (title, plot, genres fields only).


**Explain:**
- This is a real dataset of ~21,000 movies already in your cluster
- Each document = one movie
- We're using sample data — this is the same structure you'd use for your own content

## Step 2 — Choose Your Path

Use AskUserQuestion to ask:

> "What kind of search do you want to try?"

- **Semantic Search** *(Recommended)* — Find results by meaning, even when words don't match. Best for discovery, recommendations, and natural language queries.
- **Keyword Search** — Find results by exact words, with typo tolerance and autocomplete. Best for search boxes where users type specific terms.
- **I'm not sure** — routes to Semantic Search with an extra line of explanation.

## Path A: Semantic Search (Automated Embedding)

### Step 3a — Cluster Readiness

**Principle: never block a beginner on a question they can't answer. Try the real operation and let its result tell you what the tier supports.** Do NOT ask the user "what tier are you on?" up front.

**3a.1 — Try to auto-detect the tier (silent, best-effort).**

Attempt `atlas-inspect-cluster` to read the cluster tier.

- **If it succeeds:** note the tier internally and apply the tier-specific guidance in 3a.3. Don't make the user do anything.
- **If it fails** (401 Unauthorized / no Atlas Admin API key / any error): do NOT stop and do NOT interrogate the user. Ask and continue:
  > "I couldn't automatically read your cluster tier — that needs a separate Atlas management key, which isn't required for anything we're doing. No problem: I'll just build the index, and if your tier can't support it, the build itself will tell us and I'll walk you through the fix."

  (Optional, offered as help — never required:)
  > "If you're curious, your tier is shown right under your cluster's name in the Atlas UI — e.g. 'M0 Sandbox', 'Flex', or 'M10'."

**3a.2 — Proceed straight to the index build (the real test).** Go to Step 4a, which walks through the cost and creates the `quickstart_semantic` auto-embed index. The creation call is the source of truth — it either succeeds or returns one of the two catchable errors in 3a.3.

**3a.3 — Catch the only two real failures.**

**① Index-count cap (Free/Flex).** Current limits: **M0 = 3** search/vector indexes total, **Flex = 10** total — and these counts include indexes already on the collection. If `create-index` returns an error about exceeding the maximum number of indexes:
  > "Heads up — you've hit your cluster's index limit. Free (M0) clusters allow **3 search/vector indexes total** and Flex allows **10**. These counts include any indexes already on the cluster.
  >
  > Two ways forward:
  > - **Make room:** delete an unused search index, or
  > - **Scale up:** move to Flex (10) or a dedicated tier for more headroom.
  >
  > Want me to list your existing indexes so we can see what's using the budget?"

  If they agree, run `collection-indexes` (or `$listSearchIndexes`) and show the current indexes so they can choose which ones to remove. Never delete anything without explicit confirmation. After freeing room or scaling, retry the build.

**② Dedicated cluster without storage auto-scaling (auto-embed only).** Automated Embedding on dedicated (`M10+`) clusters **requires storage auto-scaling** — because the generated embeddings are stored on your own cluster and consume disk. This is a *disk* requirement, not a compute/tier one: do **not** tell users to raise their max cluster tier.

  Note the failure mode is **not** a failed build. If the cluster runs out of disk, MongoDB *pauses* embedding generation and the index transitions to **`Stale`** state; once disk is freed, generation resumes automatically. So watch for a `Stale` status from `collection-indexes`, not an error from `create-index`.

  If 3a.1 detected a dedicated tier with storage auto-scaling off, or the index goes `Stale`:
  > "Automated Embedding on a dedicated cluster **requires storage auto-scaling**. That's because MongoDB stores the generated embeddings on your own cluster, so the index needs room to grow as it embeds your documents. If the cluster runs out of disk, embedding generation pauses and the index goes into a `Stale` state — it isn't lost, and it resumes automatically when there's space again.
  >
  > To enable it: Atlas UI → your cluster → **Edit Configuration** → **Storage** → turn on **storage auto-scaling**, then come back.
  >
  > Prefer not to change cluster settings? We can switch to the manual-embeddings path (Path A2) instead — it uses pre-computed vectors already in the sample data, with no embedding generation and no token usage."

  Wait for the user to enable storage auto-scaling and retry, OR route to Path A2.

  **Note on tiers:** this requirement is scoped to dedicated clusters — it does **not** mean autoEmbed requires `M10+`. Free and Flex clusters can use Automated Embedding (they are subject to the index caps in ① and to Free Tier rate limits). Never tell a Free/Flex user that Automated Embedding is unavailable for them.

**3a.4 — Cost is an FYI, not a gate.** Surface the token note when the build is underway or done — never as a decision the user must make first. (The detailed note lives in Step 4a's token allocation section.)

### Step 4a — Recommend AutoEmbed Index

Before creating anything, explain the value and cost:

> **Here's how Automated Embedding works:**
>
> MongoDB handles everything — you don't write any embedding code. When you create this index, MongoDB reads every movie plot and converts it into a **vector** (a list of numbers that captures its meaning) using a Voyage AI model called **voyage-4**. It does this automatically, in the background, every time you add or update a document.
>
> **Token allocation:**
> - You get **200 million free tokens** per model, per organization — one-time, shared across all your Atlas projects
> - After that, voyage-4 costs **$0.06 per million tokens**
> - For reference: ~21,000 movie plots is roughly 5–10M tokens total for the initial sync
>
> **If you're on M0:** Once your 200M free tokens are exhausted, MongoDB automatically invoices you for additional usage — index builds and queries don't stop. You can add a payment method to your Atlas account without upgrading your cluster (Atlas → Billing → Payment Method). Charges are only for embedding model usage. This quickstart uses ~5–10M of your 200M free tokens, so you're well within the free allocation here.
>
> **Two more things worth knowing before you commit:**
> - **Where the embedding happens.** The embedding model runs on inference infrastructure that MongoDB operates — a multi-tenant service on Google Cloud in a **US region** — *regardless of which cloud provider or region your cluster is in*. Your text is sent there to be embedded. **Data transfer costs apply** on top of the token costs above. If you have data-residency requirements, this is the detail to check first.
> - **Where the embeddings are stored.** They live on *your* cluster, in a dedicated internal database (one generated-embeddings collection per autoEmbed index). So they consume your disk — which is why dedicated clusters need storage auto-scaling.
>
> **The index we'd create looks like this:**
> ```json
> {
>   "fields": [
>     { "type": "autoEmbed", "modality": "text", "path": "plot", "model": "voyage-4" },
>     { "type": "filter", "path": "genres" }
>   ]
> }
> ```

Use AskUserQuestion:
> "Want to create this index and try semantic search?"

- **Yes, create it** → proceed to create the index
- **Try with existing embeddings** → route to Path A2 (manual vector search using pre-embedded data, no auto embedding needed)

If yes, use `create-index` (or `mcp__mongodb-mcp-server__create-index`) to create a Vector Search index with `autoEmbed` type on `sample_mflix.movies` using the definition above.

Name the index: `quickstart_semantic`

**While the index builds, tell the user:**
> "MongoDB is now generating embeddings for all ~21,000 movie plots. This runs in the background and typically takes a few minutes for a collection of this size. I'll check when it's ready."

Wait for the index status to reach `READY` before running any queries. Check with `collection-indexes`.

### Step 5a — First Semantic Query

Tell the user:
> "Let's run your first semantic query: **'a story about growing up'**"

Run this aggregation with `aggregate`:

```javascript
db.movies.aggregate([
  {
    $vectorSearch: {
      index: "quickstart_semantic",
      path: "plot",
      query: "a story about growing up",
      numCandidates: 100,
      limit: 3
    }
  },
  {
    $project: {
      _id: 0,
      title: 1,
      plot: 1,
      score: { $meta: "vectorSearchScore" }
    }
  }
])
```

Display results in a clean table: Title | Score | Plot (truncated to ~100 chars).

**Explain to the user:**
> "None of those movie titles or plots contain the words 'growing up' — but MongoDB found them anyway. That's semantic search: it matched the **meaning** of your query, not the words. The score shows how similar each result is to what you asked for — closer to 1.0 means more similar."

Then show the query syntax as a reveal:
> "Here's what that query looks like under the hood:
> ```javascript
> $vectorSearch: {
>   index: "quickstart_semantic",
>   path: "plot",
>   query: "a story about growing up",  // plain text — no vectors needed
>   numCandidates: 100,
>   limit: 3
> }
> ```
> Notice `query` is just a text string. With auto embedding, MongoDB converts it to a vector internally — you don't need to generate the query vectors yourself."

### Step 6a — Explore Another Query

Use AskUserQuestion:
> "Want to try another query to see it work on a different theme?"

- **"unlikely friendship"** → run and show results
- **"revenge and justice"** → run and show results
- **Type your own** → run whatever they enter
- **Skip, move on** → proceed to Step 7a

After results: point out which movies surfaced and note whether any of the query words appear in the plot. If they don't — highlight it.

### Step 7a — Try Filtering

Use AskUserQuestion:
> "Want to narrow the results to a specific genre? Filters let you combine semantic similarity with exact criteria — like 'find me something emotionally similar to this query, but only in the Drama genre.'"

- **Yes, show me filtered search** → proceed
- **No, move on** → skip to Step 8a

If yes, run the same query with a genre filter:

```javascript
db.movies.aggregate([
  {
    $vectorSearch: {
      index: "quickstart_semantic",
      path: "plot",
      query: "a story about growing up",
      filter: { genres: { $eq: "Drama" } },
      numCandidates: 150,
      limit: 3
    }
  },
  {
    $project: {
      _id: 0,
      title: 1,
      genres: 1,
      score: { $meta: "vectorSearchScore" }
    }
  }
])
```

**Explain:**
> "MongoDB applied the genre filter **before** computing similarity — narrowing the candidate pool first, then finding the most semantically similar ones within it. This is faster than filtering after the fact."

Then show the query syntax:
> "Here's what the filtered query looks like:
> ```javascript
> $vectorSearch: {
>   index: "quickstart_semantic",
>   path: "plot",
>   query: "a story about growing up",
>   filter: { genres: { $eq: "Drama" } },  // applied before similarity search
>   numCandidates: 150,
>   limit: 3
> }
> ```
> The `filter` field accepts standard MongoDB query syntax — you can filter on any field you indexed as `type: filter`."

### Step 8a — Bridge to Keyword / Hybrid

Use AskUserQuestion:
> "Semantic search is great for open-ended queries. Keyword search is better when users type specific titles or names. Want to see them side by side — and then combine them into hybrid search?"

- **Yes** → run Path B steps 3b–8b quickly (show keyword search results), then go to Path C
- **No, I'm done** → skip to Wrap Up

## Path A2: Semantic Search (Bring Your Own Embeddings)

*This path is for users who prefer not to use Automated Embedding. Uses the `sample_mflix.embedded_movies` collection, which already has pre-computed 1536-dimensional plot embeddings from OpenAI's text-embedding-ada-002 model.*

### Step 3a2 — Explain Manual Vector Search

Tell the user:

> "Good news — the sample dataset actually includes a collection called `embedded_movies` that already has pre-computed vector embeddings stored on every document. So we can use this right now.
>
> With manual vector search, your application generates embeddings using a model of your choice (for example, OpenAI, Cohere, or Hugging Face) and stores them as a field in each document. MongoDB handles the similarity search — you control the embedding step.
>
> Here's what a document in `embedded_movies` looks like (simplified):
> ```json
> {
>   "title": "Toy Story",
>   "plot": "A cowboy doll is profoundly threatened...",
>   "plot_embedding": [0.0007, -0.0268, 0.0135, ...]  // 1536 numbers
> }
> ```
>
> The index definition tells MongoDB the number of dimensions and similarity metric to use:
> ```json
> {
>   "fields": [
>     {
>       "type": "vector",
>       "path": "plot_embedding",
>       "numDimensions": 1536,
>       "similarity": "cosine"
>     }
>   ]
> }
> ```"

### Step 4a2 — Create Manual Vector Index

Use `create-index` to create a vectorSearch index on `sample_mflix.embedded_movies`:

```json
{
  "fields": [
    {
      "type": "vector",
      "path": "plot_embedding",
      "numDimensions": 1536,
      "similarity": "cosine"
    }
  ]
}
```

Name the index: `quickstart_manual`

**While it builds, explain:**
> "Unlike Automated Embedding, MongoDB isn't generating anything here — the embeddings are already stored in your documents. The index just organizes them into a structure that makes similarity lookups fast."

Wait for status `READY` with `collection-indexes`.

### Step 5a2 — Run a "Find Similar Movies" Query

Explain to the user:

> "To query a manual vector search index, you need to pass a vector — an array of numbers representing the query terms. Normally your app generates this by sending the user's search text to an embedding model. Since we don't have an embedding API connected here, we take a movie we already know and find others with similar plots. This is exactly how recommendation systems work."

Use `find` to fetch the `plot_embedding` from a known movie (e.g. "Toy Story") from `sample_mflix.embedded_movies`, projection `{"plot_embedding": 1, "title": 1}`, limit 1.

Then run:

```javascript
db.embedded_movies.aggregate([
  {
    $vectorSearch: {
      index: "quickstart_manual",
      path: "plot_embedding",
      queryVector: <embedding from the movie above>,
      numCandidates: 100,
      limit: 5
    }
  },
  {
    $project: {
      _id: 0,
      title: 1,
      plot: 1,
      score: { $meta: "vectorSearchScore" }
    }
  }
])
```

Display results in a table: Title | Score | Plot snippet. Exclude the source movie from the display.

**Explain:**
> "MongoDB compared the query vector against every stored embedding and returned the most similar ones. The top result is the source movie itself (score ~1.0) — skip that one. The rest are movies whose plots are mathematically closest in meaning. No keyword matching — pure similarity between vectors."

> **In your own app:** instead of using an existing document's embedding as the query, you'd call your embedding model with the user's search text and pass the result as `queryVector`. The query structure is identical.

### Step 6a2 — Bridge to Keyword / Hybrid

Use AskUserQuestion:
> "That's manual vector search live against real data. Want to also see keyword search and hybrid — where both approaches run together?"

- **Yes** → proceed to Path B, then Path C
- **No, I'm done** → skip to Wrap Up

## Path B: Keyword Search (Atlas Search)

### Step 3b — Create Text Search Index

Use `create-index` to create an Atlas Search index on `sample_mflix.movies`:

```json
{
  "mappings": {
    "dynamic": false,
    "fields": {
      "title": { "type": "string" },
      "plot": { "type": "string" },
      "genres": { "type": "token" }
    }
  }
}
```

Name the index: `quickstart_text`

**Explain while it builds:**
> "A search index is a separate structure MongoDB builds alongside your data — like the index at the back of a book. It doesn't change your documents, it just makes specific fields fast to search. We're indexing the title, plot, and genres fields."

### Step 4b — First Keyword Search

Run with `aggregate`:

```javascript
db.movies.aggregate([
  {
    $search: {
      index: "quickstart_text",
      text: {
        query: "space adventure",
        path: ["title", "plot"]
      }
    }
  },
  {
    $project: {
      _id: 0,
      title: 1,
      plot: 1,
      score: { $meta: "searchScore" }
    }
  },
  { $limit: 3 }
])
```

Display results in a table: Title | Score | Plot snippet.

**Explain:**
> "MongoDB Search found movies where 'space' and 'adventure' appear across the title or plot — and ranked them by how relevant they are. The score reflects relevance, not just whether the word appeared."

Then show the query syntax:
> "Here's what keyword search looks like:
> ```javascript
> $search: {
>   index: "quickstart_text",
>   text: {
>     query: "space adventure",
>     path: ["title", "plot"]  // search across multiple fields at once
>   }
> }
> ```
> Compare this to `$vectorSearch` — `$search` uses the `text` operator and works with exact words. `$vectorSearch` uses `query` and works with meaning."

### Step 5b — Try Fuzzy Matching

Use AskUserQuestion:
> "Want to see what happens with a typo? Fuzzy matching is one of the most practical features for real search boxes."

If yes, run with intentional typos (`"sapce adventre"`):

```javascript
db.movies.aggregate([
  {
    $search: {
      index: "quickstart_text",
      text: {
        query: "sapce adventre",
        path: ["title", "plot"],
        fuzzy: { maxEdits: 1 }
      }
    }
  },
  {
    $project: { _id: 0, title: 1, score: { $meta: "searchScore" } }
  },
  { $limit: 3 }
])
```

**Explain:**
> "Both typos were tolerated — MongoDB allowed up to 1 character difference between the query and indexed text. This is what makes a search box feel forgiving and human."

Then show the query syntax:
> "One small addition to the keyword query:
> ```javascript
> text: {
>   query: "sapce adventre",
>   path: ["title", "plot"],
>   fuzzy: { maxEdits: 1 }  // allow up to 1 character difference per word
> }
> ```
> `maxEdits: 2` would be more forgiving, but too loose — short words start matching things they shouldn't."

### Step 6b — Try Autocomplete

Use AskUserQuestion:
> "Want to see search-as-you-type? This powers the dropdown suggestions that appear while someone is still typing."

Autocomplete needs `title` indexed as an `autocomplete` type, which `quickstart_text` does not have yet. There are two ways to get there, and **which one you use depends on your tooling**:

**Preferred when you have mongosh / a driver / Atlas UI — edit the existing index.** MongoDB supports updating a search index in place with `db.collection.updateSearchIndex(<name>, {<definition>})`. The old definition keeps serving queries while the new one builds, then swaps over. Pass the **complete** new definition (it replaces, not merges), with `title` as a multi-type field:

```json
"title": [
  { "type": "string" },
  { "type": "autocomplete", "tokenization": "edgeGram" }
]
```

**⚠️ Required when driving this from the MongoDB MCP server — create a second index instead.** The MCP exposes `create-index` and `drop-index` but **no update-index tool**, so there is no way to edit `quickstart_text` in place from here. Don't attempt it and don't drop the working index. Create a dedicated index named `quickstart_autocomplete`:

```json
{
  "mappings": {
    "dynamic": false,
    "fields": {
      "title": { "type": "autocomplete", "tokenization": "edgeGram" }
    }
  }
}
```

Then query it with `index: "quickstart_autocomplete"` instead of `quickstart_text`. This is a perfectly good pattern in its own right — a small, purpose-built autocomplete index stays fast and can be tuned independently of your main relevance index. Just remember it counts against the tier index caps in Step 3a.3 ①.

Tell the user which route you took and why.

Then run the query for the route you took. **The index name is not interchangeable — using the wrong one returns an error, because only one of the two indexes has `title` typed as `autocomplete`.**

**MCP route (second index):**
```javascript
db.movies.aggregate([
  {
    $search: {
      index: "quickstart_autocomplete",
      autocomplete: { query: "inc", path: "title" }
    }
  },
  {
    $project: { _id: 0, title: 1 }
  },
  { $limit: 5 }
])
```

**mongosh / driver / Atlas UI route (updated index):** same pipeline with `index: "quickstart_text"`.

**Explain:**
> "Three characters returned relevant title suggestions instantly. Autocomplete pre-indexes word fragments — it's purpose-built for speed so it can respond as fast as a user types."

Then show the query syntax:
> "Autocomplete uses a different operator inside `$search`:
> ```javascript
> $search: {
>   index: "quickstart_autocomplete",   // the index where title is an autocomplete field
>   autocomplete: {
>     query: "inc",   // partial input from the user
>     path: "title"   // field must be indexed as autocomplete type
>   }
> }
> ```
> This is what you'd call on every keystroke in a search box — it's designed to be that fast."

### Step 7b — Bridge to Hybrid

Use AskUserQuestion:
> "Keyword search finds exact matches. Want to see hybrid search — where MongoDB runs both keyword and semantic search at once and merges the results into one ranked list?"

- **Yes** → proceed to Path C
- **No, just the script** → skip to Wrap Up

## Path C: Hybrid Search

*Prerequisites: `quickstart_text` index (from Path B) + `quickstart_semantic` index (from Path A). If either is missing, create it silently before proceeding.*

### Step 8c — Run Hybrid Search

Run with `aggregate`:

**Two things to flag to the user before running it — both look like mistakes and aren't:**

1. **The two pipelines search for different text on purpose.** Semantic gets `"a story about growing up"` (a natural-language description of a *theme*), keyword gets `"coming of age"` (the literal *phrase* a plot would actually contain). Each pipeline is fed the query form it's good at. Say this out loud, or a beginner could read it as a typo.
2. **`limit: 20` inside each pipeline is the merge window**, and it is load-bearing. It caps how many documents `$rankFusion` evaluates from each pipeline — so cross-pipeline agreement is only visible *inside* that window. Set it to 5 and a document ranked #7 by keyword becomes invisible to the fusion, even if it's the best overall result. A reasonable default is 3–5× the number of final results you want.

```javascript
db.movies.aggregate([
  {
    $rankFusion: {
      input: {
        pipelines: {
          semanticPipeline: [
            {
              $vectorSearch: {
                index: "quickstart_semantic",
                path: "plot",
                query: "a story about growing up",
                numCandidates: 100,
                limit: 20
              }
            }
          ],
          keywordPipeline: [
            {
              $search: {
                index: "quickstart_text",
                text: { query: "coming of age", path: "plot" }
              }
            },
            { $limit: 20 }
          ]
        }
      },
      combination: {
        weights: {
          semanticPipeline: 0.7,
          keywordPipeline: 0.3
        }
      }
    }
  },
  {
    $project: { _id: 0, title: 1, plot: 1 }
  },
  { $limit: 5 }
])
```

Display results.

**Explain:**
> "MongoDB ran two searches in parallel — one by meaning, one by keywords — then merged them using an algorithm called **Reciprocal Rank Fusion**. Movies that ranked highly in **both** searches scored highest overall. The weights (70% semantic, 30% keyword) control how much each signal matters. You can tune these per query type."

Then show the query syntax:
> "Hybrid search uses `$rankFusion` to run multiple pipelines and merge them:
> ```javascript
> $rankFusion: {
>   input: {
>     pipelines: {
>       semanticPipeline: [ { $vectorSearch: { ... } } ],  // semantic search
>       keywordPipeline:  [ { $search: { ... } }, { $limit: 20 } ]  // keyword search
>     }
>   },
>   combination: {
>     weights: {
>       semanticPipeline: 0.7,  // 70% semantic
>       keywordPipeline: 0.3    // 30% keyword
>     }
>   }
> }
> ```
> Each pipeline runs independently — MongoDB merges the ranked results at the end. You can have more than two pipelines, and weight them however fits your use case."

### Step 9c — Try Different Weights (Optional)

Use AskUserQuestion:
> "Want to flip the weights and see how results change? For example, trust keywords more when users type exact titles."

If yes, re-run with `keywordPipeline: 0.7, semanticPipeline: 0.3` and show the diff in results.

**Explain:**
> "Different weights, different results. In a real product you might boost keyword search for navigational queries (user knows what they want) and boost semantic search for exploratory queries (user is browsing)."

## Wrap Up

Congratulate the user. Use AskUserQuestion:
> "Want a standalone Python script with everything you just ran — index creation, semantic search, keyword search, and hybrid search?"

If yes, copy `scripts/quickstart_complete.py` from this skill directory into the user's working directory, then tell the user:
> "Your script is at `<destination path>`. Change the `CONNECTION_STRING`, `DB_NAME`, and `COLLECTION_NAME` variables at the top to use your own data. That's the only edit needed."

## Troubleshooting

**`sample_mflix` not found**
- Load it from Atlas UI: cluster → three-dot menu → Load Sample Dataset

**Index stuck in Building state**
- Normal for large collections — check status with `collection-indexes`
- autoEmbed initial sync on 21K movies typically takes 2–5 minutes

**`$rankFusion` error**
- Run `db-stats` to check the MongoDB version.
- If below 8.0, tell the user: "Hybrid search requires MongoDB 8.0 or later — your cluster is on [version]. You can upgrade in Atlas, or we can wrap up here with what you've already built." Then proceed to Wrap Up.

**autoEmbed index creation fails**
- Do **not** tell the user they need an M10+ dedicated cluster — autoEmbed is not restricted to dedicated tiers. Free and Flex clusters can use it.
- Most likely cause is the tier index cap: **3** total search/vector indexes on Free, **10** on Flex, counting indexes already on the collection. See Step 3a.3 ①.
- Check `autoEmbed` isn't sharing an index definition with a `vector` type field — the two cannot coexist in the same index, and MongoDB throws an exception if both are present.
- Confirm the field `type` and `modality` weren't being edited on an existing index — those two are immutable after creation (other settings, and adding/deleting `autoEmbed` and `filter` fields, are fine).

**autoEmbed index shows `Stale` status**
- This is a disk-space pause, not a failure. Embedding generation resumes on its own once space is freed.
- On dedicated (`M10+`) clusters, enable **storage auto-scaling**: Atlas → cluster → Edit Configuration → Storage. See Step 3a.3 ②.

**No results returned**
- Check index name matches exactly — typos return no results silently
- Check index status is READY, not Building

**`$vectorSearch` returns an error (not just empty results)**
- Run `collection-indexes` to confirm the index exists
- If missing, the index needs to be created — return to the relevant creation step
