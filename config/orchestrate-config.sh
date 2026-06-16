#!/bin/bash
# Modular Configuration Orchestrator
# Calls each module's setup-config.sh in sequence, passing outputs as inputs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REG_AGENT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VARS_DIR="${REG_AGENT_ROOT}/vars"

# Load module interface library
source "${REG_AGENT_ROOT}/modules/lib/module-interface.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}           reg-agent Modular Configuration Orchestrator${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

#------------------------------------------------------------------------------
# Determine Deployment Mode
#------------------------------------------------------------------------------

# Check if running from JSON config
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    MODE="json"
    export AUTO_MODE=1

    echo -e "${GREEN}Mode: Non-Interactive (JSON)${NC}"
    echo "Config file: ${CONFIG_FILE}"
    echo ""

    # Validate JSON
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}ERROR: jq is required for JSON config mode${NC}"
        echo "Install: sudo dnf install -y jq"
        exit 1
    fi

    # Run validator
    if [ -f "${SCRIPT_DIR}/validate-config.sh" ]; then
        echo -e "${BLUE}Validating configuration...${NC}"
        if ! "${SCRIPT_DIR}/validate-config.sh" "$CONFIG_FILE"; then
            echo -e "${RED}Configuration validation failed${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ Configuration validated${NC}"
        echo ""
    fi

    # Parse deployment mode from JSON
    DEPLOY_MODE=$(jq -r '.deployment_mode // "full"' "$CONFIG_FILE")

else
    MODE="interactive"
    export AUTO_MODE=""

    echo -e "${GREEN}Mode: Interactive${NC}"
    echo ""

    # Ask for deployment mode
    echo "Select deployment mode:"
    echo "  1) full         - Complete pipeline (QUADS + Jetlag + Crucible + Regulus)"
    echo "  2) cluster-ready - Use existing cluster (Crucible + Regulus)"
    echo ""
    read -p "Choice [1-2, default=1]: " mode_choice

    case "$mode_choice" in
        2) DEPLOY_MODE="cluster-ready" ;;
        *) DEPLOY_MODE="full" ;;
    esac

    echo ""
    echo -e "${GREEN}Selected: $DEPLOY_MODE${NC}"
    echo ""
fi

export DEPLOY_MODE

#------------------------------------------------------------------------------
# Load Existing Configuration and State
#------------------------------------------------------------------------------

# Load existing config if it exists
if [ -f "${VARS_DIR}/config.env" ]; then
    source "${VARS_DIR}/config.env" 2>/dev/null || true
fi

# Load existing state if it exists
if [ -f "${VARS_DIR}/state.env" ]; then
    source "${VARS_DIR}/state.env" 2>/dev/null || true
fi

# Load module states
for module in quads jetlag crucible regulus; do
    module_state="${REG_AGENT_ROOT}/modules/${module}/generated/state/current.env"
    if [ -f "$module_state" ]; then
        source "$module_state" 2>/dev/null || true
    fi
done

#------------------------------------------------------------------------------
# JSON Mode: Parse Configuration for All Modules
#------------------------------------------------------------------------------

