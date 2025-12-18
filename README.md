# Claude Code + CLIProxyAPI + Antigravity Setup

This guide explains how to use Claude Code with Antigravity models via CLIProxyAPI, with optional Claude Code Router integration for advanced routing.

## Overview

CLIProxyAPI acts as a proxy server that allows Claude Code to use Antigravity models (Claude, Gemini, GPT) through your Google accounts. This setup enables:

- **Multi-account load balancing**: Rotate through 7 authenticated Google accounts
- **Automatic rate limit handling**: When one account hits limits, automatically switch to the next
- **Access to premium models**: Claude Sonnet 4.5, Claude Opus 4.5, Gemini 3 Pro, GPT-OSS 120B

## Two Ways to Use This Setup

### Option 1: Direct (CLIProxyAPI only)
- Simpler setup
- Use environment variables to configure models
- Commands: `anticc-up`, then `claude`

### Option 2: With Claude Code Router (Recommended)
- Advanced routing (different models for different tasks)
- Automatic model selection based on context (thinking, background, long context)
- Commands: `ccr-code` (handles everything)

## Available Antigravity Models

**IMPORTANT**: Antigravity Claude models have a `gemini-` prefix!

| Model ID | Description |
|----------|-------------|
| `gemini-claude-opus-4-5-thinking` | Claude Opus 4.5 with extended thinking |
| `gemini-claude-sonnet-4-5` | Claude Sonnet 4.5 |
| `gemini-claude-sonnet-4-5-thinking` | Claude Sonnet 4.5 with extended thinking |
| `gemini-3-pro-preview` | Gemini 3 Pro Preview |
| `gemini-3-pro-image-preview` | Gemini 3 Pro with image support |
| `gemini-2.5-flash` | Gemini 2.5 Flash |
| `gemini-2.5-flash-lite` | Gemini 2.5 Flash Lite (fastest) |
| `gemini-2.5-computer-use-preview-10-2025` | Gemini Computer Use Preview |
| `gpt-oss-120b-medium` | GPT-OSS 120B Medium |

## Your Configured Accounts

You have **7 Antigravity accounts** configured:

1. `app.devcanvas@gmail.com`
2. `fasal32725@gmail.com`
3. `fousiyaambukuthy@gmail.com`
4. `gostorage02@gmail.com`
5. `kaladyhouseabl@gmail.com`
6. `slayergod32725@gmail.com`
7. `ymcq.tech@gmail.com`

Account files are stored in: `~/.cli-proxy-api/antigravity-*.json`

## How Account Rotation Works

CLIProxyAPI uses **round-robin load balancing** with smart rate limit handling:

```
Request 1 → Account 1 (gostorage02@gmail.com)
Request 2 → Account 2 (fasal32725@gmail.com)
Request 3 → Account 3 (ymcq.tech@gmail.com)
...
Request 7 → Account 7 (slayergod32725@gmail.com)
Request 8 → Account 1 (back to start)
```

### Rate Limit Handling

When an account hits a rate limit:

1. CLIProxyAPI marks the account as rate-limited
2. Records the reset time (usually 1 minute)
3. Skips that account for subsequent requests
4. Automatically re-enables when the reset time passes

With 7 accounts, you effectively get **7x the rate limit capacity**.

## Setup Instructions

### Step 1: Start CLIProxyAPI

```bash
# Using the config in this directory
CLIProxyAPI --config ./config.yaml

# Or using the default Homebrew config
CLIProxyAPI
```

The server will start on `http://127.0.0.1:8317`

### Step 2: Configure Claude Code Environment Variables

Add these to your `~/.zshrc` or `~/.bashrc`:

