#!/bin/bash
# Crucible module configuration - JSON-based
# Updates the 'crucible' and 'crucible_controller' sections in vars/config.json

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG_AGENT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VARS_DIR="${REG_AGENT_ROOT}/vars"
CONFIG_JSON="${VARS_DIR}/config.json"
TEMPLATE_JSON="${VARS_DIR}/config.json.template"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

# Ensure jq is available
if ! command -v jq &> /dev/null; then
    echo -e "${RED}ERROR: jq is required${NC}"
    echo "Install: sudo dnf install -y jq"
    exit 1
fi

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Crucible Module Configuration${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Step 1: Ensure config.json exists
if [ ! -f "$CONFIG_JSON" ]; then
    echo -e "${YELLOW}config.json not found. Creating from template...${NC}"
    if [ ! -f "$TEMPLATE_JSON" ]; then
        echo -e "${RED}ERROR: Template not found at $TEMPLATE_JSON${NC}"
        exit 1
    fi
    cp "$TEMPLATE_JSON" "$CONFIG_JSON"
    echo -e "${GREEN}✓ Created $CONFIG_JSON${NC}"
    echo ""
fi

# Step 2: Read existing Crucible configuration
echo "Reading existing Crucible configuration..."
EXISTING_GIT_REPO=$(jq -r '.crucible.git_repo // "https://github.com/perftool-incubator/crucible.git"' "$CONFIG_JSON")
EXISTING_GIT_BRANCH=$(jq -r '.crucible.git_branch // "master"' "$CONFIG_JSON")
EXISTING_INSTALL_SCRIPT=$(jq -r '.crucible.install_script // "rh-install-crucible.sh"' "$CONFIG_JSON")
EXISTING_CONTROLLER_TARGET=$(jq -r '.crucible_controller.target // "bastion"' "$CONFIG_JSON")
EXISTING_CONTROLLER_USER=$(jq -r '.crucible_controller.user // "root"' "$CONFIG_JSON")

# Check if Crucible appears to be configured
CRUCIBLE_CONFIGURED=false
if [ -n "$EXISTING_GIT_REPO" ]; then
    CRUCIBLE_CONFIGURED=true
    echo -e "${GREEN}✓ Crucible section exists in config.json${NC}"
    echo ""
    echo "Current values:"
    echo "  git_repo: $EXISTING_GIT_REPO"
    echo "  git_branch: $EXISTING_GIT_BRANCH"
    echo "  install_script: $EXISTING_INSTALL_SCRIPT"
    echo "  controller_target: $EXISTING_CONTROLLER_TARGET"
    echo "  controller_user: $EXISTING_CONTROLLER_USER"
    echo ""
fi

# Step 3: Interactive prompts with keep/change option
echo -e "${BLUE}Configure Crucible settings (press Enter to keep current value):${NC}"
echo ""

# Helper function to prompt with existing value
prompt_with_default() {
    local prompt="$1"
    local current="$2"
    local var_name="$3"

    if [ -n "$current" ]; then
        read -p "$prompt [$current]: " value
        if [ -z "$value" ]; then
            value="$current"
        fi
    else
        read -p "$prompt: " value
    fi

    eval "$var_name='$value'"
}

# Git repo
echo "1. Crucible Git Repository"
prompt_with_default "   Git repo" "$EXISTING_GIT_REPO" NEW_GIT_REPO
echo ""

# Git branch
echo "2. Crucible Git Branch"
prompt_with_default "   Git branch" "$EXISTING_GIT_BRANCH" NEW_GIT_BRANCH
echo ""

# Install script
echo "3. Installation Script Name"
prompt_with_default "   Install script" "$EXISTING_INSTALL_SCRIPT" NEW_INSTALL_SCRIPT
echo ""

# Controller target
echo "4. Controller Target"
echo "   bastion - Install on bastion host from Jetlag"
echo "   other - Install on custom host"
prompt_with_default "   Target" "$EXISTING_CONTROLLER_TARGET" NEW_CONTROLLER_TARGET
echo ""

# Controller user
echo "5. Controller SSH User"
prompt_with_default "   SSH user" "$EXISTING_CONTROLLER_USER" NEW_CONTROLLER_USER
echo ""

# Step 4: Update config.json
echo -e "${BLUE}Updating config.json...${NC}"

# Create temporary file with updated Crucible sections
jq --arg git_repo "$NEW_GIT_REPO" \
   --arg git_branch "$NEW_GIT_BRANCH" \
   --arg install_script "$NEW_INSTALL_SCRIPT" \
   --arg target "$NEW_CONTROLLER_TARGET" \
   --arg user "$NEW_CONTROLLER_USER" \
   '.crucible.git_repo = $git_repo |
    .crucible.git_branch = $git_branch |
    .crucible.install_script = $install_script |
    .crucible_controller.target = $target |
    .crucible_controller.user = $user' \
   "$CONFIG_JSON" > "${CONFIG_JSON}.tmp"

mv "${CONFIG_JSON}.tmp" "$CONFIG_JSON"

echo -e "${GREEN}✓ Crucible configuration saved to config.json${NC}"
echo ""
echo "Next steps:"
echo "  - Configure Regulus module"
echo "  - Or run: make deploy"
echo ""
