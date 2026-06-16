#!/bin/bash
# Interactive configuration for Jetlag module
# Supports non-interactive mode for automation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Ensure config directory exists
mkdir -p "${SCRIPT_DIR}/generated/config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Jetlag Module Configuration${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

#------------------------------------------------------------------------------
# Mode Detection: Interactive vs Non-Interactive
#------------------------------------------------------------------------------

# Determine mode based on flags and TTY
if [ -n "$FORCE_INTERACTIVE" ]; then
    # Debug mode - always interactive, always prompt
    MODE="force-interactive"
    echo -e "${YELLOW}Running in FORCE INTERACTIVE mode (debug)${NC}"
    echo ""
elif [ -n "$AUTO_MODE" ] || [ ! -t 0 ]; then
    # Auto mode - non-interactive, use existing config or fail
    MODE="auto"
    echo -e "${YELLOW}Running in non-interactive mode${NC}"
    echo ""

    # Check if we have environment variables from orchestrator (JSON config)
    # This happens during initial configure phase before QUADS allocation
    if [ -n "$CLUSTER_TYPE" ] && [ -n "$LAB" ]; then
        echo "✓ Using configuration from environment variables"
        echo "  (QUADS allocation will happen in deploy phase)"
        choice=1
    # Auto-select option 1 if QUADS state exists
    elif [ -f "$ROOT_DIR/modules/quads/generated/state/current.env" ]; then
        echo "✓ Detected QUADS state from Phase 1"
        echo "  Auto-selecting: Deploy from QUADS allocation"
        choice=1
    elif [ -f "$ROOT_DIR/vars/state.env" ] && grep -q "CLOUD_NAME" "$ROOT_DIR/vars/state.env"; then
        echo "✓ Detected CLOUD_NAME in global state"
        echo "  Auto-selecting: Deploy from existing allocation"
        choice=1
    else
        echo -e "${RED}ERROR: Cannot auto-configure in non-interactive mode${NC}"
        echo ""
        echo "No QUADS state found. Please either:"
        echo "  1. Run Phase 1 (QUADS) first: make -C modules/quads allocate"
        echo "  2. Run interactively: make init-debug"
        echo "  3. Set environment variables: CLOUD_NAME=... LAB=..."
        exit 1
    fi
else
    # Smart mode - interactive only if needed
    MODE="smart"
    echo "How do you want to configure the cluster?"
    echo ""
    echo "1) Deploy new cluster from QUADS allocation (Phase 1 output)"
    echo "2) Deploy new cluster on specific cloud (manual CLOUD_NAME)"
    echo "3) Import existing cluster (already deployed)"
    echo ""
    read -p "Choice [1-3]: " choice
fi

