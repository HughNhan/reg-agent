#!/bin/bash
# Phase 2: Jetlag Cluster Deployment
# Uses Jetlag playbooks directly to deploy OpenShift cluster

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG_AGENT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Source configuration
if [ ! -f "${REG_AGENT_ROOT}/vars/config.json" ]; then
    echo -e "${RED}Error: Configuration not found${NC}"
    echo "Run: make configure"
    exit 1
fi
# Load JSON configuration
source "${REG_AGENT_ROOT}/modules/lib/json-config.sh"
json_export_env ".jetlag" ""
json_export_env ".lab" "LAB"

# Source state
if [ ! -f "${REG_AGENT_ROOT}/vars/state.env" ]; then
    echo -e "${RED}Error: State file not found${NC}"
    echo "This should be created by Phase 1 (QUADS allocation)"
    exit 1
fi
source "${REG_AGENT_ROOT}/vars/state.env"

# Load dependency checking library
source "${REG_AGENT_ROOT}/modules/lib/check-dependencies.sh"

# Load logging library
source "${REG_AGENT_ROOT}/modules/lib/logging.sh"
init_logging "jetlag" "phase-2-jetlag-deploy"

JETLAG_REPO="${REG_AGENT_ROOT}/repos/jetlag"

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Phase 2: Jetlag Cluster Deployment${NC}"
log "========================================"
log "Phase 2: Jetlag Cluster Deployment"
log "========================================"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Check for existing deployment
if [ -n "$BASTION_HOST" ] && [ -n "$KUBECONFIG_PATH" ]; then
    echo "Checking for existing cluster deployment..."
    log "Checking for existing cluster deployment..."
    log "  BASTION_HOST: ${BASTION_HOST}"
    log "  KUBECONFIG_PATH: ${KUBECONFIG_PATH}"

    # Test if we can access the cluster
    CLUSTER_CHECK=$(ssh root@${BASTION_HOST} "[ -f ${KUBECONFIG_PATH} ] && export KUBECONFIG=${KUBECONFIG_PATH} && oc get nodes --no-headers 2>/dev/null | wc -l" 2>/dev/null || echo "0")

    if [ "$CLUSTER_CHECK" != "0" ] && [ "$CLUSTER_CHECK" != "" ]; then
        echo -e "${GREEN}✓ Found existing cluster with ${CLUSTER_CHECK} nodes${NC}"
        echo ""
        echo "Cluster is already deployed:"
        ssh root@${BASTION_HOST} "export KUBECONFIG=${KUBECONFIG_PATH} && oc get nodes" || true
        echo ""
        log "Found existing cluster with ${CLUSTER_CHECK} nodes"

        # Get cluster info
        CLUSTER_INFO=$(ssh root@${BASTION_HOST} "export KUBECONFIG=${KUBECONFIG_PATH} && oc version 2>/dev/null | grep 'Server Version' || echo 'Version unknown'" 2>/dev/null || echo "")
        if [ -n "$CLUSTER_INFO" ]; then
            echo "$CLUSTER_INFO"
            log "$CLUSTER_INFO"
        fi

        echo ""
        echo -e "${YELLOW}=========================================${NC}"
        echo -e "${YELLOW}Existing Deployment Found${NC}"
        echo -e "${YELLOW}=========================================${NC}"
        echo ""
        echo "A cluster is already deployed on this allocation."
        echo ""
        echo "Options:"
        echo "  1. Skip deployment and use existing cluster (recommended)"
        echo "  2. Force re-deployment (will destroy existing cluster)"
        echo ""

        # Check for force flag
        if [ "${FORCE_REDEPLOY}" = "true" ]; then
            echo -e "${RED}FORCE_REDEPLOY=true detected - will re-deploy${NC}"
            log "FORCE_REDEPLOY=true - proceeding with re-deployment"
        else
            echo -e "${GREEN}Using existing cluster (set FORCE_REDEPLOY=true to override)${NC}"
            echo ""
            log "Skipping deployment - using existing cluster"
            log "Kubeconfig: ${KUBECONFIG_PATH}"
            log "Bastion: ${BASTION_HOST}"

            echo "========================================="
            echo "✅ Phase 2: Using Existing Cluster"
            echo "========================================="
            echo "Bastion: ${BASTION_HOST}"
            echo "Kubeconfig: ${KUBECONFIG_PATH}"
            echo "Nodes: ${CLUSTER_CHECK}"
            echo ""
            echo "To force re-deployment: FORCE_REDEPLOY=true make jetlag-deploy"
            echo ""

            log "========================================"
            log "✅ Phase 2: Using Existing Cluster"
            log "========================================"
            log "Bastion: ${BASTION_HOST}"
            log "Kubeconfig: ${KUBECONFIG_PATH}"
            log "Nodes: ${CLUSTER_CHECK}"
            log "To force: FORCE_REDEPLOY=true"
            log "========================================"

            exit 0
        fi
    else
        echo "No existing cluster found - proceeding with deployment"
        log "No existing cluster found - proceeding with deployment"
    fi
    echo ""
fi

