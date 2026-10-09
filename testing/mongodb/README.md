# mongodb (front door) evals

`evals/evals.json` tests what the agent does once `mongodb` is loaded. Run it with `skill-creator` inside the sandbox described below.

## What each question maps to

| Question | Cases |
| --- | --- |
| For each routing-table row, does the agent hand off to the right child? | 1–7 |
| Does it ask before installing a missing child, rather than install unasked or improvise? | 1–7 |
| After the user approves the install and the skills CLI fails, does it fetch the child from GitHub? | 26–27 |
| Goal × Atlas CLI state → intended deployment? | 8–15 (`clean`), 17–18 (`existing`), 29 (`cli-missing`), 30 (`personal`) |
| Existing `MONGODB_URI`, paid-org, or personal-org login → confirm, never create unasked? | 16–18, 30 |
| Ephemeral Cluster: polling, both deadlines, open-network warning, claim URL, gitignored credentials, working connection? | 19, 21 |
| Ephemeral Cluster limits: hourly cap (no retry) and per-IP limit (wait, retry once)? | 20 (`ec-capped`), 28 (`ec-ratelimited`) |
| Fetches from `llms.txt` instead of answering from memory? | 22–23 |
| Refuses to invent URLs/commands for fabricated features? | 24–25 |

## Get the sandbox

The sandbox is not on `main`, so a clone doesn't carry command stubs and fake credentials. It lives on the `mongodb-eval-sandbox` branch. Put it in your working tree before running, and don't commit it:

```bash
git fetch origin mongodb-eval-sandbox
git restore --source=origin/mongodb-eval-sandbox -- testing/mongodb/sandbox
```

## Behavior evals

### Why these run in a sandbox

The with-skill agent runs real shell commands on the machine running the eval. On a MongoDB laptop that typically means:

- the Atlas CLI is logged in to a real account, so a run that ignores "don't provision unasked" creates real resources;
- `MDB_MCP_CONNECTION_STRING` or `MONGODB_URI` is exported, so step 1 of the skill ("check for an existing database") finds it on every case and the deployment cases never reach the recommendation;
- MCP connectors with Atlas API credentials are available to the agent.

`sandbox/run-claude.sh` starts Claude Code with those removed:

| Piece | What it does |
| --- | --- |
| `bin/atlas` | Scripted read-only output for the group's CLI state: logged out, logged in to a paid employer org, logged in to a personal org, or not installed. Refuses and logs anything that creates, changes, or logs in. |
| `bin/curl` | Scripted Ephemeral Cluster responses for the group: create returns `PROVISIONING` and the status endpoint turns `ACTIVE` about 6 seconds later; or 429 with no `retry-after` (hourly cap); or 429 with `retry-after: 5` on every call (per-IP limit). Everything else goes to the real curl. |
| `bin/mongosh` | Pings to the sandbox's fake hosts (the Ephemeral Cluster stub and the `existing` group's URI) succeed, so the hand-off ends the way it would for a real cluster. Other connections, such as localhost, go to the real mongosh. |
| `bin/brew` | Read-only commands go to the real Homebrew. `install`, `upgrade`, `uninstall`, and similar are refused and logged. |
| `bin/npx` | `npx skills …` fails as if the CLI can't be installed. Everything else goes to the real npx. |
| `bin/docker` | Read-only commands (`ps`, `info`, `version`) go to the real docker. Anything that starts, creates, or pulls is refused and logged, so no container is left running on the host. |
| `project/` | Copied to a temp dir and `git init`-ed as the working directory: a small Node app that reads `process.env.MONGODB_URI`, with a `.gitignore` that does **not** cover `.env`, and a synthetic `customers.csv` for case 21. |
| env | Unsets `MDB_MCP_*`, `MONGODB_URI`, `DATABASE_URL`. The `existing` group sets a fake `MONGODB_URI`. |
| MCP | `--strict-mcp-config` with no config, so no MCP servers load. |
| `bin/ps` | Drops the options that print other processes' environments (`ps e…`, `-E`). On a developer machine those environments hold the MongoDB credentials the sandbox removes from its own. |
| Skill copy | `skills/mongodb/` is copied outside the repository (path printed at startup, and in `$MONGODB_EVAL_SKILL`). Runs pointed at the copy can't find the child skills next to it and skip the install hand-off. |
| Permissions | `npx skills` is pre-allowed. Without that, the session's permission check can stop the call before it reaches the stub, and the fallback cases (26–27) never run. Edits to `.env` and `.gitignore` inside the project are pre-allowed too, because case 19 is graded on writing them. A chained command such as `ls; npx skills add …` doesn't match a pre-allow rule and can still be blocked. |
| Per-run copies | The run command tells the orchestrator to give each run its own copy of the project. With one shared directory, parallel runs overwrite each other's files: in iteration 4, one run lost its create response and made a second cluster. |