case $choice in
    #--------------------------------------------------------------------------
    # Option 1: Use Phase 1 QUADS Output
    #--------------------------------------------------------------------------
    1)
        echo ""
        echo -e "${GREEN}Using QUADS allocation from Phase 1${NC}"
        echo ""

        if [ -f "$ROOT_DIR/modules/quads/generated/state/current.env" ]; then
            source "$ROOT_DIR/modules/quads/generated/state/current.env"

            # Load QUADS credentials
            if [ -f "$ROOT_DIR/vars/config.env" ]; then
                source "$ROOT_DIR/vars/config.env"
            fi

            echo "Found Phase 1 state:"
            echo "  CLOUD_NAME: ${CLOUD_NAME}"
            echo "  LAB:        ${LAB}"
            echo ""

            # First, try to get NUM_HOSTS from QUADS state (works with imported clouds)
            QUADS_STATE_FILE="${ROOT_DIR}/modules/quads/generated/state/current.env"
            if [ -f "$QUADS_STATE_FILE" ]; then
                source "$QUADS_STATE_FILE" 2>/dev/null || true
            fi

            # Check if we have NUM_HOSTS from state
            if [ -n "$NUM_HOSTS" ] && [ "$NUM_HOSTS" -gt 0 ]; then
                # Got NUM_HOSTS from state - skip QUADS API entirely
                echo -e "${GREEN}✓ Using host count from QUADS state: ${NUM_HOSTS} hosts${NC}"
                echo ""
                QUADS_TOKEN="from-state"  # Set a dummy token so the rest of the logic works
            else
                # Need to query QUADS API for host count
                echo -e "${BLUE}Querying QUADS for host count...${NC}"

                # Get authentication token
                QUADS_USER_DOMAIN=${QUADS_USER_DOMAIN:-"redhat.com"}
                QUADS_USER_EMAIL="${QUADS_USERNAME}@${QUADS_USER_DOMAIN}"

                if [ -n "$QUADS_API_TOKEN" ]; then
                    QUADS_TOKEN="$QUADS_API_TOKEN"
                elif [ -n "$QUADS_PASSWORD" ]; then
                    LOGIN_RESPONSE=$(curl -sk -X POST \
                        -u "${QUADS_USER_EMAIL}:${QUADS_PASSWORD}" \
                        "https://${QUADS_API_SERVER}/api/v3/login/" 2>/dev/null)
                    QUADS_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.auth_token // empty' 2>/dev/null)
                fi
            fi

            # Query hosts for this cloud (only if token is real and we don't have NUM_HOSTS yet)
            if [ -n "$QUADS_TOKEN" ]; then
                if [ "$QUADS_TOKEN" != "from-state" ] && { [ -z "$NUM_HOSTS" ] || [ "$NUM_HOSTS" -eq 0 ]; }; then
                    HOSTS_JSON=$(curl -sk \
                        -H "Authorization: Bearer ${QUADS_TOKEN}" \
                        "https://${QUADS_API_SERVER}/api/v3/hosts?cloud=${CLOUD_NAME}" 2>/dev/null)

                    NUM_HOSTS=$(echo "$HOSTS_JSON" | jq '. | length' 2>/dev/null || echo "0")
                fi

                if [ "$NUM_HOSTS" -gt 0 ]; then
                echo "  ✓ Found ${NUM_HOSTS} hosts in allocation"
                echo ""

                # Auto-determine cluster type based on node count
                # 2 nodes = SNO (2 single-node clusters)
                # 6+ nodes = MNO (1 bastion + 3 control + N workers)
                if [ "$NUM_HOSTS" -eq 2 ]; then
                    SUGGESTED_CLUSTER_TYPE="sno"
                    SUGGESTED_WORKER_COUNT=0
                    echo -e "${GREEN}Recommended configuration:${NC}"
                    echo "  Cluster type: SNO (Single-Node OpenShift)"
                    echo "  Reason: 2 hosts can create 2 separate SNO clusters"
                elif [ "$NUM_HOSTS" -ge 6 ]; then
                    SUGGESTED_CLUSTER_TYPE="mno"
                    SUGGESTED_WORKER_COUNT=$((NUM_HOSTS - 4))  # minus bastion + 3 control-plane
                    echo -e "${GREEN}Recommended configuration:${NC}"
                    echo "  Cluster type: MNO (Multi-Node OpenShift)"
                    echo "  Worker nodes: ${SUGGESTED_WORKER_COUNT}"
                    echo "  Layout: 1 bastion + 3 control-plane + ${SUGGESTED_WORKER_COUNT} workers = ${NUM_HOSTS} hosts"
                else
                    SUGGESTED_CLUSTER_TYPE="sno"
                    SUGGESTED_WORKER_COUNT=0
                    echo -e "${YELLOW}Warning: ${NUM_HOSTS} hosts is not a standard count${NC}"
                    echo "  - SNO requires: 2 hosts (creates 2 SNO clusters)"
                    echo "  - MNO requires: 6+ hosts (1 bastion + 3 control + 2+ workers)"
                    echo ""
                    echo "Recommended: SNO (best fit for ${NUM_HOSTS} hosts)"
                fi

                # In auto mode, use suggested values without asking
                if [ "$MODE" = "auto" ]; then
                    CLUSTER_TYPE="$SUGGESTED_CLUSTER_TYPE"
                    WORKER_NODE_COUNT="$SUGGESTED_WORKER_COUNT"
                    echo "  → Auto-selected: $CLUSTER_TYPE with $WORKER_NODE_COUNT workers"
                else
                        # Ask user to confirm or override
                        echo ""
                        echo "Cluster type:"
                        echo "  1) ${SUGGESTED_CLUSTER_TYPE} (recommended)"
                        if [ "$SUGGESTED_CLUSTER_TYPE" = "sno" ]; then
                            echo "  2) mno (Multi-Node - requires 6+ hosts)"
                        else
                            echo "  2) sno (Single-Node - only uses 2 hosts)"
                        fi
                        read -p "Choice [1-2, default=1]: " cluster_choice

                        case $cluster_choice in
                            2)
                                if [ "$SUGGESTED_CLUSTER_TYPE" = "sno" ]; then
                                    CLUSTER_TYPE="mno"
                                    echo ""
                                    echo -e "${YELLOW}Warning: You have ${NUM_HOSTS} hosts but MNO requires 6+${NC}"
                                    read -p "Worker node count [default=2]: " WORKER_NODE_COUNT
                                    WORKER_NODE_COUNT=${WORKER_NODE_COUNT:-2}
                                else
                                    CLUSTER_TYPE="sno"
                                    WORKER_NODE_COUNT=0
                                fi
                                ;;
                            *)
                                CLUSTER_TYPE="$SUGGESTED_CLUSTER_TYPE"
                                WORKER_NODE_COUNT="$SUGGESTED_WORKER_COUNT"
                                ;;
                        esac
                    fi
                else
                    if [ "$MODE" = "auto" ]; then
                        echo -e "${RED}ERROR: Could not query QUADS for host count${NC}"
                        echo ""
                        echo "QUADS query failed for CLOUD_NAME='${CLOUD_NAME}'"
                        echo ""
                        echo "Possible causes:"
                        echo "  - CLOUD_NAME not found in QUADS"
                        echo "  - Network connectivity issue"
                        echo "  - Invalid QUADS credentials"
                        echo ""
                        echo "To debug:"
                        echo "  1. Verify allocation exists: make -C modules/quads show-available"
                        echo "  2. Use debug mode: make init-debug"
                        exit 1
                    else
                        echo -e "  ${YELLOW}Could not query host count${NC}"
                        echo ""
                        # Fall back to manual prompts
                        echo "Cluster type:"
                        echo "  1) mno (Multi-Node OpenShift - 3 control + N workers)"
                        echo "  2) sno (Single-Node OpenShift)"
                        read -p "Choice [1-2, default=1]: " cluster_choice

                        case $cluster_choice in
                            2)
                                CLUSTER_TYPE="sno"
                                WORKER_NODE_COUNT=0
                                ;;
                            *)
                                CLUSTER_TYPE="mno"
                                read -p "Worker node count [default=3]: " WORKER_NODE_COUNT
                                WORKER_NODE_COUNT=${WORKER_NODE_COUNT:-3}
                                ;;
                        esac
                    fi
                fi
            else
                if [ "$MODE" = "auto" ]; then
                    echo -e "${RED}ERROR: Could not authenticate to QUADS${NC}"
                    echo ""
                    echo "QUADS authentication failed. Check credentials in:"
                    echo "  ${ROOT_DIR}/vars/config.env"
                    echo ""
                    echo "Required variables:"
                    echo "  - QUADS_API_SERVER"
                    echo "  - QUADS_USERNAME"
                    echo "  - QUADS_PASSWORD (or QUADS_API_TOKEN)"
                    echo ""
                    echo "To debug:"
                    echo "  1. Verify credentials are correct"
                    echo "  2. Use debug mode: make init-debug"
                    exit 1
                else
                    echo -e "  ${YELLOW}Could not authenticate to QUADS${NC}"
                    echo ""
                    # Fall back to manual prompts
                    echo "Cluster type:"
                    echo "  1) mno (Multi-Node OpenShift - 3 control + N workers)"
                    echo "  2) sno (Single-Node OpenShift)"
                    read -p "Choice [1-2, default=1]: " cluster_choice

                    case $cluster_choice in
                        2)
                            CLUSTER_TYPE="sno"
                            WORKER_NODE_COUNT=0
                            ;;
                        *)
                            CLUSTER_TYPE="mno"
                            read -p "Worker node count [default=3]: " WORKER_NODE_COUNT
                            WORKER_NODE_COUNT=${WORKER_NODE_COUNT:-3}
                            ;;
                    esac
                fi
            fi

            # Get lab SSH credentials
            echo ""
            echo "Lab SSH Access:"

            if [ "$MODE" = "auto" ]; then
                # AUTO_MODE: Use environment variables or defaults
                LAB_SSH_USER=${LAB_SSH_USER:-root}
                LAB_SSH_PASSWORD=${LAB_SSH_PASSWORD:-}
                echo "  → Auto-configured: user=${LAB_SSH_USER}, password=${LAB_SSH_PASSWORD:+configured}"
            else
                # Interactive mode: Prompt user
                read -p "Lab SSH username [default: root]: " LAB_SSH_USER
                LAB_SSH_USER=${LAB_SSH_USER:-root}
                read -s -p "Lab SSH password (optional, press Enter to skip): " LAB_SSH_PASSWORD
                echo ""
                if [ -n "$LAB_SSH_PASSWORD" ]; then
                    echo -e "${GREEN}✓ Lab SSH credentials: user=${LAB_SSH_USER}, password=configured${NC}"
                else
                    echo -e "${YELLOW}⚠  No lab SSH password (may require manual SSH key setup)${NC}"
                fi
            fi

            echo ""
            echo -e "${GREEN}✓ Configuration will use Phase 1 QUADS allocation${NC}"
            echo ""
            echo "Next: Run 'make deploy' to deploy cluster"
        else
            echo -e "${YELLOW}Warning: Phase 1 state not found${NC}"
            echo ""
            echo "You need to run Phase 1 (QUADS) first:"
            echo "  make test-quads"
            echo ""
            echo "Or choose option 2 to manually specify CLOUD_NAME"
        fi
        ;;

    #--------------------------------------------------------------------------
    # Option 2: Manual CLOUD_NAME
    #--------------------------------------------------------------------------
    2)
        echo ""
        echo -e "${BLUE}Manual CLOUD_NAME Configuration${NC}"
        echo ""

        # Get CLOUD_NAME
        read -p "CLOUD_NAME (e.g., cloud42): " CLOUD_NAME
        if [ -z "$CLOUD_NAME" ]; then
            echo -e "${RED}ERROR: CLOUD_NAME cannot be empty${NC}"
            exit 1
        fi

        # Get LAB
        echo ""
        echo "Lab selection:"
        echo "  1) scalelab"
        echo "  2) performancelab"
        read -p "Choice [1-2]: " lab_choice

        case $lab_choice in
            1) LAB="scalelab" ;;
            2) LAB="performancelab" ;;
            *)
                echo -e "${RED}Invalid choice${NC}"
                exit 1
                ;;
        esac

        # Get cluster type
        echo ""
        echo "Cluster type:"
        echo "  1) mno (Multi-Node OpenShift - 3 control + N workers)"
        echo "  2) sno (Single-Node OpenShift)"
        read -p "Choice [1-2, default=1]: " cluster_choice

        case $cluster_choice in
            2) CLUSTER_TYPE="sno" ;;
            *) CLUSTER_TYPE="mno" ;;
        esac

        # Get worker count (only for MNO)
        if [ "$CLUSTER_TYPE" = "mno" ]; then
            read -p "Worker node count [default=3]: " WORKER_NODE_COUNT
            WORKER_NODE_COUNT=${WORKER_NODE_COUNT:-3}
        fi

        # Get OCP version
        echo ""
        read -p "OpenShift version [default=latest-4.20]: " OCP_VERSION
        OCP_VERSION=${OCP_VERSION:-latest-4.20}

        # Get build type
        echo ""
        echo "OpenShift build:"
        echo "  1) ga (General Availability - stable)"
        echo "  2) dev (Development)"
        echo "  3) ci (Continuous Integration)"
        read -p "Choice [1-3, default=1]: " build_choice

        case $build_choice in
            2) OCP_BUILD="dev" ;;
            3) OCP_BUILD="ci" ;;
            *) OCP_BUILD="ga" ;;
        esac

        # Get network stack
        echo ""
        echo "Network stack:"
        echo "  1) ipv4 (default)"
        echo "  2) ipv6"
        echo "  3) dual"
        read -p "Choice [1-3, default=1]: " network_choice

        case $network_choice in
            2) NETWORK_STACK="ipv6" ;;
            3) NETWORK_STACK="dual" ;;
            *) NETWORK_STACK="ipv4" ;;
        esac

        # Get lab SSH credentials (optional but recommended)
        echo ""
        echo "Lab SSH Access:"
        read -p "Lab SSH username [default: root]: " LAB_SSH_USER
        LAB_SSH_USER=${LAB_SSH_USER:-root}
        read -s -p "Lab SSH password (optional, press Enter to skip): " LAB_SSH_PASSWORD
        echo ""
        if [ -n "$LAB_SSH_PASSWORD" ]; then
            echo -e "${GREEN}✓ Lab SSH credentials: user=${LAB_SSH_USER}, password=configured${NC}"
        else
            echo -e "${YELLOW}⚠  No lab SSH password (may require manual SSH key setup)${NC}"
        fi

        # Save configuration
        cat > "${SCRIPT_DIR}/generated/config/override.env" << EOF