# Check dependencies
echo "Checking Phase 2 dependencies..."
echo ""
reset_dep_check

# Repository dependencies
check_repo "jetlag"

# Required state variables from Phase 1
check_var "Cloud name" "CLOUD_NAME"
check_var "Lab" "LAB"

# Required configuration variables
check_var "Cluster type" "CLUSTER_TYPE"
check_var "OCP build" "OCP_BUILD"
check_var "OCP version" "OCP_VERSION"
check_var "Network stack" "NETWORK_STACK"

# Worker count for MNO clusters
if [ "$CLUSTER_TYPE" = "mno" ]; then
    check_var "Worker node count" "WORKER_NODE_COUNT"
fi

# Pull secret file
if [ -f "${REG_AGENT_ROOT}/pull-secret.txt" ]; then
    check_file "Pull secret" "${REG_AGENT_ROOT}/pull-secret.txt"
elif [ -n "$PULL_SECRET_PATH" ] && [ -f "$PULL_SECRET_PATH" ]; then
    check_file "Pull secret" "$PULL_SECRET_PATH"
else
    echo -e "${RED}✗${NC} Pull secret file not found"
    echo "   Expected at: ${REG_AGENT_ROOT}/pull-secret.txt or \$PULL_SECRET_PATH"
    FAILED_DEPS+=("file:pull-secret.txt")
    ((DEPS_FAILED++))
fi

# Required commands
check_command "Ansible playbook" "ansible-playbook"
check_command "Sed" "sed"
check_command "Awk" "awk"
check_command "Grep" "grep"

# Summarize and fail if dependencies not met
if ! summarize_deps "Phase 2: Jetlag Deployment"; then
    exit 1
fi

echo ""
echo "Cloud: $CLOUD_NAME"
echo "Lab: $LAB"
echo "Cluster Type: $CLUSTER_TYPE"
echo "OCP Version: $OCP_VERSION"
echo ""

# Verify Jetlag is bootstrapped
if [ ! -d "${JETLAG_REPO}/.ansible" ]; then
    echo "Bootstrapping Jetlag..."
    cd "$JETLAG_REPO"
    ./bootstrap.sh
    cd "$REG_AGENT_ROOT"
fi

# Generate Jetlag all.yml configuration
echo "Generating Jetlag configuration..."

cd "$JETLAG_REPO"

# Copy template
cp ansible/vars/all.sample.yml ansible/vars/all.yml

# Helper function for safe sed
sedi() {
    local expr="$1"
    local file="$2"
    sed "$expr" "$file" > "${file}.tmp~" && mv "${file}.tmp~" "$file"
}

# Configure basic settings
sedi "s/^lab:$/lab: ${LAB}/" ansible/vars/all.yml
sedi "s/^lab_cloud:$/lab_cloud: ${CLOUD_NAME}/" ansible/vars/all.yml
sedi "s/^cluster_type:$/cluster_type: ${CLUSTER_TYPE}/" ansible/vars/all.yml

# Set worker count for MNO
if [ "$CLUSTER_TYPE" = "mno" ]; then
    sedi "s/^worker_node_count:$/worker_node_count: ${WORKER_NODE_COUNT}/" ansible/vars/all.yml
fi

# Set OCP version
sedi "s/^ocp_build: .*/ocp_build: \"${OCP_BUILD}\"/" ansible/vars/all.yml
sedi "s/^ocp_version: .*/ocp_version: \"${OCP_VERSION}\"/" ansible/vars/all.yml

# Configure network stack
if [ "$NETWORK_STACK" = "ipv4" ]; then
    sedi 's/^setup_bastion_registry: true$/setup_bastion_registry: false/' ansible/vars/all.yml
    sedi 's/^use_bastion_registry: true$/use_bastion_registry: false/' ansible/vars/all.yml
elif [ "$NETWORK_STACK" = "ipv6" ]; then
    sedi '/^# Single Stack IPv6:/,/^$/{/^# [a-z]/s/^# //; /^# - /s/^# //;}' ansible/vars/all.yml

    if [ "$IPV6_MODE" = "disconnected" ]; then
        sedi 's/^setup_bastion_registry: false$/setup_bastion_registry: true/' ansible/vars/all.yml
        sedi 's/^use_bastion_registry: false$/use_bastion_registry: true/' ansible/vars/all.yml
        echo 'sync_operator_index: true' >> ansible/vars/all.yml
        echo 'sync_ocp_release: true' >> ansible/vars/all.yml
    else
        sedi 's/^setup_bastion_proxy: false$/setup_bastion_proxy: true/' ansible/vars/all.yml
    fi
elif [ "$NETWORK_STACK" = "dual" ]; then
    sedi '/^# Dual Stack/,/^$/{/^# [a-z]/s/^# //; /^# - /s/^# //;}' ansible/vars/all.yml
    sedi 's/^setup_bastion_registry: true$/setup_bastion_registry: false/' ansible/vars/all.yml
    sedi 's/^use_bastion_registry: true$/use_bastion_registry: false/' ansible/vars/all.yml
fi

