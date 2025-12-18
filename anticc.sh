#!/usr/bin/env bash
# ============================================================================
# anticc - Antigravity Claude Code CLI
# ============================================================================
# A unified script for running Claude Code with Antigravity/CLIProxyAPI backend.
#
# Usage:
#   Source in shell config:  source "/path/to/anticc.sh"
#   Run directly:            ./anticc.sh [command]
#
# Architecture:
#   Claude Code -> Middleware (8318) -> CLIProxyAPI (8317) -> Antigravity
#
# The middleware layer provides:
#   - Token counting (local estimation for /v1/messages/count_tokens)
#   - JSON Schema normalization for Gemini/MCP compatibility
# ============================================================================

# Detect script directory (works even when sourced)
if [[ -n "${BASH_SOURCE[0]}" ]]; then
    ANTICC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [[ -n "$0" ]]; then
    ANTICC_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# ============================================================================
# CONFIGURATION
# ============================================================================
export CLIPROXY_DIR="${CLIPROXY_DIR:-$ANTICC_SCRIPT_DIR}"
export CLIPROXY_CONFIG="${CLIPROXY_CONFIG:-$CLIPROXY_DIR/config.yaml}"
export CLIPROXY_API_KEY="${CLIPROXY_API_KEY:-sk-046ad23dfe424a369795433c1c9e0cc4f35a7d318c4e1716}"
export CLIPROXY_MIDDLEWARE="${CLIPROXY_MIDDLEWARE:-$CLIPROXY_DIR/middleware/cliproxy-middleware}"

# Ports
CLIPROXY_PORT=8317
MIDDLEWARE_PORT=8318

# Log files
CLIPROXY_LOG="/tmp/cliproxy.log"
MIDDLEWARE_LOG="/tmp/cliproxy-middleware.log"

# Claude Code Router (optional)
export CCR_CONFIG="${CCR_CONFIG:-$HOME/.claude-code-router/config.json}"

# ============================================================================
# ENVIRONMENT VARIABLES FOR CLAUDE CODE
# ============================================================================
# Point to middleware (8318) which proxies to CLIProxyAPI (8317)
export ANTHROPIC_BASE_URL="http://127.0.0.1:${MIDDLEWARE_PORT}"
export ANTHROPIC_API_KEY="$CLIPROXY_API_KEY"

# Antigravity Claude models (gemini- prefix required for Antigravity backend)
# Default: Opus as main driver for best quality
export ANTHROPIC_DEFAULT_OPUS_MODEL="${ANTHROPIC_DEFAULT_OPUS_MODEL:-gemini-claude-opus-4-5-thinking}"
export ANTHROPIC_DEFAULT_SONNET_MODEL="${ANTHROPIC_DEFAULT_SONNET_MODEL:-gemini-claude-opus-4-5-thinking}"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="${ANTHROPIC_DEFAULT_HAIKU_MODEL:-gemini-claude-sonnet-4-5}"

# ============================================================================
# COLORS (with fallback for non-color terminals)
# ============================================================================
if [[ -t 1 ]] && command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null) -ge 8 ]]; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    BOLD=$(tput bold)
    NC=$(tput sgr0)
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

_anticc_log() {
    echo -e "${GREEN}[anticc]${NC} $*"
}

_anticc_warn() {
    echo -e "${YELLOW}[anticc]${NC} $*" >&2
}

_anticc_error() {
    echo -e "${RED}[anticc]${NC} $*" >&2
}

_anticc_check_dependency() {
    local cmd="$1"
    local install_hint="$2"
    if ! command -v "$cmd" &>/dev/null; then
        _anticc_error "$cmd is not installed."
        [[ -n "$install_hint" ]] && echo "  Install: $install_hint"
        return 1
    fi
    return 0
}

_anticc_is_running() {
    local pattern="$1"
    pgrep -f "$pattern" >/dev/null 2>&1
}

_anticc_get_pid() {
    local pattern="$1"
    pgrep -f "$pattern" 2>/dev/null | head -1
}

_anticc_wait_for_url() {
    local url="$1"
    local max_attempts="${2:-20}"
    local auth_header="$3"

    for ((i=1; i<=max_attempts; i++)); do
        if [[ -n "$auth_header" ]]; then
            curl -sf "$url" -H "$auth_header" >/dev/null 2>&1 && return 0
        else
            curl -sf "$url" >/dev/null 2>&1 && return 0
        fi
        sleep 0.5
    done
    return 1
}

# ============================================================================
# CORE FUNCTIONS
# ============================================================================