# Jetlag module configuration - manual override
# Generated: $(date)

CLOUD_NAME=${CLOUD_NAME}
LAB=${LAB}
CLUSTER_TYPE=${CLUSTER_TYPE}
${WORKER_NODE_COUNT:+WORKER_NODE_COUNT=${WORKER_NODE_COUNT}}
OCP_VERSION=${OCP_VERSION}
OCP_BUILD=${OCP_BUILD}
NETWORK_STACK=${NETWORK_STACK}
LAB_SSH_USER=${LAB_SSH_USER}
${LAB_SSH_PASSWORD:+LAB_SSH_PASSWORD=${LAB_SSH_PASSWORD}}
EOF

        echo ""
        echo -e "${GREEN}✓ Configuration saved to:${NC}"
        echo "  ${SCRIPT_DIR}/generated/config/override.env"
        echo ""
        echo "Configuration:"
        cat "${SCRIPT_DIR}/generated/config/override.env" | grep -v "^#"
        echo ""
        echo "Next: Run 'make deploy' to deploy cluster"
        ;;

    #--------------------------------------------------------------------------
    # Option 3: Import Existing Cluster
    #--------------------------------------------------------------------------
    3)
        echo ""
        echo -e "${BLUE}Import Existing Cluster${NC}"
        echo ""
        echo -e "${GREEN}ℹ  Note: When importing an existing cluster, you can skip Phase 1 (QUADS) entirely${NC}"
        echo ""
        echo "This option is for when you already have:"
        echo "  ✓ A deployed OpenShift cluster"
        echo "  ✓ Access to the bastion host"
        echo "  ✓ A valid kubeconfig file"
        echo ""
        echo "You do NOT need to run 'make -C modules/quads import' first."
        echo ""

        # Get bastion host
        read -p "BASTION_HOST (hostname or IP): " BASTION_HOST
        if [ -z "$BASTION_HOST" ]; then
            echo -e "${RED}ERROR: BASTION_HOST cannot be empty${NC}"
            exit 1
        fi

        # Get kubeconfig path
        echo ""
        echo "Kubeconfig path on bastion:"
        echo "  For MNO: /root/mno/kubeconfig"
        echo "  For SNO: /root/sno/kubeconfig"
        read -p "KUBECONFIG_PATH [default=/root/mno/kubeconfig]: " KUBECONFIG_PATH
        KUBECONFIG_PATH=${KUBECONFIG_PATH:-/root/mno/kubeconfig}

        # Get cluster type
        echo ""
        echo "Cluster type:"
        echo "  1) mno (Multi-Node OpenShift)"
        echo "  2) sno (Single-Node OpenShift)"
        read -p "Choice [1-2, default=1]: " cluster_choice

        case $cluster_choice in
            2) CLUSTER_TYPE="sno" ;;
            *) CLUSTER_TYPE="mno" ;;
        esac

        # Try to discover actual cluster configuration
        echo ""
        echo -e "${BLUE}Discovering cluster configuration...${NC}"

        WORKER_NODE_COUNT=3  # Default fallback
        DISCOVERED_WORKERS=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@${BASTION_HOST} \
            "oc --kubeconfig=${KUBECONFIG_PATH} get nodes --no-headers 2>/dev/null | grep -c worker || echo ''" 2>/dev/null || echo "")

        if [ -n "$DISCOVERED_WORKERS" ] && [ "$DISCOVERED_WORKERS" -gt 0 ]; then
            WORKER_NODE_COUNT=$DISCOVERED_WORKERS
            echo "  ✓ Detected ${WORKER_NODE_COUNT} worker nodes from cluster"
        else
            echo -e "  ${YELLOW}Could not query cluster, using default worker_node_count=${WORKER_NODE_COUNT}${NC}"
        fi

        # Try to extract CLOUD_NAME from bastion hostname
        CLOUD_NAME=""
        if [[ "$BASTION_HOST" =~ ^(cloud[0-9]+) ]]; then
            CLOUD_NAME="${BASH_REMATCH[1]}"
            echo "  ✓ Detected CLOUD_NAME from bastion: ${CLOUD_NAME}"
        else
            echo "  ${YELLOW}Could not auto-detect CLOUD_NAME from bastion hostname${NC}"
            read -p "Enter CLOUD_NAME (e.g., cloud04) or press Enter to skip: " CLOUD_NAME_INPUT
            CLOUD_NAME="$CLOUD_NAME_INPUT"
        fi

        # Get LAB
        echo ""
        echo "Lab selection:"
        echo "  1) scalelab"
        echo "  2) performancelab"
        read -p "Choice [1-2, default=1]: " lab_choice

        case $lab_choice in
            2) LAB="performancelab" ;;
            *) LAB="scalelab" ;;
        esac

        # Save import configuration
        cat > "${SCRIPT_DIR}/generated/config/import.env" << EOF