```bash
# ============================================================================
# Claude Code + CLIProxyAPI + Antigravity Configuration
# ============================================================================

# CLIProxyAPI endpoint
export ANTHROPIC_BASE_URL="http://127.0.0.1:8317"
export ANTHROPIC_AUTH_TOKEN="sk-046ad23dfe424a369795433c1c9e0cc4f35a7d318c4e1716"

# Model configuration for Claude Code 2.x.x
# IMPORTANT: Antigravity Claude models have "gemini-" prefix!
export ANTHROPIC_DEFAULT_OPUS_MODEL="gemini-claude-opus-4-5-thinking"
export ANTHROPIC_DEFAULT_SONNET_MODEL="gemini-claude-sonnet-4-5"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="gemini-claude-sonnet-4-5"

# ============================================================================
# ALTERNATIVE CONFIGURATIONS (uncomment one set to use)
# ============================================================================

# Option 2: Using Antigravity Gemini models
# export ANTHROPIC_DEFAULT_OPUS_MODEL="gemini-3-pro-high"
# export ANTHROPIC_DEFAULT_SONNET_MODEL="gemini-3-pro-low"
# export ANTHROPIC_DEFAULT_HAIKU_MODEL="gemini-3-pro-low"

# Option 3: Using Claude with thinking for all tiers
# export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-4-5-thinking"
# export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet-4-5-thinking"
# export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-sonnet-4-5"

# Option 4: Mixed configuration (Claude + Gemini)
# export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-4-5-thinking"
# export ANTHROPIC_DEFAULT_SONNET_MODEL="gemini-3-pro-high"
# export ANTHROPIC_DEFAULT_HAIKU_MODEL="gemini-3-pro-low"

# Option 5: Using GPT-OSS for opus tier
# export ANTHROPIC_DEFAULT_OPUS_MODEL="gpt-oss-120b-medium"
# export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet-4-5"
# export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-sonnet-4-5"
```

Then reload your shell:

```bash
source ~/.zshrc  # or source ~/.bashrc
```

### Step 3: Verify Setup

Test that CLIProxyAPI is running:

```bash
curl http://127.0.0.1:8317/v1/models
```

### Step 4: Use Claude Code

Now you can use Claude Code normally, and it will route through CLIProxyAPI to Antigravity:

```bash
claude "Write a hello world program in Python"
```

## Model Selection Guide

### For Complex Reasoning Tasks
```bash
export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-4-5-thinking"
```
Best for: Architecture decisions, complex debugging, multi-step reasoning

### For General Coding
```bash
export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet-4-5"
```
Best for: Code generation, refactoring, documentation

### For Quick Tasks
```bash
export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-sonnet-4-5"
# or for faster responses:
export ANTHROPIC_DEFAULT_HAIKU_MODEL="gemini-3-pro-low"
```
Best for: Simple questions, quick edits, syntax help

### For Large Context Windows
```bash
export ANTHROPIC_DEFAULT_OPUS_MODEL="gemini-3-pro-high"
```
Best for: Analyzing large codebases (up to 1M tokens context)

## For Claude Code 1.x.x (Legacy)

If you're using an older version of Claude Code:

```bash
export ANTHROPIC_MODEL="claude-sonnet-4-5"
export ANTHROPIC_SMALL_FAST_MODEL="claude-sonnet-4-5"
```

## Adding More Accounts

To add additional Antigravity accounts:

```bash
CLIProxyAPI --antigravity-login
```

This will open a browser for OAuth authentication. The new account will be saved to `~/.cli-proxy-api/antigravity-<email>.json`.

## Configuration File Reference

The `config.yaml` file contains:

```yaml
# Server port
port: 8317

# Authentication directory
auth-dir: "~/.cli-proxy-api"

# API key for client authentication
api-keys:
  - "sk-046ad23dfe424a369795433c1c9e0cc4f35a7d318c4e1716"

# Retry failed requests (for rate limit handling)
request-retry: 3

# Quota exceeded behavior
quota-exceeded:
  switch-project: true
  switch-preview-model: true
```

## Known Limitations

### ⚠️ MCP Servers Not Compatible with Antigravity/Gemini Backend

**IMPORTANT**: When using Claude Code with Antigravity (via CLIProxyAPI), you **MUST disable all MCP servers** in your Claude Code configuration.

#### Why This Happens

MCP servers (like firecrawl, context7, exa, shadcn, etc.) send tool definitions with JSON Schema features that **Gemini's function calling API doesn't support**. This is a known limitation across the industry:

