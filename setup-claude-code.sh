#!/bin/bash

# ============================================================================
# Claude Code + CLIProxyAPI + Antigravity Setup Script
# ============================================================================
# This script configures Claude Code to use Antigravity models via CLIProxyAPI
#
# Available Antigravity Models:
#   - claude-sonnet-4-5 (Claude Sonnet 4.5)
#   - claude-sonnet-4-5-thinking (Claude Sonnet 4.5 with extended thinking)
#   - claude-opus-4-5-thinking (Claude Opus 4.5 with extended thinking)
#   - gemini-3-pro-high / gemini-3-pro-low (Gemini 3 Pro)
#   - gpt-oss-120b-medium (GPT-OSS 120B)
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Claude Code + Antigravity Setup${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Configuration
CLIPROXY_PORT=8317
CLIPROXY_URL="http://127.0.0.1:${CLIPROXY_PORT}"
API_KEY="sk-046ad23dfe424a369795433c1c9e0cc4f35a7d318c4e1716"

# Check if CLIProxyAPI is installed
if ! command -v CLIProxyAPI &> /dev/null; then
    echo -e "${RED}Error: CLIProxyAPI is not installed${NC}"
    echo "Install it via Homebrew: brew install router-for-me/tap/cliproxyapi"
    exit 1
fi

echo -e "${GREEN}✓ CLIProxyAPI found at: $(which CLIProxyAPI)${NC}"
echo -e "  Version: $(CLIProxyAPI --version 2>&1 | head -1)"
echo ""

# Function to add accounts
add_antigravity_accounts() {
    echo -e "${YELLOW}Adding Antigravity accounts...${NC}"
    echo "You'll need to authenticate with Google accounts that have Antigravity access."
    echo ""
    
    while true; do
        read -p "Do you want to add an Antigravity account? (y/n): " yn
        case $yn in
            [Yy]* )
                echo -e "${BLUE}Opening browser for OAuth login...${NC}"
                echo "Note: OAuth callback uses port 51121"
                CLIProxyAPI --antigravity-login
                echo -e "${GREEN}✓ Account added${NC}"
                echo ""
                ;;
            [Nn]* )
                break
                ;;
            * )
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Function to list existing accounts
list_accounts() {
    echo -e "${BLUE}Checking existing Antigravity accounts...${NC}"
    AUTH_DIR="${HOME}/.cli-proxy-api"
    
    if [ -d "$AUTH_DIR" ]; then
        ACCOUNTS=$(ls -1 "$AUTH_DIR"/antigravity-*.json 2>/dev/null | wc -l | tr -d ' ')
        if [ "$ACCOUNTS" -gt 0 ]; then
            echo -e "${GREEN}Found $ACCOUNTS Antigravity account(s):${NC}"
            for f in "$AUTH_DIR"/antigravity-*.json; do
                if [ -f "$f" ]; then
                    EMAIL=$(basename "$f" | sed 's/antigravity-//' | sed 's/.json//')
                    echo "  - $EMAIL"
                fi
            done
        else
            echo -e "${YELLOW}No Antigravity accounts found${NC}"
        fi
    else
        echo -e "${YELLOW}Auth directory not found. No accounts configured yet.${NC}"
    fi
    echo ""
}

