# Installing skill-validator-ent

## Installation methods

### Homebrew (recommended for macOS)

```bash
brew tap agent-ecosystem/homebrew-tap
brew install skill-validator-ent
```

### From source (requires Go 1.25.5+)

```bash
go install github.com/agent-ecosystem/skill-validator-ent/cmd/skill-validator-ent@latest
```

Ensure `$GOPATH/bin` (usually `~/go/bin`) is on your PATH:

```bash
export PATH="$PATH:$(go env GOPATH)/bin"
```

### From a pre-built binary

```bash
cp /path/to/skill-validator-ent /usr/local/bin/ && chmod +x /usr/local/bin/skill-validator-ent
```

## Verify installation

```bash
skill-validator-ent --version
```

## Prerequisites for LLM scoring

LLM scoring requires AWS Bedrock access:

1. **AWS CLI v2** (`aws --version`)
2. **AWS profile** with `bedrock:InvokeModel` permission
3. **Bedrock model access** enabled for `us.anthropic.claude-sonnet-4-5-20250929-v1:0`

### AWS SSO authentication (common for enterprise teams)

```bash
aws configure sso --profile bedrock   # one-time setup
aws sso login --profile bedrock       # repeat when session expires
aws sts get-caller-identity --profile <your-profile>  # verify
```

If verification fails: re-run `aws sso login`, check `bedrock:InvokeModel`
permission, or confirm model enablement in the Bedrock console.
