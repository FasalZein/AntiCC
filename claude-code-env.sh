# Claude Code + CLIProxyAPI + Antigravity Environment Variables
# Source this file: source ./claude-code-env.sh
# Or add to ~/.zshrc: source /path/to/claude-code-env.sh

# CLIProxyAPI endpoint
export ANTHROPIC_BASE_URL="http://127.0.0.1:8317"
export ANTHROPIC_AUTH_TOKEN="sk-046ad23dfe424a369795433c1c9e0cc4f35a7d318c4e1716"

# Model configuration for Claude Code 2.x.x
# IMPORTANT: Antigravity Claude models have "gemini-" prefix!
export ANTHROPIC_DEFAULT_OPUS_MODEL="gemini-claude-opus-4-5-thinking"
export ANTHROPIC_DEFAULT_SONNET_MODEL="gemini-claude-sonnet-4-5"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="gemini-claude-sonnet-4-5"

echo "✓ Claude Code environment configured for Antigravity"
echo "  ANTHROPIC_BASE_URL: $ANTHROPIC_BASE_URL"
echo "  OPUS Model: $ANTHROPIC_DEFAULT_OPUS_MODEL"
echo "  SONNET Model: $ANTHROPIC_DEFAULT_SONNET_MODEL"
echo "  HAIKU Model: $ANTHROPIC_DEFAULT_HAIKU_MODEL"