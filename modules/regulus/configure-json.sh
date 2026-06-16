#!/bin/bash
# Regulus module configuration - JSON-based
# Updates the 'regulus' section in vars/config.json

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
echo -e "${BLUE}Regulus Module Configuration${NC}"
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

# Step 2: Read existing Regulus configuration
echo "Reading existing Regulus configuration..."
EXISTING_INSTALL_SUBDIR=$(jq -r '.regulus.install_subdir // ""' "$CONFIG_JSON")
EXISTING_BASTION_USER=$(jq -r '.regulus.bastion_ssh_user // "root"' "$CONFIG_JSON")
EXISTING_JOBS=$(jq -r '.regulus.jobs // ""' "$CONFIG_JSON")
EXISTING_DURATION=$(jq -r '.regulus.duration // "60"' "$CONFIG_JSON")
EXISTING_TAG=$(jq -r '.regulus.tag // "REG-AGENT"' "$CONFIG_JSON")
EXISTING_NUM_SAMPLES=$(jq -r '.regulus.num_samples // "3"' "$CONFIG_JSON")
EXISTING_TEST_SUITE=$(jq -r '.regulus.test_suite // ""' "$CONFIG_JSON")

# Check if Regulus appears to be configured
REGULUS_CONFIGURED=false
if [ -n "$EXISTING_BASTION_USER" ]; then
    REGULUS_CONFIGURED=true
    echo -e "${GREEN}✓ Regulus section exists in config.json${NC}"
    echo ""
    echo "Current values:"
    echo "  install_subdir: $EXISTING_INSTALL_SUBDIR"
    echo "  bastion_ssh_user: $EXISTING_BASTION_USER"
    echo "  jobs: $EXISTING_JOBS"
    echo "  duration: $EXISTING_DURATION"
    echo "  tag: $EXISTING_TAG"
    echo "  num_samples: $EXISTING_NUM_SAMPLES"
    echo "  test_suite: $EXISTING_TEST_SUITE"
    echo ""
fi

# Step 3: Interactive prompts with keep/change option
echo -e "${BLUE}Configure Regulus settings (press Enter to keep current value):${NC}"
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

# Install subdirectory
echo "1. Installation Subdirectory"
echo "   Optional subdirectory under /root/ for Regulus installation"
echo "   Leave empty for /root/cpt-regulus-<timestamp>"
prompt_with_default "   Subdir" "$EXISTING_INSTALL_SUBDIR" NEW_INSTALL_SUBDIR
echo ""

# Bastion SSH user
echo "2. Bastion SSH User"
prompt_with_default "   SSH user" "$EXISTING_BASTION_USER" NEW_BASTION_USER
echo ""

# Jobs
echo "3. Test Jobs"
echo "   Space-separated list of test job paths"
echo "   e.g., ./SANDBOX or ./1_GROUP/NO-PAO/4IP"
prompt_with_default "   Jobs" "$EXISTING_JOBS" NEW_JOBS
echo ""

# Duration
echo "4. Test Duration (seconds)"
prompt_with_default "   Duration" "$EXISTING_DURATION" NEW_DURATION
echo ""

# Tag
echo "5. Test Tag/Identifier"
prompt_with_default "   Tag" "$EXISTING_TAG" NEW_TAG
echo ""

# Num samples
echo "6. Number of Samples"
echo "   How many times to run each test"
prompt_with_default "   Num samples" "$EXISTING_NUM_SAMPLES" NEW_NUM_SAMPLES
echo ""

# Test suite
echo "7. Test Suite Name (optional)"
prompt_with_default "   Test suite" "$EXISTING_TEST_SUITE" NEW_TEST_SUITE
echo ""

# Step 4: Update config.json
echo -e "${BLUE}Updating config.json...${NC}"

# Create temporary file with updated Regulus section
jq --arg install_subdir "$NEW_INSTALL_SUBDIR" \
   --arg bastion_user "$NEW_BASTION_USER" \
   --arg jobs "$NEW_JOBS" \
   --argjson duration "$NEW_DURATION" \
   --arg tag "$NEW_TAG" \
   --argjson num_samples "$NEW_NUM_SAMPLES" \
   --arg test_suite "$NEW_TEST_SUITE" \
   '.regulus.install_subdir = $install_subdir |
    .regulus.bastion_ssh_user = $bastion_user |
    .regulus.jobs = $jobs |
    .regulus.duration = $duration |
    .regulus.tag = $tag |
    .regulus.num_samples = $num_samples |
    .regulus.test_suite = $test_suite' \
   "$CONFIG_JSON" > "${CONFIG_JSON}.tmp"

mv "${CONFIG_JSON}.tmp" "$CONFIG_JSON"

echo -e "${GREEN}✓ Regulus configuration saved to config.json${NC}"
echo ""
echo "Configuration complete!"
echo ""
echo "Next: make deploy"
echo ""