# Jetlag module - import configuration
# Generated: $(date)

BASTION_HOST=${BASTION_HOST}
KUBECONFIG_PATH=${KUBECONFIG_PATH}
CLUSTER_TYPE=${CLUSTER_TYPE}
WORKER_NODE_COUNT=${WORKER_NODE_COUNT}
${CLOUD_NAME:+CLOUD_NAME=${CLOUD_NAME}}
LAB=${LAB}
EOF

        echo ""
        echo -e "${GREEN}✓ Import configuration saved to:${NC}"
        echo "  ${SCRIPT_DIR}/generated/config/import.env"
        echo ""
        echo "Configuration:"
        cat "${SCRIPT_DIR}/generated/config/import.env" | grep -v "^#"
        echo ""
        echo -e "${GREEN}=========================================${NC}"
        echo -e "${GREEN}Cluster Import Setup Complete${NC}"
        echo -e "${GREEN}=========================================${NC}"
        echo ""
        echo "Next steps:"
        echo "  1. Import cluster:  make -C modules/jetlag import"
        echo "  2. Validate:        make -C modules/jetlag validate"
        echo "  3. Continue:        make test-crucible"
        echo ""
        echo -e "${BLUE}Note:${NC} You can skip Phase 1 (QUADS) entirely since you have an existing cluster."
        echo ""
        ;;

    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