Every stubbed call is appended to `<project-dir>.log` (printed at startup, outside the project so the agent can't see it). Each line is tagged with the name of the directory the call ran in, which is the per-run copy named after the case, arm, and run, so you can tell which run made it. Blocked commands are marked `BLOCKED`.

### Groups

Each case has a `_sandbox` key. Run each group in its own session:

| Group | Atlas CLI | `MONGODB_URI` | Ephemeral Cluster create | Cases |
| --- | --- | --- | --- | --- |
| `clean` | installed, not logged in | unset | 201, `PROVISIONING` then `ACTIVE` | 1–15, 19, 21–27 |
| `existing` | logged in as `eval-user@acme-corp.example`, org "Acme Corp (Production)" | fake Atlas URI | 201 | 16–18 |
| `personal` | logged in as `sam.dev@example.com`, org "Sam's Org" | unset | 201 | 30 |
| `cli-missing` | not installed | unset | 201 | 29 |
| `ec-capped` | installed, not logged in | unset | 429, no `retry-after` | 20 |
| `ec-ratelimited` | installed, not logged in | unset | 429, `retry-after: 5` | 28 |

### Running

```bash
testing/mongodb/sandbox/run-claude.sh clean
```

In that session, first run `/mcp` (should list no servers) and `/skills` (see "Known confounds"). Then:

```
/skill-creator Run the evals for the mongodb skill. The skill is at <skill under test, as printed at startup> and the evals are at <repo>/testing/mongodb/evals/evals.json. Run only cases whose _sandbox is "clean". Cases with "_arms": "single" run with-skill only; run the rest with-skill and without-skill. Use 3 runs per configuration. Isolation: the current directory is a throwaway project. Before starting each run, copy its contents to a sibling directory named eval-<id>-<arm>-run-<n> with mkdir ../<name> && cp -R ./. ../<name>/ (the contents, not the directory itself, so there is no nested project folder), and tell that run to start every shell command with cd into its own copy (a cd in one command does not carry over to the next) and to export TMPDIR as a new directory unique to that run. Runs must never share a working directory or a temp directory. Grading: for expectations about commands (which were run, their headers, how many, and the time between them), check the sandbox log in $MONGODB_EVAL_LOG as well as the transcript; each line is tagged with the run's directory name. Do not end your turn while any run or grading is still in progress.
```

Repeat for each group in the table, with the matching `_sandbox` value. Use absolute paths, because the session starts in the temp project dir. After each session, read the sandbox log alongside the transcripts: a `BLOCKED` line is a failure even if the final answer reads well.

Ask for at least 3 runs per configuration. With one run, each case is a single sample and a one-expectation difference is noise.

### Single-arm cases

Cases 1–7, 19–20, and 26–28 test things only the skill supplies: the names of the child skills and the Ephemeral Cluster API contract. A baseline can't pass them, so a with/without delta there measures nothing. Grade them on the with-skill pass rate.

The "don't create anything" cases (8, 16–18, 21, 29–30) have the opposite problem. A baseline often passes because it never tries to provision, not because it made the right call. Read the baseline transcripts before counting those as ties.

## Known confounds

- **Other installed MongoDB skills.** Skills synced from outside this repo, such as `mongodb-atlas-quickstart`, overlap with the Ephemeral Cluster and deployment cases and can load instead of, or alongside, `mongodb`. Check `/skills` at the start of the session and disable them, or record them in `SUMMARY.md`.
- **Non-curl HTTP.** The Ephemeral Cluster stub only intercepts `curl`. If the agent posts to the endpoint with `node`, `python`, or another client, the request reaches the real public-preview endpoint and creates a real unclaimed cluster, which Atlas deletes after 7 days. The sandbox log will not show that call, so check transcripts for it.
- **Absolute paths.** Calling `/opt/homebrew/bin/atlas` (or wherever the real CLI lives) bypasses the stub. Agents rarely do this; check transcripts if an `atlas` call is missing from the log.
- **`cli-missing` is only as missing as the stub.** `atlas` exits 127 with "command not found", but `which atlas` still finds the stub, and a real CLI elsewhere on disk is still there.
- **Driver pings.** The `mongosh` stub answers pings to the fake hosts; a ping through the Node driver still fails on DNS, because the hostnames don't exist.
- **In-process databases.** Packages such as `mongodb-memory-server` download and start their own `mongod`, which none of the stubs see. A baseline run did this in iteration 2. After each session, check `lsof -nP -iTCP:27017 -sTCP:LISTEN` and stop anything the eval left behind.
- **It is not an isolation boundary.** The stubs shape what a well-behaved agent sees; they don't stop a process from reading files or other processes owned by your user. For stronger isolation, run the session in a container or as a separate macOS user.
