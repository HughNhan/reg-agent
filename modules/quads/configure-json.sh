#!/bin/bash
# QUADS module configuration - JSON-based
# Updates the 'quads' section in vars/config.json

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
echo -e "${BLUE}QUADS Module Configuration${NC}"
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

# Step 2: Read existing QUADS configuration
echo "Reading existing QUADS configuration..."
EXISTING_MODE=$(jq -r '.quads.mode // "allocate"' "$CONFIG_JSON")
EXISTING_API_SERVER=$(jq -r '.quads.api_server // ""' "$CONFIG_JSON")
EXISTING_USERNAME=$(jq -r '.quads.username // ""' "$CONFIG_JSON")
EXISTING_LAB=$(jq -r '.quads.lab // "scalelab"' "$CONFIG_JSON")
EXISTING_NUM_HOSTS=$(jq -r '.quads.num_hosts // "6"' "$CONFIG_JSON")
EXISTING_PREFERRED_MODEL=$(jq -r '.quads.preferred_model // "r750"' "$CONFIG_JSON")
EXISTING_WORKLOAD_NAME=$(jq -r '.quads.workload_name // ""' "$CONFIG_JSON")
EXISTING_WIPE_DISKS=$(jq -r '.quads.wipe_disks // "yes"' "$CONFIG_JSON")

# Check if QUADS appears to be configured
QUADS_CONFIGURED=false
if [ -n "$EXISTING_API_SERVER" ] && [ -n "$EXISTING_USERNAME" ]; then
    QUADS_CONFIGURED=true
    echo -e "${GREEN}✓ QUADS section exists in config.json${NC}"
    echo ""
    echo "Current values:"
    echo "  mode: $EXISTING_MODE"
    echo "  api_server: $EXISTING_API_SERVER"
    echo "  username: $EXISTING_USERNAME"
    echo "  lab: $EXISTING_LAB"
    echo "  num_hosts: $EXISTING_NUM_HOSTS"
    echo "  preferred_model: $EXISTING_PREFERRED_MODEL"
    echo "  workload_name: $EXISTING_WORKLOAD_NAME"
    echo "  wipe_disks: $EXISTING_WIPE_DISKS"
    echo ""
fi

# Step 3: Interactive prompts with keep/change option
echo -e "${BLUE}Configure QUADS settings (press Enter to keep current value):${NC}"
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

# Mode
echo "1. QUADS Mode"
echo "   allocate - Request new allocation"
echo "   import - Import existing allocation"
prompt_with_default "   Mode" "$EXISTING_MODE" NEW_MODE
echo ""

# API Server
echo "2. QUADS API Server"
prompt_with_default "   API Server" "$EXISTING_API_SERVER" NEW_API_SERVER
echo ""

# Username
echo "3. QUADS Username"
prompt_with_default "   Username" "$EXISTING_USERNAME" NEW_USERNAME
echo ""

# Password (don't show existing)
echo "4. QUADS Password"
read -sp "   Password (hidden): " NEW_PASSWORD
echo ""
echo ""

# Lab
echo "5. Lab"
echo "   scalelab or performancelab"
prompt_with_default "   Lab" "$EXISTING_LAB" NEW_LAB
echo ""

# Num hosts
echo "6. Number of Hosts"
prompt_with_default "   Num hosts" "$EXISTING_NUM_HOSTS" NEW_NUM_HOSTS
echo ""

# Preferred model
echo "7. Preferred Model"
echo "   e.g., r750, r740xd"
prompt_with_default "   Model" "$EXISTING_PREFERRED_MODEL" NEW_PREFERRED_MODEL
echo ""

# Workload name
echo "8. Workload Name"
prompt_with_default "   Workload name" "$EXISTING_WORKLOAD_NAME" NEW_WORKLOAD_NAME
echo ""

# Wipe disks
echo "9. Wipe Disks"
echo "   yes or no"
prompt_with_default "   Wipe disks" "$EXISTING_WIPE_DISKS" NEW_WIPE_DISKS
echo ""

# Lab SSH password (shared setting)
EXISTING_LAB_PASSWORD=$(jq -r '.lab.ssh_password // ""' "$CONFIG_JSON")
echo "10. Lab SSH Password (shared setting)"
echo "    Default password for SSH to lab machines"
read -sp "    Lab password (hidden): " NEW_LAB_PASSWORD
echo ""
if [ -z "$NEW_LAB_PASSWORD" ] && [ -n "$EXISTING_LAB_PASSWORD" ]; then
    NEW_LAB_PASSWORD="$EXISTING_LAB_PASSWORD"
fi
echo ""

# Step 4: Update config.json
echo -e "${BLUE}Updating config.json...${NC}"

# Create temporary file with updated QUADS and lab sections
jq --arg mode "$NEW_MODE" \
   --arg api_server "$NEW_API_SERVER" \
   --arg username "$NEW_USERNAME" \
   --arg password "$NEW_PASSWORD" \
   --arg lab "$NEW_LAB" \
   --argjson num_hosts "$NEW_NUM_HOSTS" \
   --arg model "$NEW_PREFERRED_MODEL" \
   --arg workload "$NEW_WORKLOAD_NAME" \
   --arg wipe "$NEW_WIPE_DISKS" \
   --arg lab_password "$NEW_LAB_PASSWORD" \
   '.quads.mode = $mode |
    .quads.api_server = $api_server |
    .quads.username = $username |
    .quads.password = $password |
    .quads.lab = $lab |
    .quads.num_hosts = $num_hosts |
    .quads.preferred_model = $model |
    .quads.workload_name = $workload |
    .quads.wipe_disks = $wipe |
    .lab.ssh_password = $lab_password' \
   "$CONFIG_JSON" > "${CONFIG_JSON}.tmp"

mv "${CONFIG_JSON}.tmp" "$CONFIG_JSON"

echo -e "${GREEN}✓ QUADS configuration saved to config.json${NC}"
echo ""
echo "Next steps:"
echo "  - Configure other modules (jetlag, crucible, regulus)"
echo "  - Or run: make deploy"
echo ""
