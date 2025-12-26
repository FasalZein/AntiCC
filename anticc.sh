#!/usr/bin/env bash
# ============================================================================
# anticc - Antigravity Claude Code CLI (Minimal Edition)
# ============================================================================
# Usage: source "/path/to/anticc.sh"
#
# Commands:
#   anticc-up     Start CLIProxyAPI + middleware
#   anticc-down   Stop all services
#   anticc-on     Enable Antigravity mode
#   anticc-off    Disable (use other providers)
#   anticc-status Check service status
# ============================================================================

# Detect script directory
if [[ -n "${BASH_SOURCE[0]}" ]]; then
    ANTICC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [[ -n "$ZSH_VERSION" ]]; then
    eval 'ANTICC_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"'
fi

# ============================================================================
# CONFIGURATION
# ============================================================================
ANTICC_CLIPROXY_PORT=8317
ANTICC_MIDDLEWARE_PORT=8318
ANTICC_CLIPROXY_LOG="/tmp/cliproxy.log"
ANTICC_MIDDLEWARE_LOG="/tmp/cliproxy-middleware.log"

export CLIPROXY_DIR="${CLIPROXY_DIR:-$ANTICC_DIR}"
export CLIPROXY_CONFIG="${CLIPROXY_CONFIG:-$CLIPROXY_DIR/config.yaml}"
export CLIPROXY_MIDDLEWARE="${CLIPROXY_MIDDLEWARE:-$CLIPROXY_DIR/middleware/cliproxy-middleware}"

# Load API key from .env if not set
[[ -z "$CLIPROXY_API_KEY" && -f "$CLIPROXY_DIR/.env" ]] && source "$CLIPROXY_DIR/.env"
export CLIPROXY_API_KEY="${CLIPROXY_API_KEY:-}"

# Internal settings (exported when anticc-on is called)
_ANTICC_BASE_URL="http://127.0.0.1:${ANTICC_MIDDLEWARE_PORT}"
_ANTICC_API_KEY="$CLIPROXY_API_KEY"

# Model configuration (Opus-focused)
_ANTICC_OPUS_MODEL="gemini-claude-opus-4-5-thinking"
_ANTICC_SONNET_MODEL="gemini-claude-sonnet-4-5-thinking"
_ANTICC_HAIKU_MODEL="gemini-claude-sonnet-4-5"

# Track state
ANTICC_ENABLED="${ANTICC_ENABLED:-false}"

# ============================================================================
# COLORS
# ============================================================================
if [[ -t 1 ]] && command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null) -ge 8 ]]; then
    _C_GREEN=$(tput setaf 2); _C_YELLOW=$(tput setaf 3)
    _C_RED=$(tput setaf 1); _C_BOLD=$(tput bold); _C_NC=$(tput sgr0)
else
    _C_GREEN=''; _C_YELLOW=''; _C_RED=''; _C_BOLD=''; _C_NC=''
fi

_log() { echo -e "${_C_GREEN}[anticc]${_C_NC} $*"; }
_warn() { echo -e "${_C_YELLOW}[anticc]${_C_NC} $*" >&2; }
_err() { echo -e "${_C_RED}[anticc]${_C_NC} $*" >&2; }

# ============================================================================
# UTILITIES
# ============================================================================
_get_cliproxy_cmd() {
    command -v CLIProxyAPI 2>/dev/null || command -v cliproxyapi 2>/dev/null || echo ""
}

_is_running() { pgrep -f "$1" >/dev/null 2>&1; }
_get_pid() { pgrep -f "$1" 2>/dev/null | head -1; }

_wait_for() {
    local url="$1" max="${2:-20}" auth="$3"
    for ((i=1; i<=max; i++)); do
        if [[ -n "$auth" ]]; then
            curl -sf "$url" -H "$auth" >/dev/null 2>&1 && return 0
        else
            curl -sf "$url" >/dev/null 2>&1 && return 0
        fi
        sleep 0.5
    done
    return 1
}

# ============================================================================
# CORE COMMANDS
# ============================================================================

# Enable Antigravity mode
anticc-on() {
    export ANTHROPIC_BASE_URL="$_ANTICC_BASE_URL"
    export ANTHROPIC_API_KEY="$_ANTICC_API_KEY"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="$_ANTICC_OPUS_MODEL"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="$_ANTICC_SONNET_MODEL"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="$_ANTICC_HAIKU_MODEL"
    export ANTICC_ENABLED="true"
    _log "Antigravity mode ${_C_GREEN}enabled${_C_NC}"
}