#------------------------------------------------------------------------------
# Generate all.yml template for Jetlag
#------------------------------------------------------------------------------

echo ""
echo -e "${BLUE}Generating Jetlag all.yml template...${NC}"

# Ensure Jetlag repo exists
if [ ! -d "${ROOT_DIR}/repos/jetlag" ]; then
    echo -e "${RED}ERROR: Jetlag repository not found${NC}"
    echo "Run: ${ROOT_DIR}/bootstrap.sh"
    exit 1
fi

# Generate all.yml for all modes (deploy and import)
if [ "$choice" = "1" ] || [ "$choice" = "2" ] || [ "$choice" = "3" ]; then
    # Load configuration based on mode
    if [ "$choice" = "1" ] && [ -f "$ROOT_DIR/modules/quads/generated/state/current.env" ]; then
        source "$ROOT_DIR/modules/quads/generated/state/current.env"
    elif [ "$choice" = "2" ] && [ -f "${SCRIPT_DIR}/generated/config/override.env" ]; then
        source "${SCRIPT_DIR}/generated/config/override.env"
    elif [ "$choice" = "3" ] && [ -f "${SCRIPT_DIR}/generated/config/import.env" ]; then
        source "${SCRIPT_DIR}/generated/config/import.env"
    fi

    # Set defaults for any missing values
    CLUSTER_TYPE=${CLUSTER_TYPE:-mno}
    WORKER_NODE_COUNT=${WORKER_NODE_COUNT:-3}
    OCP_BUILD=${OCP_BUILD:-ga}
    OCP_VERSION=${OCP_VERSION:-latest-4.20}
    NETWORK_STACK=${NETWORK_STACK:-ipv4}
    LAB=${LAB:-scalelab}
    CLOUD_NAME=${CLOUD_NAME:-cloud99}

    # Generate all.yml
    cat > "${ROOT_DIR}/repos/jetlag/ansible/vars/all.yml" << EOF