if [ "$MODE" = "json" ]; then
    echo -e "${BLUE}Parsing JSON configuration...${NC}"
    echo ""

    # Parse QUADS configuration
    export QUADS_MODE=$(jq -r '.quads.mode // "allocate"' "$CONFIG_FILE")
    export QUADS_API_SERVER=$(jq -r '.quads.api_server // empty' "$CONFIG_FILE")
    export QUADS_USERNAME=$(jq -r '.quads.username // empty' "$CONFIG_FILE")
    export QUADS_PASSWORD=$(jq -r '.quads.password // empty' "$CONFIG_FILE")
    export QUADS_API_TOKEN=$(jq -r '.quads.api_token // empty' "$CONFIG_FILE")
    export LAB=$(jq -r '.quads.lab // empty' "$CONFIG_FILE")
    export NUM_HOSTS=$(jq -r '.quads.num_hosts // empty' "$CONFIG_FILE")
    export PREFERRED_MODEL=$(jq -r '.quads.preferred_model // empty' "$CONFIG_FILE")
    export WORKLOAD_NAME=$(jq -r '.quads.workload_name // empty' "$CONFIG_FILE")
    export SHORT_DESCRIPTION=$(jq -r '.quads.short_description // empty' "$CONFIG_FILE")
    export WIPE_DISKS=$(jq -r '.quads.wipe_disks // empty' "$CONFIG_FILE")
    export CLOUD_NAME=$(jq -r '.quads.cloud_name // empty' "$CONFIG_FILE")

    # Parse Jetlag configuration
    export CLUSTER_TYPE=$(jq -r '.jetlag.cluster_type // empty' "$CONFIG_FILE")
    export WORKER_NODE_COUNT=$(jq -r '.jetlag.worker_node_count // empty' "$CONFIG_FILE")
    export OCP_BUILD=$(jq -r '.jetlag.ocp_build // "ga"' "$CONFIG_FILE")
    export OCP_VERSION=$(jq -r '.jetlag.ocp_version // "latest-4.20"' "$CONFIG_FILE")
    export NETWORK_STACK=$(jq -r '.jetlag.network_stack // "ipv4"' "$CONFIG_FILE")
    export IPV6_MODE=$(jq -r '.jetlag.ipv6_mode // empty' "$CONFIG_FILE")
    export PULL_SECRET_PATH=$(jq -r '.jetlag.pull_secret_path // empty' "$CONFIG_FILE")
    export BMC_PASSWORD=$(jq -r '.jetlag.bmc_password // empty' "$CONFIG_FILE")
    export LAB_SSH_USER=$(jq -r '.jetlag.lab_ssh_user // "root"' "$CONFIG_FILE")
    export LAB_SSH_PASSWORD=$(jq -r '.jetlag.lab_ssh_password // empty' "$CONFIG_FILE")

    # Parse cluster-ready mode configuration (bastion host could come from jetlag or crucible_controller)
    export BASTION_HOST=$(jq -r '.jetlag.bastion_host // empty' "$CONFIG_FILE")
    export KUBECONFIG_PATH=$(jq -r '.jetlag.kubeconfig_path // "/root/mno/kubeconfig"' "$CONFIG_FILE")

    # Parse Crucible configuration
    export CRUCIBLE_GIT_REPO=$(jq -r '.crucible.git_repo // "https://github.com/perftool-incubator/crucible.git"' "$CONFIG_FILE")
    export CRUCIBLE_GIT_BRANCH=$(jq -r '.crucible.git_branch // "master"' "$CONFIG_FILE")
    export CRUCIBLE_CONTROLLER_USER=$(jq -r '.crucible.controller_user // "root"' "$CONFIG_FILE")
    export CRUCIBLE_CONTROLLER_PASSWORD=$(jq -r '.crucible.controller_password // empty' "$CONFIG_FILE")

    # Parse Regulus configuration
    export REGULUS_JOBS=$(jq -r '.regulus.jobs // empty' "$CONFIG_FILE")
    export REGULUS_TAG=$(jq -r '.regulus.tag // "REG-AGENT"' "$CONFIG_FILE")
    export NUM_SAMPLES=$(jq -r '.regulus.num_samples // "3"' "$CONFIG_FILE")
    export TEST_DURATION=$(jq -r '.regulus.duration // "60"' "$CONFIG_FILE")
    export REG_KNI_USER=$(jq -r '.regulus.kni_user // "root"' "$CONFIG_FILE")
    export REG_DP=$(jq -r '.regulus.deployment_id // "reg-agent"' "$CONFIG_FILE")
    export REGULUS_INSTALL_SUBDIR=$(jq -r '.regulus.install_subdir // empty' "$CONFIG_FILE")

    echo -e "${GREEN}✓ Configuration parsed from JSON${NC}"
    echo ""
fi

#------------------------------------------------------------------------------
# Get Module List Based on Deployment Mode
#------------------------------------------------------------------------------

MODULES=$(get_modules_for_mode "$DEPLOY_MODE")

echo -e "${BLUE}Deployment Mode: ${DEPLOY_MODE}${NC}"
echo "Modules to configure: $MODULES"
echo ""

#------------------------------------------------------------------------------
# Configure Each Module in Sequence
#------------------------------------------------------------------------------