# Disable Antigravity mode
anticc-off() {
    unset ANTHROPIC_BASE_URL ANTHROPIC_API_KEY
    unset ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL
    export ANTICC_ENABLED="false"
    _log "Antigravity mode ${_C_YELLOW}disabled${_C_NC} - using default/other provider"
}

# Start services
anticc-up() {
    local cmd=$(_get_cliproxy_cmd)
    [[ -z "$cmd" ]] && { _err "CLIProxyAPI not installed"; return 1; }

    # Start CLIProxyAPI
    if ! _is_running "CLIProxyAPI" && ! _is_running "cliproxyapi"; then
        _log "Starting CLIProxyAPI..."
        "$cmd" --config "$CLIPROXY_CONFIG" > "$ANTICC_CLIPROXY_LOG" 2>&1 &
        if _wait_for "http://127.0.0.1:${ANTICC_CLIPROXY_PORT}/v1/models" 20 "Authorization: Bearer $CLIPROXY_API_KEY"; then
            _log "${_C_GREEN}CLIProxyAPI ready${_C_NC} on :${ANTICC_CLIPROXY_PORT}"
        else
            _err "CLIProxyAPI failed. Check: tail $ANTICC_CLIPROXY_LOG"
            return 1
        fi
    else
        _log "${_C_GREEN}CLIProxyAPI already running${_C_NC}"
    fi

    # Start Middleware
    if ! _is_running "cliproxy-middleware"; then
        _log "Starting Middleware..."
        [[ ! -x "$CLIPROXY_MIDDLEWARE" ]] && { _err "Middleware not found: $CLIPROXY_MIDDLEWARE"; return 1; }
        "$CLIPROXY_MIDDLEWARE" > "$ANTICC_MIDDLEWARE_LOG" 2>&1 &
        if _wait_for "http://127.0.0.1:${ANTICC_MIDDLEWARE_PORT}/health" 20; then
            _log "${_C_GREEN}Middleware ready${_C_NC} on :${ANTICC_MIDDLEWARE_PORT}"
        else
            _err "Middleware failed. Check: tail $ANTICC_MIDDLEWARE_LOG"
            return 1
        fi
    else
        _log "${_C_GREEN}Middleware already running${_C_NC}"
    fi

    anticc-on
    echo ""
    _log "Ready! Run ${_C_BOLD}claude${_C_NC} to start."
}

# Stop services
anticc-down() {
    local stopped=false
    _is_running "cliproxy-middleware" && { pkill -f "cliproxy-middleware"; _log "Middleware stopped"; stopped=true; }
    _is_running "CLIProxyAPI" && { pkill -f "CLIProxyAPI"; _log "CLIProxyAPI stopped"; stopped=true; }
    _is_running "cliproxyapi" && { pkill -f "cliproxyapi"; _log "CLIProxyAPI stopped"; stopped=true; }
    [[ "$stopped" == "false" ]] && _log "No services running"
}

# Show status
anticc-status() {
    echo "${_C_BOLD}Services:${_C_NC}"
    if _is_running "CLIProxyAPI" || _is_running "cliproxyapi"; then
        echo "  CLIProxyAPI:  ${_C_GREEN}running${_C_NC} (PID: $(_get_pid 'CLIProxyAPI' || _get_pid 'cliproxyapi'))"
    else
        echo "  CLIProxyAPI:  ${_C_RED}stopped${_C_NC}"
    fi
    if _is_running "cliproxy-middleware"; then
        echo "  Middleware:   ${_C_GREEN}running${_C_NC} (PID: $(_get_pid 'cliproxy-middleware'))"
    else
        echo "  Middleware:   ${_C_RED}stopped${_C_NC}"
    fi
    echo ""
    echo "${_C_BOLD}Mode:${_C_NC}"
    if [[ "$ANTICC_ENABLED" == "true" ]]; then
        echo "  Anticc: ${_C_GREEN}enabled${_C_NC} → $ANTHROPIC_BASE_URL"
    else
        echo "  Anticc: ${_C_YELLOW}disabled${_C_NC}"
    fi
}

# Backward compatibility
anticc-stop() { anticc-down; }
anticc-restart() { anticc-down; sleep 1; anticc-up; }

# Quick help
anticc-help() {
    cat << 'EOF'
anticc commands:
  anticc-up      Start services + enable Antigravity
  anticc-down    Stop all services
  anticc-on      Enable Antigravity mode
  anticc-off     Disable (use other providers)
  anticc-status  Check service status
  anticc-restart Restart services
EOF
}

# Logs
anticc-logs() { tail -f "$ANTICC_CLIPROXY_LOG"; }
anticc-mw-logs() { tail -f "$ANTICC_MIDDLEWARE_LOG"; }
