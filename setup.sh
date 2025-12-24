#!/bin/bash
# =============================================================================
# CLIProxyAPI + Antigravity Setup Script
# =============================================================================
# This script sets up everything needed to use Claude Code with Antigravity:
# 1. Installs CLIProxyAPI (via Homebrew on macOS, direct download on Linux/WSL)
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

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin*)    echo "macos" ;;
        Linux*)     echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)          echo "unknown" ;;
    esac
}

# Detect architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)   echo "amd64" ;;
        arm64|aarch64)  echo "arm64" ;;
        armv7l)         echo "arm" ;;
        *)              echo "unknown" ;;
    esac
}

OS=$(detect_os)
ARCH=$(detect_arch)

echo ""
echo "=============================================="
echo "  CLIProxyAPI + Antigravity Setup"
echo "=============================================="
echo "  OS: $OS, Arch: $ARCH"
echo "=============================================="
echo ""

# =============================================================================
# Step 1: Check/Install CLIProxyAPI
# =============================================================================
log "Checking CLIProxyAPI..."

# Check for either command name (CLIProxyAPI or cliproxyapi)
CLIPROXY_CMD=""
if command -v CLIProxyAPI &>/dev/null; then
    CLIPROXY_CMD="CLIProxyAPI"
elif command -v cliproxyapi &>/dev/null; then
    CLIPROXY_CMD="cliproxyapi"
fi

if [[ -n "$CLIPROXY_CMD" ]]; then
    log "CLIProxyAPI already installed: $($CLIPROXY_CMD --help 2>&1 | head -1 || echo 'unknown version')"
else
    case "$OS" in
        macos)
            if command -v brew &>/dev/null; then
                log "Installing CLIProxyAPI via Homebrew..."
                brew install router-for-me/tap/cliproxyapi
                CLIPROXY_CMD="cliproxyapi"
            else
                error "Homebrew not found. Please install CLIProxyAPI manually:"
                echo "  brew install router-for-me/tap/cliproxyapi"
                echo "  Or download from: https://github.com/router-for-me/CLIProxyAPI/releases"
                exit 1
            fi
            ;;
        linux)
            log "Installing CLIProxyAPI for Linux..."
            
            # Determine download URL based on architecture
            DOWNLOAD_ARCH="$ARCH"
            if [[ "$ARCH" == "amd64" ]]; then
                DOWNLOAD_ARCH="amd64"
            elif [[ "$ARCH" == "arm64" ]]; then
                DOWNLOAD_ARCH="arm64"
            else
                error "Unsupported architecture: $ARCH"
                echo "  Please download manually from: https://github.com/router-for-me/CLIProxyAPI/releases"
                exit 1
            fi
            
            # Get latest release version
            log "Fetching latest release..."
            LATEST_VERSION=$(curl -sL "https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || echo "")
            
            if [[ -z "$LATEST_VERSION" ]]; then
                warn "Could not determine latest version, using v6.6.42"
                LATEST_VERSION="v6.6.42"
            fi
            
            log "Latest version: $LATEST_VERSION"
            
            # Download URL
            DOWNLOAD_URL="https://github.com/router-for-me/CLIProxyAPI/releases/download/${LATEST_VERSION}/CLIProxyAPI_Linux_${DOWNLOAD_ARCH}.tar.gz"
            
            # Create temp directory
            TEMP_DIR=$(mktemp -d)
            trap "rm -rf $TEMP_DIR" EXIT
            
            log "Downloading from: $DOWNLOAD_URL"
            if curl -sL "$DOWNLOAD_URL" -o "$TEMP_DIR/cliproxyapi.tar.gz"; then
                log "Extracting..."
                tar -xzf "$TEMP_DIR/cliproxyapi.tar.gz" -C "$TEMP_DIR"
                
                # Find the binary
                BINARY_PATH=$(find "$TEMP_DIR" -name "CLIProxyAPI" -o -name "cliproxyapi" 2>/dev/null | head -1)
                
                if [[ -z "$BINARY_PATH" ]]; then
                    # Try looking for any executable
                    BINARY_PATH=$(find "$TEMP_DIR" -type f -executable 2>/dev/null | head -1)
                fi
                
                if [[ -n "$BINARY_PATH" && -f "$BINARY_PATH" ]]; then
                    # Install to /usr/local/bin or ~/.local/bin
                    if [[ -w "/usr/local/bin" ]]; then
                        INSTALL_DIR="/usr/local/bin"
                    else
                        INSTALL_DIR="$HOME/.local/bin"
                        mkdir -p "$INSTALL_DIR"
                    fi
                    
                    cp "$BINARY_PATH" "$INSTALL_DIR/cliproxyapi"
                    chmod +x "$INSTALL_DIR/cliproxyapi"
                    
                    # Also create CLIProxyAPI symlink for compatibility
                    ln -sf "$INSTALL_DIR/cliproxyapi" "$INSTALL_DIR/CLIProxyAPI" 2>/dev/null || true
                    
                    log "Installed to: $INSTALL_DIR/cliproxyapi"
                    
                    # Add to PATH if needed
                    if [[ "$INSTALL_DIR" == "$HOME/.local/bin" ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
                        warn "Please add ~/.local/bin to your PATH:"
                        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
                        export PATH="$HOME/.local/bin:$PATH"
                    fi
                    
                    CLIPROXY_CMD="cliproxyapi"
                else
                    error "Could not find CLIProxyAPI binary in downloaded archive"
                    exit 1
                fi
            else
                error "Failed to download CLIProxyAPI"
                echo "  Please download manually from: https://github.com/router-for-me/CLIProxyAPI/releases"
                exit 1
            fi
            ;;
        *)
            error "Unsupported OS: $OS"
            echo "  Please download CLIProxyAPI manually from: https://github.com/router-for-me/CLIProxyAPI/releases"
            exit 1
            ;;
    esac
fi

# Export the command name for use in anticc.sh
export CLIPROXY_CMD

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
            # Use different sed syntax for macOS vs Linux
            if [[ "$OS" == "macos" ]]; then
                sed -i '' "s/sk-your-api-key-here/$CLIPROXY_API_KEY/g" "$SCRIPT_DIR/config.yaml"
            else
                sed -i "s/sk-your-api-key-here/$CLIPROXY_API_KEY/g" "$SCRIPT_DIR/config.yaml"
            fi
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
    # Use the detected command name
    if [[ -n "$CLIPROXY_CMD" ]]; then
        "$CLIPROXY_CMD" --antigravity-login
    elif command -v cliproxyapi &>/dev/null; then
        cliproxyapi --antigravity-login
    elif command -v CLIProxyAPI &>/dev/null; then
        CLIProxyAPI --antigravity-login
    else
        error "CLIProxyAPI command not found!"
        exit 1
    fi
fi