---
# Jetlag configuration generated by reg-agent
# Generated: $(date)

################################################################################
# Lab & cluster infrastructure vars
################################################################################
lab: ${LAB:-scalelab}
lab_cloud: ${CLOUD_NAME:-cloud99}
cluster_type: ${CLUSTER_TYPE}
worker_node_count: ${WORKER_NODE_COUNT}

ocp_build: "${OCP_BUILD}"
ocp_version: "${OCP_VERSION}"

# Public VLAN configuration (false for standard private cloud)
public_vlan: false
sno_use_lab_dhcp: false

# Security and features
enable_fips: false
enable_techpreview: false
enable_cnv_install: false

# SSH keys
ssh_private_key_file: ~/.ssh/id_rsa
ssh_public_key_file: ~/.ssh/id_rsa.pub

# Pull secret
pull_secret: "{{ lookup('file', '../pull-secret.txt') }}"

################################################################################
# Network configuration
################################################################################
networktype: OVNKubernetes

################################################################################
# Bastion configuration
################################################################################
bastion_cluster_config_dir: /root/{{ cluster_type }}
setup_bastion_gogs: false
setup_bastion_registry: false
use_bastion_registry: false
setup_bastion_proxy: false
EOF

    echo -e "${GREEN}✓ Generated: ${ROOT_DIR}/repos/jetlag/ansible/vars/all.yml${NC}"
    echo ""
    echo "Configuration includes:"
    echo "  - lab: ${LAB}"
    echo "  - lab_cloud: ${CLOUD_NAME}"
    echo "  - cluster_type: ${CLUSTER_TYPE}"
    echo "  - worker_node_count: ${WORKER_NODE_COUNT}"
    echo ""
    echo "You can review/edit the configuration at:"
    echo "  ${ROOT_DIR}/repos/jetlag/ansible/vars/all.yml"
    echo ""

    if [ "$choice" = "3" ]; then
        echo -e "${BLUE}For imported clusters:${NC}"
        echo "  make test-inventory - Safely test inventory creation (won't touch cluster)"
        echo "  This helps debug issues that 'make deploy' would encounter"
    fi