for module in $MODULES; do
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Configuring Module: $module${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Load module interface
    if ! load_module_interface "$module"; then
        echo -e "${RED}ERROR: Failed to load interface for module: $module${NC}"
        exit 1
    fi

    echo -e "${BLUE}Module: $MODULE_NAME (Phase $MODULE_PHASE)${NC}"
    echo "$MODULE_DESCRIPTION"
    echo ""

    # Check if module's requirements are met (inputs from previous modules)
    # Note: During configuration phase, some runtime dependencies may not be available yet
    # They will be generated during deployment phase
    if [ ${#MODULE_REQUIRES[@]} -gt 0 ]; then
        echo "Checking required inputs..."

        missing_inputs=()
        available_inputs=()

        for var in "${MODULE_REQUIRES[@]}"; do
            if [ -z "${!var}" ]; then
                missing_inputs+=("$var")
                echo "  - $var (will be provided during deployment)"
            else
                available_inputs+=("$var")
                echo "  ✓ $var = ${!var}"
            fi
        done

        # Only fail if we're in deployment mode and inputs are truly missing
        # During configuration, it's OK for runtime outputs to not exist yet
        if [ ${#missing_inputs[@]} -gt 0 ]; then
            echo ""
            echo -e "${YELLOW}Note: Some inputs will be generated by previous modules during deployment${NC}"
            echo "      Missing now: ${missing_inputs[*]}"
        fi
        echo ""
    fi

    # Call module's public init API (make init)
    # This respects module encapsulation and uses the official interface
    echo "Running module initialization (make init)..."
    echo ""

    # Run make init for the module
    # In AUTO_MODE, it should use environment variables from JSON/config
    # In interactive mode, it should prompt the user
    # make init is idempotent - safe to call multiple times
    if make -C "${REG_AGENT_ROOT}/modules/${module}" init; then
        echo ""
        echo -e "${GREEN}✓ Module '$module' initialized successfully${NC}"
        echo ""
    else
        echo ""
        echo -e "${RED}ERROR: Module '$module' initialization failed${NC}"
        exit 1
    fi

    # Reload config and state to pick up module's outputs
    if [ -f "${VARS_DIR}/config.env" ]; then
        source "${VARS_DIR}/config.env" 2>/dev/null || true
    fi
    if [ -f "${VARS_DIR}/state.env" ]; then
        source "${VARS_DIR}/state.env" 2>/dev/null || true
    fi

    module_state="${REG_AGENT_ROOT}/modules/${module}/generated/state/current.env"
    if [ -f "$module_state" ]; then
        source "$module_state" 2>/dev/null || true
    fi

    # Verify module provided its outputs
    echo "Verifying module outputs..."
    missing_outputs=()
    for var in "${MODULE_PROVIDES[@]}"; do
        if [ -n "${!var}" ]; then
            echo "  ✓ $var = ${!var}"
        else
            missing_outputs+=("$var")
            echo "  - $var (not set, will be set during deployment)"
        fi
    done
    echo ""

    if [ ${#missing_outputs[@]} -gt 0 ] && [ "$MODE" != "json" ]; then
        # In interactive mode, some outputs may not be set until deployment
        # This is okay - they'll be created during deploy phase
        echo -e "${YELLOW}Note: Some outputs will be generated during deployment${NC}"
        echo ""
    fi
done

#------------------------------------------------------------------------------
# Write Global Settings
#------------------------------------------------------------------------------

# Ensure DEPLOY_MODE is in config.env
if [ -f "${VARS_DIR}/config.env" ]; then
    if ! grep -q "^DEPLOY_MODE=" "${VARS_DIR}/config.env" 2>/dev/null; then
        echo "" >> "${VARS_DIR}/config.env"
        echo "# Deployment mode" >> "${VARS_DIR}/config.env"
        echo "DEPLOY_MODE=${DEPLOY_MODE}" >> "${VARS_DIR}/config.env"
    fi
fi

#------------------------------------------------------------------------------
# Configuration Summary
#------------------------------------------------------------------------------

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}           Configuration Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ -f "${VARS_DIR}/config.json" ]; then
    echo -e "${GREEN}✓ Configuration saved to: ${VARS_DIR}/config.json${NC}"
    echo ""

    echo "Configured modules:"
    for module in $MODULES; do
        echo "  ✓ $module"
    done
    echo ""

    echo -e "${GREEN}Next steps:${NC}"
    echo "  1. Review config: cat ${VARS_DIR}/config.json | jq ."
    echo "  2. Start deployment: make deploy"
    echo ""
else
    echo -e "${RED}ERROR: Configuration file was not created${NC}"
    echo "Check module scripts for errors"
    exit 1
fi

exit 0
