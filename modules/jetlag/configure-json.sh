#!/bin/bash
# Jetlag module configuration - JSON-based
# Updates the 'jetlag' section in vars/config.json

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
echo -e "${BLUE}Jetlag Module Configuration${NC}"
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

# Step 2: Read existing Jetlag configuration
echo "Reading existing Jetlag configuration..."
EXISTING_CLUSTER_TYPE=$(jq -r '.jetlag.cluster_type // "mno"' "$CONFIG_JSON")
EXISTING_WORKER_COUNT=$(jq -r '.jetlag.worker_node_count // "3"' "$CONFIG_JSON")
EXISTING_OCP_BUILD=$(jq -r '.jetlag.ocp_build // "ga"' "$CONFIG_JSON")
EXISTING_OCP_VERSION=$(jq -r '.jetlag.ocp_version // "latest-4.20"' "$CONFIG_JSON")
EXISTING_NETWORK_STACK=$(jq -r '.jetlag.network_stack // "ipv4"' "$CONFIG_JSON")
EXISTING_PULL_SECRET=$(jq -r '.jetlag.pull_secret_path // ""' "$CONFIG_JSON")
EXISTING_BASTION=$(jq -r '.jetlag.bastion_host // ""' "$CONFIG_JSON")
EXISTING_KUBECONFIG=$(jq -r '.jetlag.kubeconfig_path // "/root/mno/kubeconfig"' "$CONFIG_JSON")

# Check if Jetlag appears to be configured
JETLAG_CONFIGURED=false
if [ -n "$EXISTING_CLUSTER_TYPE" ]; then
    JETLAG_CONFIGURED=true
    echo -e "${GREEN}✓ Jetlag section exists in config.json${NC}"
    echo ""
    echo "Current values:"
    echo "  cluster_type: $EXISTING_CLUSTER_TYPE"
    echo "  worker_node_count: $EXISTING_WORKER_COUNT"
    echo "  ocp_build: $EXISTING_OCP_BUILD"
    echo "  ocp_version: $EXISTING_OCP_VERSION"
    echo "  network_stack: $EXISTING_NETWORK_STACK"
    echo "  pull_secret_path: $EXISTING_PULL_SECRET"
    echo "  bastion_host: $EXISTING_BASTION"
    echo "  kubeconfig_path: $EXISTING_KUBECONFIG"
    echo ""
fi

# Step 3: Interactive prompts with keep/change option
echo -e "${BLUE}Configure Jetlag settings (press Enter to keep current value):${NC}"
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

# Cluster type
echo "1. Cluster Type"
echo "   mno - Multi-Node OpenShift (3 control + N workers)"
echo "   sno - Single-Node OpenShift"
prompt_with_default "   Cluster type" "$EXISTING_CLUSTER_TYPE" NEW_CLUSTER_TYPE
echo ""

# Worker count (for MNO)
if [ "$NEW_CLUSTER_TYPE" = "mno" ]; then
    echo "2. Worker Node Count"
    prompt_with_default "   Worker count" "$EXISTING_WORKER_COUNT" NEW_WORKER_COUNT
    echo ""
else
    NEW_WORKER_COUNT="0"
fi

# OCP Build
echo "3. OpenShift Build Type"
echo "   ga - General Availability (stable)"
echo "   dev - Development builds"
echo "   ci - CI builds"
prompt_with_default "   OCP build" "$EXISTING_OCP_BUILD" NEW_OCP_BUILD
echo ""

# OCP Version
echo "4. OpenShift Version"
echo "   e.g., latest-4.20, 4.18.1"
prompt_with_default "   OCP version" "$EXISTING_OCP_VERSION" NEW_OCP_VERSION
echo ""

# Network stack
echo "5. Network Stack"
echo "   ipv4, ipv6, dual"
prompt_with_default "   Network stack" "$EXISTING_NETWORK_STACK" NEW_NETWORK_STACK
echo ""

# Pull secret
echo "6. Pull Secret Path"
echo "   Path to OpenShift pull secret file"
prompt_with_default "   Pull secret path" "$EXISTING_PULL_SECRET" NEW_PULL_SECRET
echo ""

# For cluster-ready mode
echo "7. Bastion Host (leave empty for new deployment)"
prompt_with_default "   Bastion host" "$EXISTING_BASTION" NEW_BASTION
echo ""

echo "8. Kubeconfig Path"
prompt_with_default "   Kubeconfig path" "$EXISTING_KUBECONFIG" NEW_KUBECONFIG
echo ""

# Step 4: Update config.json
echo -e "${BLUE}Updating config.json...${NC}"

# Create temporary file with updated Jetlag section
jq --arg cluster_type "$NEW_CLUSTER_TYPE" \
   --argjson worker_count "$NEW_WORKER_COUNT" \
   --arg ocp_build "$NEW_OCP_BUILD" \
   --arg ocp_version "$NEW_OCP_VERSION" \
   --arg network_stack "$NEW_NETWORK_STACK" \
   --arg pull_secret "$NEW_PULL_SECRET" \
   --arg bastion "$NEW_BASTION" \
   --arg kubeconfig "$NEW_KUBECONFIG" \
   '.jetlag.cluster_type = $cluster_type |
    .jetlag.worker_node_count = $worker_count |
    .jetlag.ocp_build = $ocp_build |
    .jetlag.ocp_version = $ocp_version |
    .jetlag.network_stack = $network_stack |
    .jetlag.pull_secret_path = $pull_secret |
    .jetlag.bastion_host = $bastion |
    .jetlag.kubeconfig_path = $kubeconfig' \
   "$CONFIG_JSON" > "${CONFIG_JSON}.tmp"

mv "${CONFIG_JSON}.tmp" "$CONFIG_JSON"

echo -e "${GREEN}✓ Jetlag configuration saved to config.json${NC}"
echo ""
echo "Next steps:"
echo "  - Configure other modules (crucible, regulus)"
echo "  - Or run: make deploy"
echo ""
