# Installing the MongoDB Atlas integration with the Vercel CLI

Source: [vercel integration](https://vercel.com/docs/cli/integration) (page last updated September 17, 2026). Check `vercel --version` and `vercel integration add --help`, since flags and plans change between CLI releases.

## What the command does

`vercel integration add <integration>` (alias `vercel install`) installs the Marketplace integration on the team if needed, provisions a resource, connects it to the **currently linked project**, and then runs `vercel env pull`. This is the same native integration described in the Atlas guide, so its network and privilege defaults apply. Provisioning is billable and changes Atlas network access and users, so it needs the owner's explicit approval first.

## Plan first, then run

1. **Confirm the context.** The project is linked (`vercel link`), the right team is selected (`--scope`), and the CLI is logged in. Do not paste tokens into chat.
2. **Look up the integration instead of guessing its slug.** `vercel integration discover mongodb --format=json` lists matching integrations and products. Use the slug it returns.
3. **Read what the integration asks for.** `vercel integration add <integration> --help` lists the products, required metadata keys, and billing plans. `vercel integration guide <integration>` prints setup guidance for the project's framework (`--framework nextjs`).
4. **Present the plan.** Show the exact commands, the values you looked up (plan, region or other metadata, resource name), which environments will be connected, and what the user must approve: billing, the `0.0.0.0/0` access entry, and the `Vercel-Admin-*` user with `readWriteAnyDatabase`. If the user's policy forbids broad network access or broad privileges, stop and offer a manually connected cluster instead, since the integration cannot be restricted.
5. **Run only after approval.** For a plan-only request, do not run anything that provisions.

## Options that matter

| Option | Use |
| --- | --- |
| `-e, --environment <env>` | Connect only the named environments. Repeatable. Accepts `production`, `preview`, `development`, or a Custom Environment slug or ID of the linked project. **Without it, all three built-in environments are connected.** |
| `-n, --name` | Name the resource. |
| `-m, --metadata KEY=VALUE` | Provide required metadata. Repeatable. |
| `-p, --plan` | Billing plan ID, from `--help`. |
| `--prefix` | Prefix for the environment variable names, used as-is. Use it to avoid colliding with an existing `MONGODB_URI`. |
| `--no-connect` | Provision without connecting to the project (this also skips the env pull). |
| `--no-env-pull` | Skip `vercel env pull`, so no credentials are written to a local file. |
| `-F, --format=json` | Machine-readable output for agents. |

Example, scoped to Production and Preview only (the slug and plan come from the lookup steps, not from this document):

```bash
vercel integration add <slug-from-discover> -e production -e preview --no-env-pull --format=json
```

## Approval and non-interactive limits

- `vercel integration accept-terms <integration>` requires an interactive terminal and human confirmation. Terms acceptance, and any browser or device flow, belong to the user. Pause and ask; never try to bypass them.
- In non-interactive environments, required options must be passed as flags, because prompts are skipped.
- `vercel env pull` writes values to a local file. Confirm it is git-ignored and never print its contents.

## After provisioning

Verify as in the main workflow: inspect the resources and the variable names and scopes the CLI reported, check that Preview and Production are bound as intended, and confirm the Atlas access list and database user match what the user approved. Do not rely on the documented defaults as proof of current state.