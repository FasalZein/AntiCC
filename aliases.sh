# Claude Code + CLIProxyAPI + Antigravity + Claude Code Router Aliases
# Add this to your ~/.zshrc: source "/Users/tothemoon/Dev/Code Forge/CLIProxyAPI/aliases.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================
export CLIPROXY_CONFIG="/Users/tothemoon/Dev/Code Forge/CLIProxyAPI/config.yaml"
export CLIPROXY_DIR="/Users/tothemoon/Dev/Code Forge/CLIProxyAPI"
export CLIPROXY_API_KEY="sk-046ad23dfe424a369795433c1c9e0cc4f35a7d318c4e1716"
export CCR_CONFIG="$HOME/.claude-code-router/config.json"

# ============================================================================
# ENVIRONMENT VARIABLES FOR CLAUDE CODE
# ============================================================================
export ANTHROPIC_BASE_URL="http://127.0.0.1:8317"
export ANTHROPIC_API_KEY="$CLIPROXY_API_KEY"

# Antigravity Claude models (gemini- prefix required)
# Default: Opus as main driver for best quality
export ANTHROPIC_DEFAULT_OPUS_MODEL="gemini-claude-opus-4-5-thinking"
export ANTHROPIC_DEFAULT_SONNET_MODEL="gemini-claude-opus-4-5-thinking"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="gemini-claude-sonnet-4-5"

# ============================================================================
# ALIASES (anticc = Antigravity Claude Code)
# ============================================================================

# Start CLIProxyAPI server
alias anticc='CLIProxyAPI --config "$CLIPROXY_CONFIG"'
alias anticc-start='CLIProxyAPI --config "$CLIPROXY_CONFIG"'

# Start CLIProxyAPI in background
alias anticc-bg='CLIProxyAPI --config "$CLIPROXY_CONFIG" > /tmp/cliproxy.log 2>&1 &'

# Stop CLIProxyAPI
alias anticc-stop='pkill -f "CLIProxyAPI" && echo "CLIProxyAPI stopped"'

# Restart CLIProxyAPI
alias anticc-restart='anticc-stop; sleep 1; anticc-bg && echo "CLIProxyAPI restarted"'

# Check if CLIProxyAPI is running
alias anticc-status='pgrep -f "CLIProxyAPI" > /dev/null && echo "✓ CLIProxyAPI is running (PID: $(pgrep -f CLIProxyAPI))" || echo "✗ CLIProxyAPI is not running"'

# View CLIProxyAPI logs
alias anticc-logs='tail -f /tmp/cliproxy.log'

# List available models (with API key)
alias anticc-models='curl -s http://127.0.0.1:8317/v1/models -H "Authorization: Bearer $CLIPROXY_API_KEY" | python3 -m json.tool 2>/dev/null || echo "CLIProxyAPI not running or error"'

# Add new Antigravity account
alias anticc-login='CLIProxyAPI --antigravity-login'
alias anticc-add='CLIProxyAPI --antigravity-login'

# List Antigravity accounts
alias anticc-accounts='ls -la ~/.cli-proxy-api/antigravity-*.json 2>/dev/null | awk "{print \$NF}" | xargs -I {} basename {} .json | sed "s/antigravity-//" | sed "s/_/@/g" | sed "s/@gmail/@gmail./"'

# Quick test (with API key)
alias anticc-test='curl -s http://127.0.0.1:8317/v1/models -H "Authorization: Bearer $CLIPROXY_API_KEY" > /dev/null && echo "✓ CLIProxyAPI is responding" || echo "✗ CLIProxyAPI not responding"'

# Open config directory
alias anticc-dir='cd "$CLIPROXY_DIR"'

# Edit config
alias anticc-config='${EDITOR:-nano} "$CLIPROXY_CONFIG"'

# ============================================================================
# FUNCTIONS
# ============================================================================

# Start CLIProxyAPI and wait for it to be ready
anticc-up() {
    if pgrep -f "CLIProxyAPI" > /dev/null; then
        echo "CLIProxyAPI is already running"
        return 0
    fi
    
    echo "Starting CLIProxyAPI..."
    CLIProxyAPI --config "$CLIPROXY_CONFIG" > /tmp/cliproxy.log 2>&1 &
    
    # Wait for server to be ready
    for i in {1..10}; do
        sleep 0.5
        if curl -s http://127.0.0.1:8317/v1/models -H "Authorization: Bearer $CLIPROXY_API_KEY" > /dev/null 2>&1; then
            echo "✓ CLIProxyAPI is ready on http://127.0.0.1:8317"
            return 0
        fi
    done
    
    echo "✗ CLIProxyAPI failed to start. Check logs: anticc-logs"
    return 1
}

