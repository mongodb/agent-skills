# Installing skill-validator

This repo uses the [grove-platform fork](https://github.com/grove-platform/skill-validator)
of skill-validator, which adds MongoDB-specific checks. The upstream Homebrew
formula and `go install github.com/agent-ecosystem/...` install the upstream
tool, which does not include them.

## Install the release used by CI

From the root of `agent-skills`, with the GitHub CLI (`gh`) installed and
authenticated, run:

```bash
bash tools/install-skill-validator.sh && export PATH="$HOME/.local/bin:$PATH"
```

The installer selects the macOS or Linux archive for your architecture (amd64 or
arm64), checks its SHA-256 against the pin in this repo before extracting it,
and installs the binary to `~/.local/bin` by default. You can pass a different
install directory and put that directory first on your `PATH` instead.

## Verify installation

```bash
skill-validator --version
bash tools/install-skill-validator.sh --version
```

The versions should match. If they don't, check `command -v skill-validator` to
see which installation is first on your `PATH`.

## Prerequisites for LLM scoring

LLM scoring uses the `claude-cli` provider, which shells out to the locally
installed `claude` binary. No API keys are needed — it uses the CLI's existing
authentication.

1. **Claude Code CLI** (`claude --version`) — install with
   `curl -fsSL https://claude.ai/install.sh | bash` on macOS, or follow the
   [Claude Code quickstart guide](https://code.claude.com/docs/en/quickstart)
   for other platforms
2. **Authenticated session** — run `claude` interactively to complete login if
   not yet authenticated
