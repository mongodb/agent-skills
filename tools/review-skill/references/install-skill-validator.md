# Installing skill-validator

This repo uses the [grove-platform fork](https://github.com/grove-platform/skill-validator)
of skill-validator, which adds MongoDB-specific checks. The upstream Homebrew
formula and `go install github.com/agent-ecosystem/...` install the upstream
tool, which does not include them.

## Installation methods

### Release binary (recommended)

Replace `darwin_arm64` with your platform (`darwin_amd64`, `linux_amd64`,
`linux_arm64`):

```bash
gh release download --repo grove-platform/skill-validator --pattern '*_darwin_arm64.tar.gz' -O - | tar -xz skill-validator
sudo install -m 0755 skill-validator /usr/local/bin/
```

### From source (requires Go 1.25.5+)

```bash
git clone https://github.com/grove-platform/skill-validator.git
cd skill-validator
go install ./cmd/skill-validator
```

Ensure `$GOPATH/bin` (usually `~/go/bin`) is on your PATH:

```bash
export PATH="$PATH:$(go env GOPATH)/bin"
```

## Verify installation

```bash
skill-validator --version
```

The version should include `-grove`. If it does not, an upstream installation
earlier on your PATH is still being used.

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