# Start CLIProxyAPI and middleware
anticc-up() {
    local cliproxy_started=false
    local middleware_started=false

    # Check dependencies
    if ! _anticc_check_dependency "CLIProxyAPI" "brew install router-for-me/tap/cliproxyapi"; then
        return 1
    fi

    if ! _anticc_check_dependency "curl"; then
        return 1
    fi

    # Start CLIProxyAPI if not running
    if ! _anticc_is_running "CLIProxyAPI"; then
        _anticc_log "Starting CLIProxyAPI..."

        if [[ ! -f "$CLIPROXY_CONFIG" ]]; then
            _anticc_warn "Config not found: $CLIPROXY_CONFIG"
            _anticc_warn "Using default configuration"
        fi

        CLIProxyAPI --config "$CLIPROXY_CONFIG" > "$CLIPROXY_LOG" 2>&1 &

        if _anticc_wait_for_url "http://127.0.0.1:${CLIPROXY_PORT}/v1/models" 20 "Authorization: Bearer $CLIPROXY_API_KEY"; then
            _anticc_log "${GREEN}CLIProxyAPI ready${NC} on http://127.0.0.1:${CLIPROXY_PORT}"
            cliproxy_started=true
        else
            _anticc_error "CLIProxyAPI failed to start. Check: tail $CLIPROXY_LOG"
            return 1
        fi
    else
        _anticc_log "${GREEN}CLIProxyAPI already running${NC} (PID: $(_anticc_get_pid 'CLIProxyAPI'))"
    fi

    # Start middleware if not running
    if ! _anticc_is_running "cliproxy-middleware"; then
        _anticc_log "Starting middleware..."

        if [[ ! -x "$CLIPROXY_MIDDLEWARE" ]]; then
            _anticc_error "Middleware binary not found or not executable: $CLIPROXY_MIDDLEWARE"
            _anticc_warn "Build it with: cd $CLIPROXY_DIR/middleware && go build -o cliproxy-middleware ."
            return 1
        fi

        "$CLIPROXY_MIDDLEWARE" > "$MIDDLEWARE_LOG" 2>&1 &

        if _anticc_wait_for_url "http://127.0.0.1:${MIDDLEWARE_PORT}/health" 20; then
            _anticc_log "${GREEN}Middleware ready${NC} on http://127.0.0.1:${MIDDLEWARE_PORT}"
            _anticc_log "  Features: token counting, schema normalization"
            middleware_started=true
        else
            _anticc_error "Middleware failed to start. Check: tail $MIDDLEWARE_LOG"
            return 1
        fi
    else
        _anticc_log "${GREEN}Middleware already running${NC} (PID: $(_anticc_get_pid 'cliproxy-middleware'))"
    fi

    echo ""
    _anticc_log "Ready! Run ${BOLD}claude${NC} to start coding."
    return 0
}

# Stop all services
anticc-stop() {
    local stopped=false

    if _anticc_is_running "cliproxy-middleware"; then
        pkill -f "cliproxy-middleware" 2>/dev/null
        _anticc_log "Middleware stopped"
        stopped=true
    fi

    if _anticc_is_running "CLIProxyAPI"; then
        pkill -f "CLIProxyAPI" 2>/dev/null
        _anticc_log "CLIProxyAPI stopped"
        stopped=true
    fi

    if [[ "$stopped" == "false" ]]; then
        _anticc_log "No services were running"
    fi
}

# Restart all services
anticc-restart() {
    anticc-stop
    sleep 1
    anticc-up
}

# Show status of services
anticc-status() {
    echo "${BOLD}Service Status:${NC}"
    echo ""

    if _anticc_is_running "CLIProxyAPI"; then
        local pid=$(_anticc_get_pid 'CLIProxyAPI')
        echo "  CLIProxyAPI:  ${GREEN}running${NC} (PID: $pid) on port $CLIPROXY_PORT"
    else
        echo "  CLIProxyAPI:  ${RED}not running${NC}"
    fi

    if _anticc_is_running "cliproxy-middleware"; then
        local pid=$(_anticc_get_pid 'cliproxy-middleware')
        echo "  Middleware:   ${GREEN}running${NC} (PID: $pid) on port $MIDDLEWARE_PORT"
    else
        echo "  Middleware:   ${RED}not running${NC}"
    fi

    echo ""
    echo "${BOLD}Environment:${NC}"
    echo "  ANTHROPIC_BASE_URL: $ANTHROPIC_BASE_URL"
}

