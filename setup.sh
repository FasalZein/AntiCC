#!/bin/bash
# =============================================================================
# CLIProxyAPI + Antigravity Setup Script
# =============================================================================
# This script sets up everything needed to use Claude Code with Antigravity:
# 1. Installs CLIProxyAPI (via Homebrew)
# 2. Builds the middleware (requires Go)
# 3. Creates config files from examples
# 4. Generates an API key
# 5. Adds shell configuration to your terminal
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[setup]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
error() { echo -e "${RED}[error]${NC} $*"; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "=============================================="
echo "  CLIProxyAPI + Antigravity Setup"
echo "=============================================="
echo ""

# =============================================================================
# Step 1: Check/Install CLIProxyAPI
# =============================================================================
log "Checking CLIProxyAPI..."

if command -v CLIProxyAPI &>/dev/null; then
    log "CLIProxyAPI already installed: $(CLIProxyAPI --version 2>/dev/null || echo 'unknown version')"
else
    if command -v brew &>/dev/null; then
        log "Installing CLIProxyAPI via Homebrew..."
        brew install router-for-me/tap/cliproxyapi
    else
        error "Homebrew not found. Please install CLIProxyAPI manually:"
        echo "  brew install router-for-me/tap/cliproxyapi"
        echo "  Or download from: https://github.com/router-for-me/CLIProxyAPI/releases"
        exit 1
    fi
fi

# =============================================================================
# Step 2: Build Middleware
# =============================================================================
log "Building middleware..."

if [[ -f "$SCRIPT_DIR/middleware/cliproxy-middleware" ]]; then
    log "Middleware already built"
else
    if command -v go &>/dev/null; then
        cd "$SCRIPT_DIR/middleware"
        go build -o cliproxy-middleware .
        cd "$SCRIPT_DIR"
        log "Middleware built successfully"
    else
        warn "Go not installed. Middleware will not be available."
        warn "MCP servers may not work without middleware."
        warn "Install Go from: https://go.dev/dl/"
    fi
fi

# =============================================================================
# Step 3: Create Config Files
# =============================================================================
log "Setting up configuration..."

# Generate API key if needed
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    log ".env already exists"
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
else
    API_KEY="sk-$(openssl rand -hex 24)"
    echo "CLIPROXY_API_KEY=\"$API_KEY\"" > "$SCRIPT_DIR/.env"
    log "Generated new API key in .env"
    CLIPROXY_API_KEY="$API_KEY"
fi

# Create config.yaml from example
if [[ -f "$SCRIPT_DIR/config.yaml" ]]; then
    log "config.yaml already exists"
else
    if [[ -f "$SCRIPT_DIR/config.example.yaml" ]]; then
        cp "$SCRIPT_DIR/config.example.yaml" "$SCRIPT_DIR/config.yaml"
        # Replace placeholder with actual key
        if [[ -n "$CLIPROXY_API_KEY" ]]; then
            sed -i.bak "s/sk-your-api-key-here/$CLIPROXY_API_KEY/g" "$SCRIPT_DIR/config.yaml"
            rm -f "$SCRIPT_DIR/config.yaml.bak"
        fi
        log "Created config.yaml from example"
    else
        error "config.example.yaml not found!"
        exit 1
    fi
fi

# =============================================================================
# Step 4: Add to Shell Configuration
# =============================================================================
log "Setting up shell configuration..."

# Detect shell
SHELL_NAME=$(basename "$SHELL")
case "$SHELL_NAME" in
    zsh)  SHELL_RC="$HOME/.zshrc" ;;
    bash) SHELL_RC="$HOME/.bashrc" ;;
    *)    SHELL_RC="$HOME/.${SHELL_NAME}rc" ;;
esac

# Source line to add
SOURCE_LINE="source \"$SCRIPT_DIR/anticc.sh\""
MARKER="# Antigravity Claude Code (anticc)"

# Check if already added
if [[ -f "$SHELL_RC" ]] && grep -q "anticc.sh" "$SHELL_RC"; then
    log "Shell config already set up in $SHELL_RC"
else
    echo "" >> "$SHELL_RC"
    echo "$MARKER" >> "$SHELL_RC"
    echo "$SOURCE_LINE" >> "$SHELL_RC"
    log "Added to $SHELL_RC"
fi

# =============================================================================
# Step 5: Login to Antigravity
# =============================================================================
echo ""
log "Setup complete!"
echo ""
echo "=============================================="
echo "  Next Steps"
echo "=============================================="
echo ""
echo "1. Reload your shell:"
echo "   ${BLUE}source $SHELL_RC${NC}"
echo ""
echo "2. Login to Antigravity (opens browser):"
echo "   ${BLUE}anticc-login${NC}"
echo ""
echo "3. Start the proxy and use Claude Code:"
echo "   ${BLUE}anticc-up${NC}"
echo "   ${BLUE}claude${NC}"
echo ""
echo "Optional: Add more Google accounts for higher rate limits:"
echo "   ${BLUE}anticc-login${NC}  (repeat for each account)"
echo ""
echo "=============================================="
echo ""

# Ask if they want to login now
read -r -p "Would you like to login to Antigravity now? [y/N] " response
if [[ "$response" =~ ^[Yy]$ ]]; then
    # Source the script first
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/anticc.sh"
    CLIProxyAPI --antigravity-login
fi
