# Claude Code + Antigravity Setup

Use Claude Code with Antigravity models (Claude, Gemini, GPT) via CLIProxyAPI - no API keys needed, just your Google account.

## What This Does

```
Claude Code → Middleware (8318) → CLIProxyAPI (8317) → Antigravity → Google AI
```

- **Free access** to Claude Opus 4.5, Sonnet 4.5, Gemini 3 Pro, GPT-OSS via Google OAuth
- **Multi-account rotation** - add multiple Google accounts to increase rate limits
- **MCP server support** - middleware normalizes JSON schemas for Gemini compatibility
- **Works with any Claude Code version** - automatic model name translation

## Quick Start

### 1. Install CLIProxyAPI

```bash
brew install router-for-me/tap/cliproxyapi
```

### 2. Clone This Repo

```bash
git clone https://github.com/user/CLIProxyAPI-setup.git ~/Dev/CLIProxyAPI
cd ~/Dev/CLIProxyAPI
```

### 3. Generate Your API Key

```bash
# Generate a random API key
openssl rand -hex 24 | sed 's/^/sk-/'
# Example output: sk-a1b2c3d4e5f6...

# Edit config.yaml and replace "sk-your-api-key-here" with your generated key
```

### 4. Add Your Shell Config

Add to `~/.zshrc` or `~/.bashrc`:

```bash
# Antigravity Claude Code (anticc)
source "$HOME/Dev/CLIProxyAPI/anticc.sh"
```

Then reload:

```bash
source ~/.zshrc
```

### 5. Login to Antigravity

```bash
anticc-login
```

This opens a browser for Google OAuth. Add multiple accounts for higher rate limits.

### 6. Start & Use

```bash
anticc-up      # Start the proxy + middleware
claude         # Use Claude Code normally
```

## Available Commands

After sourcing `anticc.sh`:

| Command | Description |
|---------|-------------|
| `anticc-up` | Start CLIProxyAPI + middleware |
| `anticc-stop` | Stop all services |
| `anticc-status` | Check if services are running |
| `anticc-login` | Add new Google account |
| `anticc-accounts` | List configured accounts |
| `anticc-models` | List available models |
| `anticc-show` | Show current model config |
| `anticc-opus` | Use Opus as main model |
| `anticc-sonnet` | Use Sonnet as main model |
| `anticc-logs` | View CLIProxyAPI logs |
| `anticc-help` | Show all commands |

## Available Models

| Model | Best For |
|-------|----------|
| `gemini-claude-opus-4-5-thinking` | Complex reasoning, architecture |
| `gemini-claude-sonnet-4-5-thinking` | General coding with thinking |
| `gemini-claude-sonnet-4-5` | Fast coding tasks |
| `gemini-3-pro-preview` | Large context (1M tokens) |
| `gemini-2.5-flash` | Quick responses |
| `gpt-oss-120b-medium` | Alternative model |

## MCP Servers

The middleware normalizes JSON schemas so MCP servers work with Antigravity/Gemini backends.

### Supported MCP Servers

These work with the middleware:
- **Firecrawl** - Web scraping
- **Context7** - Documentation lookup
- **Exa** - Web search

### Configure MCP Servers

Create `.mcp.json` in your project directory:

```json
{
  "mcpServers": {
    "firecrawl-mcp": {
      "command": "npx",
      "args": ["-y", "firecrawl-mcp"],
      "env": {
        "FIRECRAWL_API_KEY": "your-firecrawl-key"
      }
    },
    "context7": {
      "command": "npx",
      "args": ["-y", "@context7/mcp"]
    }
  }
}
```

## Multi-Account Rotation

Add multiple Google accounts to increase rate limits:

```bash
anticc-login  # Add account 1
anticc-login  # Add account 2
anticc-login  # Add account 3
# ... add more as needed
```

CLIProxyAPI rotates through accounts automatically. When one hits rate limits, it switches to the next.

## Environment Variables

The `anticc.sh` script sets these automatically, but for reference:

```bash
export ANTHROPIC_BASE_URL="http://127.0.0.1:8318"  # Middleware port
export ANTHROPIC_AUTH_TOKEN="sk-your-api-key"
export ANTHROPIC_DEFAULT_OPUS_MODEL="gemini-claude-opus-4-5-thinking"
export ANTHROPIC_DEFAULT_SONNET_MODEL="gemini-claude-sonnet-4-5-thinking"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="gemini-claude-sonnet-4-5"
```

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌─────────────┐
│ Claude Code │────▶│  Middleware  │────▶│ CLIProxyAPI  │────▶│ Antigravity │
│             │     │   (8318)     │     │   (8317)     │     │             │
└─────────────┘     └──────────────┘     └──────────────┘     └─────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │ - Token count│
                    │ - Schema fix │
                    └──────────────┘
```

**Middleware provides:**
- Token counting (local estimation for `/v1/messages/count_tokens`)
- JSON Schema normalization (removes `propertyNames`, `anyOf`, etc. for Gemini)

## Files

| File | Description |
|------|-------------|
| `config.yaml` | CLIProxyAPI configuration |
| `anticc.sh` | Shell commands and environment setup |
| `middleware/` | Go middleware for token counting & schema normalization |

## Troubleshooting

### Services not starting

```bash
anticc-status  # Check what's running
anticc-logs    # View CLIProxyAPI logs
anticc-mw-logs # View middleware logs
```

### Rate limit errors

Add more Google accounts:

```bash
anticc-login
```

### Model not found

Make sure you're using Antigravity model names (with `gemini-` prefix for Claude models):

```bash
anticc-models  # List available models
```

### MCP server errors

Check if middleware is running:

```bash
curl http://127.0.0.1:8318/health
```

## Building the Middleware

The middleware is optional but recommended for MCP server support:

```bash
cd middleware
go build -o cliproxy-middleware ./cmd/middleware
```

## Resources

- [CLIProxyAPI Docs](https://help.router-for.me/)
- [Antigravity Setup](https://help.router-for.me/configuration/provider/antigravity)
- [Claude Code Docs](https://docs.anthropic.com/claude-code)

## License

MIT