fi

#------------------------------------------------------------------------------
# Write Jetlag Configuration to vars/config.env
#------------------------------------------------------------------------------

# DISABLED: config.env write (passive mode - JSON only)
if false; then
    echo "Writing Jetlag configuration to vars/config.env..."

    # Ensure config.env exists
    mkdir -p "${ROOT_DIR}/vars"
    touch "${ROOT_DIR}/vars/config.env"

    # Remove existing Jetlag config if present (delete individual variables and section header)
    sed -i '/^# ========================================$/{ N; /\n# Jetlag Configuration$/{ N; /\n# ========================================$/d; } }' "${ROOT_DIR}/vars/config.env" 2>/dev/null || true
    sed -i '/^CLUSTER_TYPE=/d' "${ROOT_DIR}/vars/config.env" 2>/dev/null || true
    sed -i '/^WORKER_NODE_COUNT=/d' "${ROOT_DIR}/vars/config.env" 2>/dev/null || true
    sed -i '/^OCP_BUILD=/d' "${ROOT_DIR}/vars/config.env" 2>/dev/null || true
    sed -i '/^OCP_VERSION=/d' "${ROOT_DIR}/vars/config.env" 2>/dev/null || true
    sed -i '/^NETWORK_STACK=/d' "${ROOT_DIR}/vars/config.env" 2>/dev/null || true
    sed -i '/^LAB_SSH_USER=/d' "${ROOT_DIR}/vars/config.env" 2>/dev/null || true
    sed -i '/^LAB_SSH_PASSWORD=/d' "${ROOT_DIR}/vars/config.env" 2>/dev/null || true
    sed -i '/^BASTION_HOST=/d' "${ROOT_DIR}/vars/config.env" 2>/dev/null || true
    sed -i '/^KUBECONFIG_PATH=/d' "${ROOT_DIR}/vars/config.env" 2>/dev/null || true

    # Append Jetlag configuration
    cat >> "${ROOT_DIR}/vars/config.env" <<EOF