# Function to setup environment variables
setup_env_vars() {
    echo -e "${BLUE}Setting up environment variables for Claude Code...${NC}"
    echo ""
    
    # Determine shell config file
    SHELL_CONFIG=""
    if [ -f "$HOME/.zshrc" ]; then
        SHELL_CONFIG="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        SHELL_CONFIG="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        SHELL_CONFIG="$HOME/.bash_profile"
    fi
    
    # Claude Code environment variables
    ENV_VARS="
# ============================================================================
# Claude Code + CLIProxyAPI + Antigravity Configuration
# Added by setup-claude-code.sh on $(date)
# ============================================================================

# CLIProxyAPI endpoint for Claude Code
export ANTHROPIC_BASE_URL=\"${CLIPROXY_URL}\"
export ANTHROPIC_AUTH_TOKEN=\"${API_KEY}\"

# Model configuration for Claude Code 2.x.x
# Using Antigravity Claude models
export ANTHROPIC_DEFAULT_OPUS_MODEL=\"claude-opus-4-5-thinking\"
export ANTHROPIC_DEFAULT_SONNET_MODEL=\"claude-sonnet-4-5\"
export ANTHROPIC_DEFAULT_HAIKU_MODEL=\"claude-sonnet-4-5\"

# Alternative: Using Gemini models
# export ANTHROPIC_DEFAULT_OPUS_MODEL=\"gemini-3-pro-high\"
# export ANTHROPIC_DEFAULT_SONNET_MODEL=\"gemini-3-pro-low\"
# export ANTHROPIC_DEFAULT_HAIKU_MODEL=\"gemini-3-pro-low\"

# For Claude Code 1.x.x (legacy)
# export ANTHROPIC_MODEL=\"claude-sonnet-4-5\"
# export ANTHROPIC_SMALL_FAST_MODEL=\"claude-sonnet-4-5\"
"
    
    echo "The following environment variables will be configured:"
    echo ""
    echo -e "${YELLOW}ANTHROPIC_BASE_URL${NC}=${CLIPROXY_URL}"
    echo -e "${YELLOW}ANTHROPIC_AUTH_TOKEN${NC}=${API_KEY}"
    echo -e "${YELLOW}ANTHROPIC_DEFAULT_OPUS_MODEL${NC}=claude-opus-4-5-thinking"
    echo -e "${YELLOW}ANTHROPIC_DEFAULT_SONNET_MODEL${NC}=claude-sonnet-4-5"
    echo -e "${YELLOW}ANTHROPIC_DEFAULT_HAIKU_MODEL${NC}=claude-sonnet-4-5"
    echo ""
    
    if [ -n "$SHELL_CONFIG" ]; then
        read -p "Add these to $SHELL_CONFIG? (y/n): " yn
        case $yn in
            [Yy]* )
                # Check if already configured
                if grep -q "ANTHROPIC_BASE_URL.*127.0.0.1:${CLIPROXY_PORT}" "$SHELL_CONFIG" 2>/dev/null; then
                    echo -e "${YELLOW}Environment variables already configured in $SHELL_CONFIG${NC}"
                else
                    echo "$ENV_VARS" >> "$SHELL_CONFIG"
                    echo -e "${GREEN}✓ Environment variables added to $SHELL_CONFIG${NC}"
                    echo -e "${YELLOW}Run 'source $SHELL_CONFIG' or restart your terminal to apply changes${NC}"
                fi
                ;;
            [Nn]* )
                echo ""
                echo "Add these manually to your shell config:"
                echo "$ENV_VARS"
                ;;
        esac
    else
        echo -e "${YELLOW}Could not detect shell config file${NC}"
        echo "Add these environment variables manually:"
        echo "$ENV_VARS"
    fi
    echo ""
}

# Function to start CLIProxyAPI
start_proxy() {
    echo -e "${BLUE}Starting CLIProxyAPI server...${NC}"
    
    CONFIG_FILE="$(pwd)/config.yaml"
    if [ ! -f "$CONFIG_FILE" ]; then
        CONFIG_FILE="/opt/homebrew/etc/cliproxyapi.conf"
    fi
    
    echo "Using config: $CONFIG_FILE"
    echo "Server will run on port $CLIPROXY_PORT"
    echo ""
    
    read -p "Start CLIProxyAPI now? (y/n): " yn
    case $yn in
        [Yy]* )
            echo -e "${GREEN}Starting CLIProxyAPI...${NC}"
            echo "Press Ctrl+C to stop"
            echo ""
            CLIProxyAPI --config "$CONFIG_FILE"
            ;;
        [Nn]* )
            echo ""
            echo "To start manually, run:"
            echo "  CLIProxyAPI --config $CONFIG_FILE"
            ;;
    esac
}

# Function to test the setup
test_setup() {
    echo -e "${BLUE}Testing CLIProxyAPI connection...${NC}"
    
    # Check if server is running
    if curl -s "${CLIPROXY_URL}/v1/models" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ CLIProxyAPI is running on ${CLIPROXY_URL}${NC}"
        
        # List available models
        echo ""
        echo "Available models:"
        curl -s "${CLIPROXY_URL}/v1/models" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for model in data.get('data', []):
        print(f\"  - {model.get('id', 'unknown')}\")
except:
    print('  Could not parse model list')
" 2>/dev/null || echo "  (Could not fetch model list)"
    else
        echo -e "${YELLOW}CLIProxyAPI is not running on ${CLIPROXY_URL}${NC}"
        echo "Start it with: CLIProxyAPI --config config.yaml"
    fi
    echo ""
}

# Main menu
main_menu() {
    echo ""
    echo "What would you like to do?"
    echo ""
    echo "  1) List existing Antigravity accounts"
    echo "  2) Add new Antigravity account"
    echo "  3) Setup Claude Code environment variables"
    echo "  4) Test CLIProxyAPI connection"
    echo "  5) Start CLIProxyAPI server"
    echo "  6) Full setup (all of the above)"
    echo "  7) Exit"
    echo ""
    
    read -p "Enter choice [1-7]: " choice
    
    case $choice in
        1) list_accounts; main_menu ;;
        2) add_antigravity_accounts; main_menu ;;
        3) setup_env_vars; main_menu ;;
        4) test_setup; main_menu ;;
        5) start_proxy ;;
        6)
            list_accounts
            add_antigravity_accounts
            setup_env_vars
            test_setup
            start_proxy
            ;;
        7) echo "Goodbye!"; exit 0 ;;
        *) echo -e "${RED}Invalid choice${NC}"; main_menu ;;
    esac
}

# Run main menu
main_menu