**Unsupported JSON Schema features in Gemini:**
- `propertyNames` - Used by firecrawl, context7
- `anyOf` / `oneOf` arrays - Used by many MCP servers
- Complex `type` arrays like `["string", "number", "boolean", "null"]`
- `$ref` / `$defs` references
- `additionalProperties` with nested schemas

#### Error Messages You'll See

```
Invalid JSON payload received. Unknown name "propertyNames" at 'request.tools[0].function_declarations[24].parameters.properties[4].value': Cannot find field.
```

Or:

```
Invalid JSON payload received. Unknown name "type" at 'request.tools[0].function_declarations[21].parameters.properties[1].value': Proto field is not repeating, cannot start list.
```

#### Solution: Disable MCP Servers

1. Open Claude Code settings: `claude /settings`
2. Remove or comment out MCP server configurations
3. Restart Claude Code

#### Related Issues (This is a Known Industry Problem)

- [google-gemini/gemini-cli #4301](https://github.com/google-gemini/gemini-cli/issues/4301) - inputSchema dropped due to property name issues
- [google-gemini/gemini-cli #2654](https://github.com/google-gemini/gemini-cli/issues/2654) - TypeError with multi-type JSON schema
- [google-gemini/gemini-cli #8075](https://github.com/google-gemini/gemini-cli/issues/8075) - Incorrect InputSchema causes 400 errors
- [google/adk-python #3424](https://github.com/google/adk-python/issues/3424) - MCP tools with anyOf schemas fail Gemini validation
- [microsoft/vscode #244467](https://github.com/microsoft/vscode/issues/244467) - VS Code implemented schema fixups for this

#### Why CLIProxyAPI Doesn't Fix This (Yet)

CLIProxyAPI passes through tool definitions as-is without schema transformation. VS Code implemented "schema fixups" to sanitize MCP tool schemas before sending to models with limited JSON Schema support. CLIProxyAPI would need similar functionality to support MCP with Gemini backends.

**Workaround**: Use Claude Code without MCP servers when using Antigravity, or use a different backend (like direct Claude API) when you need MCP functionality.

---

## Troubleshooting

### CLIProxyAPI not starting

Check if the port is already in use:

```bash
lsof -i :8317
```

### Rate limit errors

If you're still hitting rate limits with 7 accounts, you may need to:
1. Wait for the rate limit reset (usually 1 minute)
2. Add more accounts
3. Reduce request frequency

### Model not found errors

Make sure you're using the correct Antigravity model names:
- ✅ `claude-sonnet-4-5` (Antigravity)
- ❌ `claude-sonnet-4-5-20250929` (Standard CLIProxyAPI)

### Authentication errors

Re-authenticate the problematic account:

```bash
CLIProxyAPI --antigravity-login
```

### Check logs

Enable debug mode in `config.yaml`:

```yaml
debug: true
logging-to-file: true
```

Logs will be written to the `logs/` directory.

## Files in This Directory

| File | Description |
|------|-------------|
| `config.yaml` | CLIProxyAPI configuration |
| `aliases.sh` | Shell aliases (source in ~/.zshrc) |
| `README.md` | This documentation |

## Quick Commands (anticc)

After sourcing `aliases.sh`, you have access to these commands:

### Server Management
```bash
anticc-up       # Start CLIProxyAPI (recommended)
anticc-start    # Start CLIProxyAPI (foreground)
anticc-stop     # Stop CLIProxyAPI
anticc-restart  # Restart CLIProxyAPI
anticc-status   # Check if running
anticc-logs     # View logs
```

### Model Management
```bash
anticc-models   # List available models
anticc-show     # Show current model config
anticc-claude   # Switch to Claude models (gemini-claude-*)
anticc-gemini   # Switch to Gemini models
anticc-thinking # Switch to Claude thinking models
anticc-gpt      # Switch to GPT-OSS hybrid
```

### Account Management
```bash
anticc-login    # Add new Antigravity account
anticc-accounts # List configured accounts
```

### Other
```bash
anticc-init     # Full setup (start + verify)
anticc-test     # Test connection
anticc-config   # Edit config file
anticc-dir      # Go to config directory
anticc-help     # Show all commands
```

## Manual Commands

```bash
# Start CLIProxyAPI
CLIProxyAPI --config ./config.yaml

# Add new Antigravity account
CLIProxyAPI --antigravity-login

# Check CLIProxyAPI version
CLIProxyAPI --version

# List available models
curl http://127.0.0.1:8317/v1/models -H "Authorization: Bearer sk-046ad23dfe424a369795433c1c9e0cc4f35a7d318c4e1716"

# Test a completion with Antigravity Claude model
curl http://127.0.0.1:8317/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-046ad23dfe424a369795433c1c9e0cc4f35a7d318c4e1716" \
  -d '{
    "model": "gemini-claude-sonnet-4-5",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## Quick Start (Copy-Paste)

Add this to your `~/.zshrc`:

```bash
# Claude Code + Antigravity via CLIProxyAPI
source "/Users/tothemoon/Dev/Code Forge/CLIProxyAPI/aliases.sh"
```

Then run:
```bash
source ~/.zshrc
anticc-up
claude "Hello, world!"
```

## Claude Code Router Integration

Claude Code Router provides intelligent model routing based on task type. When integrated with CLIProxyAPI, you get:

- **Smart routing**: Different models for different tasks (thinking, background, long context)
- **Multiple providers**: Can mix Antigravity with other providers
- **Dynamic switching**: Use `/model` command in Claude Code to switch models

### Claude Code Router Config

Location: `~/.claude-code-router/config.json`

```json
{
  "APIKEY": "ccr-local-key-12345",
  "LOG": true,
  "LOG_LEVEL": "debug",
  "HOST": "127.0.0.1",
  "PORT": 3456,
  "API_TIMEOUT_MS": "600000",
  "Providers": [
    {
      "name": "Antigravity",
      "api_base_url": "http://localhost:8317/v1/chat/completions",
      "api_key": "sk-046ad23dfe424a369795433c1c9e0cc4f35a7d318c4e1716",
      "models": [
        "gemini-claude-opus-4-5-thinking",
        "gemini-claude-sonnet-4-5-thinking",
        "gemini-claude-sonnet-4-5",
        "gemini-3-pro-preview",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.5-computer-use-preview-10-2025"
      ],
      "transformer": {
        "use": [
          "OpenAI",
          ["maxtoken", {"max_tokens": 16384}]
        ]
      }
    }
  ],
  "Router": {
    "default": "Antigravity,gemini-claude-sonnet-4-5-thinking",
    "background": "Antigravity,gemini-claude-sonnet-4-5",
    "think": "Antigravity,gemini-claude-opus-4-5-thinking",
    "longContext": "Antigravity,gemini-3-pro-preview",
    "longContextThreshold": 60000
  }
}
```

### Router Commands

```bash
ccr-start    # Start CLIProxyAPI + Claude Code Router
ccr-code     # Run Claude Code through the router (auto-starts CLIProxyAPI)
ccr-ui       # Open web UI for configuration
ccr-config   # Edit router config
ccr-restart  # Restart the router
```

### How Routing Works

| Task Type | Model Used | When |
|-----------|------------|------|
| `default` | gemini-claude-sonnet-4-5-thinking | Normal coding tasks |
| `background` | gemini-claude-sonnet-4-5 | Background/async tasks |
| `think` | gemini-claude-opus-4-5-thinking | Complex reasoning (plan mode) |
| `longContext` | gemini-3-pro-preview | >60K tokens context |

### Dynamic Model Switching

In Claude Code, use `/model` to switch models on the fly:
```
/model Antigravity,gemini-claude-opus-4-5-thinking
```

## Resources

- [CLIProxyAPI Documentation](https://help.router-for.me/)
- [Claude Code Documentation](https://help.router-for.me/agent-client/claude-code)
- [Antigravity Setup Guide](https://help.router-for.me/configuration/provider/antigravity)
- [Claude Code Router](https://github.com/musistudio/claude-code-router)