# Full setup: start proxy and verify
anticc-init() {
    echo "=== Antigravity Claude Code Setup ==="
    echo ""
    
    # Check accounts
    ACCOUNTS=$(ls ~/.cli-proxy-api/antigravity-*.json 2>/dev/null | wc -l | tr -d ' ')
    echo "Antigravity accounts: $ACCOUNTS"
    
    # Start server
    anticc-up
    
    echo ""
    echo "Environment configured:"
    echo "  ANTHROPIC_BASE_URL: $ANTHROPIC_BASE_URL"
    echo "  OPUS: $ANTHROPIC_DEFAULT_OPUS_MODEL"
    echo "  SONNET: $ANTHROPIC_DEFAULT_SONNET_MODEL"
    echo "  HAIKU: $ANTHROPIC_DEFAULT_HAIKU_MODEL"
    echo ""
    echo "Ready! Use 'claude' to start coding."
}

# Switch to Sonnet as main (faster, cheaper)
anticc-sonnet() {
    export ANTHROPIC_DEFAULT_OPUS_MODEL="gemini-claude-opus-4-5-thinking"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="gemini-claude-sonnet-4-5-thinking"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="gemini-claude-sonnet-4-5"
    echo "Switched to Sonnet as main driver"
    anticc-show
}

# Switch to Opus as main (DEFAULT - best quality)
anticc-opus() {
    export ANTHROPIC_DEFAULT_OPUS_MODEL="gemini-claude-opus-4-5-thinking"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="gemini-claude-opus-4-5-thinking"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="gemini-claude-sonnet-4-5"
    echo "Switched to Opus as main driver (default)"
    anticc-show
}

# Alias for backward compatibility
anticc-claude() {
    anticc-opus
}

# Show current model configuration
anticc-show() {
    echo "Current Model Configuration:"
    echo "  OPUS:   $ANTHROPIC_DEFAULT_OPUS_MODEL"
    echo "  SONNET: $ANTHROPIC_DEFAULT_SONNET_MODEL"
    echo "  HAIKU:  $ANTHROPIC_DEFAULT_HAIKU_MODEL"
}

# Help
anticc-help() {
    echo "Antigravity Claude Code (anticc) Commands:"
    echo ""
    echo "  Quick Start:"
    echo "    anticc-up       Start CLIProxyAPI, then use 'claude'"
    echo ""
    echo "  Server:"
    echo "    anticc-up       Start CLIProxyAPI (recommended)"
    echo "    anticc-stop     Stop CLIProxyAPI"
    echo "    anticc-restart  Restart CLIProxyAPI"
    echo "    anticc-status   Check if running"
    echo "    anticc-logs     View logs"
    echo ""
    echo "  Models:"
    echo "    anticc-opus     Use Opus as main (default, best quality)"
    echo "    anticc-sonnet   Use Sonnet as main (faster)"
    echo "    anticc-show     Show current config"
    echo ""
    echo "  Accounts:"
    echo "    anticc-login    Add new Antigravity account"
    echo "    anticc-accounts List configured accounts"
    echo ""
    echo "  Claude Code Router:"
    echo "    ccr-code        Run Claude Code through router"
    echo "    ccr-ui          Open router web UI"
}

# ============================================================================
# CLAUDE CODE ROUTER INTEGRATION
# ============================================================================

# Start CLIProxyAPI and then run Claude Code through the router
ccr-start() {
    echo "Starting CLIProxyAPI backend..."
    anticc-up
    if [ $? -eq 0 ]; then
        echo ""
        echo "Starting Claude Code Router..."
        ccr start
    fi
}

# Run Claude Code through the router (ensures CLIProxyAPI is running)
ccr-code() {
    # Check if CLIProxyAPI is running
    if ! pgrep -f "CLIProxyAPI" > /dev/null; then
        echo "Starting CLIProxyAPI backend first..."
        anticc-up
        if [ $? -ne 0 ]; then
            echo "Failed to start CLIProxyAPI"
            return 1
        fi
        echo ""
    fi
    
    # Run Claude Code through the router
    ccr code "$@"
}

# Open Claude Code Router UI
alias ccr-ui='ccr ui'

# Edit Claude Code Router config
alias ccr-config='${EDITOR:-nano} "$CCR_CONFIG"'

# Restart Claude Code Router
alias ccr-restart='ccr restart'

# Silent load - use 'anticc-help' for commands, 'anticc-show' for current models