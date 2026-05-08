# Contributing

## Releasing

Releases are driven by GitHub Actions. Release operators should use the
workflows rather than editing version fields, creating tags, or drafting GitHub
releases by hand.

1. Start the `Prepare Release` workflow (`.github/workflows/prepare-release.yml`)
   from the GitHub Actions UI, using `main` as the workflow branch.
2. Choose the version source:
   - `patch`, `minor`, or `major` increments the current plugin version.
   - `exact` uses the `exact_version` input, for example `1.2.3`.
3. Review the release PR that the workflow opens. Confirm that the target
   version is correct and that CI passes.
4. Merge the release PR.
5. Wait for the `Draft Release` workflow to create the draft GitHub release.
6. Review the generated notes, add any platform-specific context that should be
   included, and confirm that the draft release tag matches the release PR
   version and targets the merged `main` commit. Then publish the draft release.
7. Manually submit plugin updates for [Cursor](#cursor) and [Claude](#claude).
8. Coordinate the [VS Code](#vs-code) extension update.

The repo release is complete after the GitHub release is published and the
Cursor and Claude updates have been submitted. Marketplace approval, marketplace
indexing, and downstream extension releases can happen afterward.

The `Draft Release` workflow also supports manual dispatch. If a release already
exists for the release tag, the workflow skips release creation.

### Releasing individual plugins

| Plugin or surface | Visible to users when | Operator action |
| --- | --- | --- |
| [Gemini](#gemini) | The extension gallery picks up the latest GitHub release | None |
| [Cursor](#cursor) | The Cursor Marketplace publishes the submitted update | Submit the update form |
| [Claude](#claude) | The Claude plugin directory publishes the submitted update | Submit the update form |
| [Copilot CLI](#copilot-cli) | Changes are merged to `main` | None |
| [Codex](#codex) | Changes are merged to `main` | None |
| [VS Code](#vs-code) | The VS Code extension publishes a release with the updated skills | Coordinate the extension update |

#### Gemini

No manual submission is required after publishing the GitHub release.

This repo is listed in the
[Gemini extension gallery](https://geminicli.com/docs/extensions/releasing/) via
the `gemini-cli-extension` GitHub topic and root `gemini-extension.json`. The
gallery crawls tagged repositories daily and should pick up the latest GitHub
release automatically.

#### Cursor

After publishing the GitHub release, submit the update through the
[Cursor Marketplace publish form](https://cursor.com/marketplace/publish). Use
the release tag as the submitted version and include any release notes that
matter to Cursor users. See the
[plugin submission details](https://docs.google.com/document/d/1F5kmD_3rmWsMDfcaVQ7s7UHcR8AFyg-sMnqopVTgYGk/edit?tab=t.0#heading=h.l834bz9xr4qf)
for what to include in the form. If you cannot access that document, stop and
ask for the required submission details.

#### Claude

After publishing the GitHub release, submit the update through the
[Claude.ai form](https://claude.ai/settings/plugins/submit). Each update is
scanned before it is shared in the plugin directory. See the
[plugin submission details](https://docs.google.com/document/d/1F5kmD_3rmWsMDfcaVQ7s7UHcR8AFyg-sMnqopVTgYGk/edit?tab=t.0#heading=h.l834bz9xr4qf)
for what to include in the form. If you cannot access that document, stop and
ask for the required submission details.

#### Copilot CLI

No manual submission is required after the release PR is merged.

Copilot CLI users install this plugin from the GitHub repository and pull
updates with `copilot plugin update mongodb` or `copilot plugin update --all`.
Copilot CLI can also recognize this repo's `.claude-plugin/marketplace.json` as
a marketplace manifest.

#### Codex

No manual submission is required after the release PR is merged.

This repo's Codex marketplace entry points at the GitHub repository with
`ref: "main"`. Codex does not have a native "latest GitHub release" source
selector.

#### VS Code

The VS Code extension is released from the
[mongodb-js/vscode](https://github.com/mongodb-js/vscode) repository. To include
skill changes from this repo, update the extension's `agent-skills` submodule to
the latest released tag, then run `pnpm run sync-skills` in the extension repo
to pull in any skill changes before releasing the extension.