# Test connectivity
anticc-test() {
    echo "${BOLD}Testing connectivity...${NC}"
    echo ""

    # Test CLIProxyAPI
    if curl -sf "http://127.0.0.1:${CLIPROXY_PORT}/v1/models" -H "Authorization: Bearer $CLIPROXY_API_KEY" >/dev/null 2>&1; then
        echo "  CLIProxyAPI (${CLIPROXY_PORT}): ${GREEN}OK${NC}"
    else
        echo "  CLIProxyAPI (${CLIPROXY_PORT}): ${RED}FAILED${NC}"
    fi

    # Test Middleware
    if curl -sf "http://127.0.0.1:${MIDDLEWARE_PORT}/health" >/dev/null 2>&1; then
        echo "  Middleware (${MIDDLEWARE_PORT}):  ${GREEN}OK${NC}"
    else
        echo "  Middleware (${MIDDLEWARE_PORT}):  ${RED}FAILED${NC}"
    fi
}

# Show current model configuration
anticc-show() {
    echo "${BOLD}Current Model Configuration:${NC}"
    echo "  OPUS:   $ANTHROPIC_DEFAULT_OPUS_MODEL"
    echo "  SONNET: $ANTHROPIC_DEFAULT_SONNET_MODEL"
    echo "  HAIKU:  $ANTHROPIC_DEFAULT_HAIKU_MODEL"
    echo ""
    echo "${BOLD}API Endpoint:${NC}"
    echo "  $ANTHROPIC_BASE_URL"
}

# Switch to Opus as main (default - best quality)
anticc-opus() {
    export ANTHROPIC_DEFAULT_OPUS_MODEL="gemini-claude-opus-4-5-thinking"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="gemini-claude-opus-4-5-thinking"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="gemini-claude-sonnet-4-5"
    _anticc_log "Switched to ${BOLD}Opus${NC} as main driver (best quality)"
    anticc-show
}

# Switch to Sonnet as main (faster)
anticc-sonnet() {
    export ANTHROPIC_DEFAULT_OPUS_MODEL="gemini-claude-opus-4-5-thinking"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="gemini-claude-sonnet-4-5-thinking"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="gemini-claude-sonnet-4-5"
    _anticc_log "Switched to ${BOLD}Sonnet${NC} as main driver (faster)"
    anticc-show
}