# Add custom BMC password if provided
if [ -n "$BMC_PASSWORD" ]; then
    echo "bmc_password: \"$BMC_PASSWORD\"" >> ansible/vars/all.yml
fi

# Handle pull secret
if [ -f "${REG_AGENT_ROOT}/pull-secret.txt" ]; then
    cp "${REG_AGENT_ROOT}/pull-secret.txt" pull-secret.txt
elif [ -f "$PULL_SECRET_PATH" ]; then
    cp "$PULL_SECRET_PATH" pull-secret.txt
else
    echo "Error: Pull secret not found"
    echo "Expected at: ${REG_AGENT_ROOT}/pull-secret.txt or $PULL_SECRET_PATH"
    exit 1
fi

echo "✓ Jetlag configuration generated"

# Activate Jetlag environment
echo ""
echo "Activating Jetlag environment..."
source .ansible/bin/activate

# Create inventory
echo ""
echo "Creating inventory for $CLOUD_NAME..."
ansible-playbook ansible/create-inventory.yml

INVENTORY_FILE="ansible/inventory/${CLOUD_NAME}.local"

if [ ! -f "$INVENTORY_FILE" ]; then
    echo "Error: Inventory not created at $INVENTORY_FILE"
    exit 1
fi

echo "✓ Inventory created: $INVENTORY_FILE"

# Extract bastion host
BASTION_HOST=$(grep -A1 '^\[bastion\]' "$INVENTORY_FILE" | tail -1 | awk '{print $1}')

if [ -z "$BASTION_HOST" ]; then
    echo "Error: Could not extract bastion host from inventory"
    exit 1
fi

echo "✓ Bastion host: $BASTION_HOST"

# Save bastion to state
echo "BASTION_HOST=${BASTION_HOST}" >> "${REG_AGENT_ROOT}/vars/state.env"

# Copy SSH key to bastion (if password provided)
if [ -n "$BASTION_ROOT_PASSWORD" ]; then
    echo ""
    echo "Copying SSH key to bastion..."

    ssh-keygen -R "$BASTION_HOST" 2>/dev/null || true
    ssh-keyscan "$BASTION_HOST" >> ~/.ssh/known_hosts 2>/dev/null

    if command -v sshpass &>/dev/null; then
        if sshpass -p "$BASTION_ROOT_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no -o PubkeyAuthentication=no root@$BASTION_HOST 2>/dev/null; then
            echo "✓ SSH key copied to bastion"
        else
            echo "⚠️  Could not copy SSH key. You may need to do this manually:"
            echo "   ssh-copy-id root@$BASTION_HOST"
        fi
    else
        echo "⚠️  sshpass not found. Copy SSH key manually:"
        echo "   ssh-copy-id root@$BASTION_HOST"
    fi
fi

# Setup bastion
echo ""
echo "========================================="
echo "Setting up bastion host..."
echo "========================================="

ansible-playbook -i "$INVENTORY_FILE" ansible/setup-bastion.yml

echo ""
echo "✓ Bastion setup complete"

# Deploy cluster
echo ""
echo "========================================="
echo "Deploying OpenShift cluster..."
echo "========================================="

# Determine deployment playbook
if [ "$CLUSTER_TYPE" = "mno" ]; then
    DEPLOY_PLAYBOOK="ansible/mno-deploy.yml"
elif [ "$CLUSTER_TYPE" = "sno" ]; then
    DEPLOY_PLAYBOOK="ansible/sno-deploy.yml"
else
    echo "Error: Unknown cluster type: $CLUSTER_TYPE"
    exit 1
fi

ansible-playbook -i "$INVENTORY_FILE" "$DEPLOY_PLAYBOOK"

# Determine kubeconfig path
if [ "$CLUSTER_TYPE" = "sno" ]; then
    SNO_NAME=$(grep -v '^#' "$INVENTORY_FILE" | grep -A1 '^\[sno\]' | tail -1 | awk '{print $1}' || echo "")
    if [ -n "$SNO_NAME" ]; then
        KUBECONFIG_PATH="/root/sno/${SNO_NAME}/kubeconfig"
    else
        KUBECONFIG_PATH="/root/sno/kubeconfig"
    fi
else
    KUBECONFIG_PATH="/root/${CLUSTER_TYPE}/kubeconfig"
fi

# Save kubeconfig path to state
echo "KUBECONFIG_PATH=${KUBECONFIG_PATH}" >> "${REG_AGENT_ROOT}/vars/state.env"
echo "CLUSTER_TYPE=${CLUSTER_TYPE}" >> "${REG_AGENT_ROOT}/vars/state.env"

echo ""
echo "========================================="
echo "✅ Phase 2: Cluster Deployment Complete"
echo "========================================="
echo "Cluster Type: $CLUSTER_TYPE"
echo "Bastion: $BASTION_HOST"
echo "Kubeconfig: $KUBECONFIG_PATH"
echo ""
echo "Access cluster:"
echo "  ssh root@$BASTION_HOST"
echo "  export KUBECONFIG=$KUBECONFIG_PATH"
echo "  oc get nodes"
echo ""

cd "$REG_AGENT_ROOT"
exit 0
