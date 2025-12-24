# Antigravity AI Proxy Setup

Use AI coding tools (Claude Code, Roo Code, Cursor, etc.) with Antigravity models (Claude, Gemini, GPT) via CLIProxyAPI - no API keys needed, just your Google account.

## What This Does

```
AI Tool → Middleware (8318) → CLIProxyAPI (8317) → Antigravity → Google AI
```

- **Free access** to Claude Opus 4.5, Sonnet 4.5, Gemini 3 Pro, GPT-OSS via Google OAuth
- **Multi-account rotation** - add multiple Google accounts to increase rate limits
- **MCP server support** - middleware normalizes JSON schemas for Gemini compatibility
- **Works with Claude Code, Roo Code, Cursor** - supports both Anthropic and OpenAI APIs
- **Token counting** - returns usage stats for all requests

## Quick Start (One Command)

```bash
git clone https://github.com/FasalZein/AntiCC.git ~/Dev/AntiCC
cd ~/Dev/AntiCC
./setup.sh
```

The setup script will:
1. Install CLIProxyAPI (via Homebrew on macOS, direct download on Linux/WSL)
2. Build the middleware (requires Go 1.21+)
3. Generate an API key
4. Create config files
5. Add shell configuration to your terminal
6. Prompt you to login to Antigravity

### Requirements

- **macOS** or **Linux/WSL** (Windows via WSL)
- **Homebrew** (macOS) - for installing CLIProxyAPI
- **Go 1.21+** - for building middleware (optional but recommended for MCP support)

## Manual Setup

If you prefer to set up manually:

### 1. Install CLIProxyAPI

**macOS (Homebrew):**
```bash
brew install router-for-me/tap/cliproxyapi
```

**Linux/WSL (Direct Download):**
```bash
# Download latest release
VERSION=$(curl -sL https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')
curl -sL "https://github.com/router-for-me/CLIProxyAPI/releases/download/${VERSION}/CLIProxyAPI_Linux_${ARCH}.tar.gz" | tar xz

# Install to ~/.local/bin
mkdir -p ~/.local/bin
mv CLIProxyAPI ~/.local/bin/cliproxyapi
chmod +x ~/.local/bin/cliproxyapi

# Add to PATH (add to ~/.bashrc or ~/.zshrc)
export PATH="$HOME/.local/bin:$PATH"
```

### 2. Create Config Files

```bash
cp config.example.yaml config.yaml
cp .env.example .env

# Generate API key
API_KEY=$(openssl rand -hex 24 | sed 's/^/sk-/')
echo "CLIPROXY_API_KEY=\"$API_KEY\"" > .env

# Update config.yaml with your key (macOS)
sed -i '' "s/sk-your-api-key-here/$API_KEY/" config.yaml

# Or on Linux:
# sed -i "s/sk-your-api-key-here/$API_KEY/" config.yaml
```

### 3. Build Middleware (Optional)

```bash
cd middleware
go build -o cliproxy-middleware .
cd ..
```

### 4. Add Shell Config

Add to `~/.zshrc` or `~/.bashrc`:

```bash
# Antigravity Claude Code (anticc)
source "$HOME/Dev/CLIProxyAPI/anticc.sh"
```

### 5. Login & Start

```bash
source ~/.zshrc
anticc-login   # Opens browser for Google OAuth
anticc-up      # Start the proxy
claude         # Use Claude Code
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

## Using with Roo Code / Cursor / Other OpenAI Tools

The middleware supports the OpenAI API format, so you can use it with any OpenAI-compatible tool.

### Roo Code Configuration

In Roo Code settings, configure the API:

```json
{
  "openai.apiKey": "sk-your-api-key",
  "openai.baseUrl": "http://127.0.0.1:8318/v1",
  "openai.model": "gemini-claude-sonnet-4-5"
}
```

### Cursor Configuration

In Cursor settings:
- API Base URL: `http://127.0.0.1:8318/v1`
- API Key: Your CLIProxyAPI key from `.env`
- Model: `gemini-claude-sonnet-4-5`

### Token Usage

All responses include token usage:

```json
{
  "usage": {
    "prompt_tokens": 15,
    "completion_tokens": 7,
    "total_tokens": 22
  }
}
```

## Environment Variables (Claude Code)

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
│  AI Tool    │────▶│  Middleware  │────▶│ CLIProxyAPI  │────▶│ Antigravity │
│             │     │   (8318)     │     │   (8317)     │     │             │
└─────────────┘     └──────────────┘     └──────────────┘     └─────────────┘
                           │
                           ▼
                    ┌──────────────────────────┐
                    │ - Schema normalization   │
                    │ - Token count (Anthropic)│
                    └──────────────────────────┘
```

**Supported Endpoints:**
- `/v1/messages` - Anthropic API (Claude Code)
- `/v1/chat/completions` - OpenAI API (Roo Code, Cursor, etc.)
- `/v1/messages/count_tokens` - Anthropic token counting

**Middleware provides:**
- JSON Schema normalization (removes `propertyNames`, `anyOf`, etc. for Gemini)
- Token counting (local estimation for Anthropic `/v1/messages/count_tokens`)
- Streaming support for both APIs

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