# ========================================
# Jetlag Configuration
# ========================================
CLUSTER_TYPE=${CLUSTER_TYPE:-mno}
WORKER_NODE_COUNT=${WORKER_NODE_COUNT:-3}
OCP_BUILD=${OCP_BUILD:-ga}
OCP_VERSION=${OCP_VERSION:-latest-4.20}
NETWORK_STACK=${NETWORK_STACK:-ipv4}
LAB_SSH_USER=${LAB_SSH_USER:-root}
${LAB_SSH_PASSWORD:+LAB_SSH_PASSWORD=${LAB_SSH_PASSWORD}}
${BASTION_HOST:+BASTION_HOST=${BASTION_HOST}}
${KUBECONFIG_PATH:+KUBECONFIG_PATH=${KUBECONFIG_PATH}}
EOF

    echo -e "${GREEN}✓ Jetlag configuration written to vars/config.env${NC}"
fi

# Also write to JSON format
export REG_AGENT_ROOT="${ROOT_DIR}"
source "${ROOT_DIR}/modules/lib/json-config.sh" 2>/dev/null || true
if [ -f "${ROOT_DIR}/modules/lib/json-config.sh" ]; then
    json_set_multi ".jetlag" \
        "cluster_type=${CLUSTER_TYPE:-mno}" \
        "worker_node_count=${WORKER_NODE_COUNT:-3}" \
        "ocp_build=${OCP_BUILD:-ga}" \
        "ocp_version=${OCP_VERSION:-latest-4.20}" \
        "network_stack=${NETWORK_STACK:-ipv4}"

    json_set_multi ".lab" \
        "ssh_username=${LAB_SSH_USER:-root}" \
        "ssh_password=${LAB_SSH_PASSWORD:-}"

    [ -n "$BASTION_HOST" ] && json_set ".lab.bastion_host" "$BASTION_HOST"
    [ -n "$KUBECONFIG_PATH" ] && json_set ".jetlag.kubeconfig_path" "$KUBECONFIG_PATH"

    echo -e "${GREEN}✓ Jetlag configuration also written to vars/config.json${NC}"
fi

echo ""