# List available models from CLIProxyAPI
anticc-models() {
    if ! _anticc_is_running "CLIProxyAPI"; then
        _anticc_error "CLIProxyAPI is not running. Start with: anticc-up"
        return 1
    fi

    echo "${BOLD}Available Models:${NC}"
    curl -s "http://127.0.0.1:${CLIPROXY_PORT}/v1/models" \
        -H "Authorization: Bearer $CLIPROXY_API_KEY" | \
        python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for model in data.get('data', []):
        print(f\"  - {model.get('id', 'unknown')}\")
except Exception as e:
    print(f'  Error: {e}')
" 2>/dev/null || echo "  (Could not fetch model list)"
}

# List Antigravity accounts
anticc-accounts() {
    local auth_dir="$HOME/.cli-proxy-api"

    echo "${BOLD}Antigravity Accounts:${NC}"

    if [[ -d "$auth_dir" ]]; then
        local count=0
        for f in "$auth_dir"/antigravity-*.json; do
            if [[ -f "$f" ]]; then
                local email
                email=$(basename "$f" | sed 's/antigravity-//' | sed 's/.json//' | sed 's/_/@/g' | sed 's/@gmail/@gmail./')
                echo "  - $email"
                ((count++))
            fi
        done

        if [[ $count -eq 0 ]]; then
            echo "  ${YELLOW}No accounts configured${NC}"
            echo "  Add one with: anticc-login"
        fi
    else
        echo "  ${YELLOW}Auth directory not found${NC}"
        echo "  Add an account with: anticc-login"
    fi
}

# Add new Antigravity account
anticc-login() {
    _anticc_check_dependency "CLIProxyAPI" "brew install router-for-me/tap/cliproxyapi" || return 1

    _anticc_log "Opening browser for Antigravity OAuth login..."
    _anticc_log "Note: OAuth callback uses port 51121"
    echo ""
    CLIProxyAPI --antigravity-login
}

# Full initialization and status check
anticc-init() {
    echo "${BOLD}=== Antigravity Claude Code Setup ===${NC}"
    echo ""

    # Check accounts
    local auth_dir="$HOME/.cli-proxy-api"
    local account_count=0
    if [[ -d "$auth_dir" ]]; then
        account_count=$(ls -1 "$auth_dir"/antigravity-*.json 2>/dev/null | wc -l | tr -d ' ')
    fi

    if [[ $account_count -eq 0 ]]; then
        _anticc_warn "No Antigravity accounts found"
        echo "  Add one with: anticc-login"
        echo ""
    else
        _anticc_log "Found $account_count Antigravity account(s)"
    fi

    # Start services
    anticc-up || return 1

    echo ""
    anticc-show
    echo ""
    _anticc_log "Ready! Use ${BOLD}claude${NC} to start coding."
}

# Help
anticc-help() {
    cat << 'EOF'
Antigravity Claude Code (anticc) Commands:

  Quick Start:
    anticc-up       Start CLIProxyAPI + middleware, then use 'claude'
    anticc-init     Full setup with status check

  Services:
    anticc-up       Start CLIProxyAPI and middleware
    anticc-stop     Stop all services
    anticc-restart  Restart all services
    anticc-status   Check service status
    anticc-test     Test connectivity

  Logs:
    anticc-logs     View CLIProxyAPI logs
    anticc-mw-logs  View middleware logs

  Models:
    anticc-opus     Use Opus as main (default, best quality)
    anticc-sonnet   Use Sonnet as main (faster)
    anticc-show     Show current model configuration
    anticc-models   List available models from API

  Accounts:
    anticc-login    Add new Antigravity account
    anticc-accounts List configured accounts

  Configuration:
    anticc-dir      Go to project directory
    anticc-config   Edit config file

  Architecture:
    Claude Code -> Middleware (8318) -> CLIProxyAPI (8317) -> Antigravity

    Middleware provides:
      - Token counting (local estimation)
      - JSON Schema normalization for MCP/Gemini compatibility

  Claude Code Router (optional):
    ccr-code        Run Claude Code through router
    ccr-ui          Open router web UI
    ccr-start       Start CLIProxyAPI + router
EOF
}

# ============================================================================
# ALIASES (only defined when sourced, not when run directly)
# ============================================================================

if [[ "${BASH_SOURCE[0]}" != "${0}" ]] || [[ -n "$ZSH_EVAL_CONTEXT" && "$ZSH_EVAL_CONTEXT" =~ :file$ ]]; then
    # Script is being sourced - define aliases

    # Start CLIProxyAPI server (foreground)
    alias anticc='CLIProxyAPI --config "$CLIPROXY_CONFIG"'
    alias anticc-start='CLIProxyAPI --config "$CLIPROXY_CONFIG"'

    # Start in background
    alias anticc-bg='CLIProxyAPI --config "$CLIPROXY_CONFIG" > "$CLIPROXY_LOG" 2>&1 &'

    # View logs
    alias anticc-logs='tail -f /tmp/cliproxy.log'
    alias anticc-mw-logs='tail -f /tmp/cliproxy-middleware.log'

    # Add account (alias for login)
    alias anticc-add='anticc-login'

    # Directory and config
    alias anticc-dir='cd "$CLIPROXY_DIR"'
    alias anticc-config='${EDITOR:-${VISUAL:-nano}} "$CLIPROXY_CONFIG"'

    # Backward compatibility
    alias anticc-claude='anticc-opus'

    # ========================================================================
    # CLAUDE CODE ROUTER INTEGRATION (optional)
    # ========================================================================

    if command -v ccr &>/dev/null; then
        # Start CLIProxyAPI and then run Claude Code through the router
        ccr-start() {
            _anticc_log "Starting CLIProxyAPI backend..."
            anticc-up
            if [[ $? -eq 0 ]]; then
                echo ""
                _anticc_log "Starting Claude Code Router..."
                ccr start
            fi
        }

        # Run Claude Code through the router
        ccr-code() {
            if ! _anticc_is_running "cliproxy-middleware"; then
                _anticc_log "Starting CLIProxyAPI and middleware..."
                anticc-up || return 1
                echo ""
            fi
            ccr code "$@"
        }

        alias ccr-ui='ccr ui'
        alias ccr-config='${EDITOR:-${VISUAL:-nano}} "$CCR_CONFIG"'
        alias ccr-restart='ccr restart'
    fi
fi

# ============================================================================
# CLI MODE (when script is run directly, not sourced)
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being run directly
    case "${1:-help}" in
        up|start)
            anticc-up
            ;;
        stop)
            anticc-stop
            ;;
        restart)
            anticc-restart
            ;;
        status)
            anticc-status
            ;;
        test)
            anticc-test
            ;;
        init|setup)
            anticc-init
            ;;
        show)
            anticc-show
            ;;
        opus)
            anticc-opus
            ;;
        sonnet)
            anticc-sonnet
            ;;
        models)
            anticc-models
            ;;
        accounts)
            anticc-accounts
            ;;
        login|add)
            anticc-login
            ;;
        logs)
            tail -f "$CLIPROXY_LOG"
            ;;
        mw-logs|middleware-logs)
            tail -f "$MIDDLEWARE_LOG"
            ;;
        help|--help|-h|"")
            anticc-help
            ;;
        *)
            _anticc_error "Unknown command: $1"
            echo ""
            anticc-help
            exit 1
            ;;
    esac
fi
