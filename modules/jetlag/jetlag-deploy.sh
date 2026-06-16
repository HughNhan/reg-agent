#!/bin/bash
# Jetlag Cluster Deployment with Stage Tracking and Auto-Resume
# Deploys new OpenShift cluster using Jetlag automation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REG_AGENT_ROOT="$ROOT_DIR"  # For compatibility with dependency library

# Generated directories
STATE_DIR="${SCRIPT_DIR}/generated/state"
LOG_DIR="${SCRIPT_DIR}/generated/logs"
OUTPUT_DIR="${SCRIPT_DIR}/generated/output"
mkdir -p "${STATE_DIR}" "${LOG_DIR}" "${OUTPUT_DIR}"

# Timestamped log for this run
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/deploy_${TIMESTAMP}.log"
STATE_FILE="${STATE_DIR}/current.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Load dependency checking library
source "${ROOT_DIR}/modules/lib/check-dependencies.sh"

#------------------------------------------------------------------------------
# Venv Validation Function
#------------------------------------------------------------------------------

ensure_jetlag_venv() {
    local jetlag_venv="${ROOT_DIR}/repos/jetlag/.ansible"

    # Check if venv exists and is functional
    if [ ! -d "$jetlag_venv" ]; then
        log "${YELLOW}Jetlag Python venv not found${NC}"
        log "Initializing Jetlag (this may take a few minutes)..."
        cd "${ROOT_DIR}/repos/jetlag"
        ./bootstrap.sh
        log "${GREEN}✓ Jetlag venv initialized${NC}"
    elif ! "$jetlag_venv/bin/ansible-playbook" --version &>/dev/null; then
        log "${YELLOW}Jetlag venv exists but is invalid/broken (possibly wrong paths)${NC}"
        log "Rebuilding Jetlag venv..."
        cd "${ROOT_DIR}/repos/jetlag"
        rm -rf .ansible
        ./bootstrap.sh
        log "${GREEN}✓ Jetlag venv rebuilt${NC}"
    fi
}

#------------------------------------------------------------------------------
# Logging Functions
#------------------------------------------------------------------------------

log() {
    echo -e "$@" | tee -a "$LOG_FILE"
}

log_no_newline() {
    echo -n -e "$@" | tee -a "$LOG_FILE"
}

#------------------------------------------------------------------------------
# State Management Functions
#------------------------------------------------------------------------------

# Mark stage complete
mark_stage_complete() {
    local stage_name=$1
    local stage_var="STAGE_${stage_name}"

    # Update state file
    sed -i "/^${stage_var}=/d" "$STATE_FILE" 2>/dev/null || true
    sed -i "/^${stage_var}_TIMESTAMP=/d" "$STATE_FILE" 2>/dev/null || true

    echo "${stage_var}=true" >> "$STATE_FILE"
    echo "${stage_var}_TIMESTAMP=$(date +%Y%m%d_%H%M%S)" >> "$STATE_FILE"

    log "${GREEN}✓ Stage ${stage_name} completed${NC}"
}

# Check if stage already complete
is_stage_complete() {
    local stage_name=$1
    local stage_var="STAGE_${stage_name}"

    if [ -f "$STATE_FILE" ]; then
        grep -q "^${stage_var}=true" "$STATE_FILE" 2>/dev/null
        return $?
    fi
    return 1
}

# Save value to state
save_state_var() {
    local var_name=$1
    local var_value=$2

    sed -i "/^${var_name}=/d" "$STATE_FILE" 2>/dev/null || true
    echo "${var_name}=${var_value}" >> "$STATE_FILE"
}

#------------------------------------------------------------------------------
# Initialize State File
#------------------------------------------------------------------------------

if [ ! -f "$STATE_FILE" ]; then
    cat > "$STATE_FILE" << EOF
JETLAG_STATUS=not_started
STAGE_INVENTORY_CREATED=false
STAGE_BASTION_SETUP=false
STAGE_CLUSTER_DEPLOY=false
EOF
fi

# Load current state
source "$STATE_FILE"

# Check for FORCE flag
FORCE_DEPLOY=${FORCE_DEPLOY:-false}

log ""
log "${BLUE}=========================================${NC}"
log "${BLUE}Jetlag Cluster Deployment${NC}"
log "${BLUE}=========================================${NC}"
log ""
log "Deployment script: $0"
log "Log file: $LOG_FILE"
log "State file: $STATE_FILE"
log "Force deploy: $FORCE_DEPLOY"
log ""

# Update status to in_progress
save_state_var "JETLAG_STATUS" "in_progress"

#------------------------------------------------------------------------------
# Dependency Checking
#------------------------------------------------------------------------------

log "Checking dependencies..."
log ""
reset_dep_check

# Repository dependencies
check_repo "jetlag"

# Check if we can source config (may not exist yet in some scenarios)
if [ -f "${ROOT_DIR}/vars/config.json" ]; then
    # Load JSON configuration
source "${ROOT_DIR}/modules/lib/json-config.sh"
json_export_env ".jetlag" ""
json_export_env ".lab" "LAB"
else
    log "${YELLOW}Warning: vars/config.json not found, will use environment variables${NC}"
fi

#------------------------------------------------------------------------------
# Input Resolution: Get CLOUD_NAME and LAB
#------------------------------------------------------------------------------

log "${BLUE}Resolving input variables...${NC}"
log ""

# Priority 1: Environment variables (for make deploy CLOUD_NAME=...)
if [[ -n "$CLOUD_NAME" ]]; then
    log "✓ Using CLOUD_NAME from environment: ${CLOUD_NAME}"

# Priority 2: Module-local override
elif [[ -f "$SCRIPT_DIR/generated/config/override.env" ]]; then
    source "$SCRIPT_DIR/generated/config/override.env"
    log "✓ Using CLOUD_NAME from module override: ${CLOUD_NAME}"

# Priority 3: Phase 1 QUADS state
elif [[ -f "$ROOT_DIR/modules/quads/generated/state/current.env" ]]; then
    source "$ROOT_DIR/modules/quads/generated/state/current.env"
    log "✓ Using CLOUD_NAME from Phase 1 QUADS: ${CLOUD_NAME}"

# Priority 4: Global state (fallback)
elif [[ -f "$ROOT_DIR/vars/state.env" ]]; then
    source "$ROOT_DIR/vars/state.env"
    log "✓ Using CLOUD_NAME from global state: ${CLOUD_NAME}"

else
    log "${RED}ERROR: CLOUD_NAME not found${NC}"
    log ""
    log "This typically means Phase 1 (QUADS) hasn't run yet."
    log ""
    log "Options:"
    log "  1. Run Phase 1 first:"
    log "     make test-quads"
    log ""
    log "  2. Provide CLOUD_NAME manually:"
    log "     make -C modules/jetlag deploy CLOUD_NAME=cloud42 LAB=scalelab"
    log ""
    log "  3. Create module override file:"
    log "     echo 'CLOUD_NAME=cloud42' > modules/jetlag/generated/config/override.env"
    log "     echo 'LAB=scalelab' >> modules/jetlag/generated/config/override.env"
    log ""
    log "  4. If you have an existing cluster, use import instead:"
    log "     make -C modules/jetlag import"
    log ""
    exit 1
fi

# Validate required variables
check_var "CLOUD_NAME" "CLOUD_NAME"
check_var "LAB" "LAB"

#------------------------------------------------------------------------------
# Auto-detect cluster type from QUADS allocation if not already set
#------------------------------------------------------------------------------

if [ -z "$CLUSTER_TYPE" ]; then
    log ""
    log "${BLUE}Auto-detecting cluster configuration from QUADS...${NC}"

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

    # Query hosts for this cloud
    if [ -n "$QUADS_TOKEN" ]; then
        HOSTS_JSON=$(curl -sk \
            -H "Authorization: Bearer ${QUADS_TOKEN}" \
            "https://${QUADS_API_SERVER}/api/v3/hosts?cloud=${CLOUD_NAME}" 2>/dev/null)

        NUM_HOSTS=$(echo "$HOSTS_JSON" | jq '. | length' 2>/dev/null || echo "0")

        if [ "$NUM_HOSTS" -gt 0 ]; then
            log "  ✓ Found ${NUM_HOSTS} hosts in ${CLOUD_NAME}"

            # Auto-determine cluster type based on node count
            if [ "$NUM_HOSTS" -eq 2 ]; then
                CLUSTER_TYPE="sno"
                WORKER_NODE_COUNT=0
                log "  ✓ Auto-detected: SNO (2 single-node clusters)"
            elif [ "$NUM_HOSTS" -ge 6 ]; then
                CLUSTER_TYPE="mno"
                WORKER_NODE_COUNT=$((NUM_HOSTS - 4))
                log "  ✓ Auto-detected: MNO (${WORKER_NODE_COUNT} workers)"
            else
                log "  ${YELLOW}Warning: ${NUM_HOSTS} hosts is not standard${NC}"
                log "  Defaulting to SNO"
                CLUSTER_TYPE="sno"
                WORKER_NODE_COUNT=0
            fi
        else
            log "  ${YELLOW}Could not query host count, using defaults${NC}"
        fi
    else
        log "  ${YELLOW}Could not authenticate to QUADS, using defaults${NC}"
    fi
    log ""
fi

# Configuration variables (with defaults)
CLUSTER_TYPE=${CLUSTER_TYPE:-mno}
OCP_BUILD=${OCP_BUILD:-ga}
OCP_VERSION=${OCP_VERSION:-latest-4.20}
NETWORK_STACK=${NETWORK_STACK:-ipv4}
WORKER_NODE_COUNT=${WORKER_NODE_COUNT:-3}

log ""
log "Deployment configuration:"
log "  CLOUD_NAME:        ${CLOUD_NAME}"
log "  LAB:               ${LAB}"
log "  CLUSTER_TYPE:      ${CLUSTER_TYPE}"
log "  OCP_BUILD:         ${OCP_BUILD}"
log "  OCP_VERSION:       ${OCP_VERSION}"
log "  NETWORK_STACK:     ${NETWORK_STACK}"
log "  WORKER_NODE_COUNT: ${WORKER_NODE_COUNT}"
log ""

# Save inputs to state
save_state_var "CLOUD_NAME" "$CLOUD_NAME"
save_state_var "LAB" "$LAB"
save_state_var "CLUSTER_TYPE" "$CLUSTER_TYPE"

# Required commands (ansible-playbook checked via venv in ensure_jetlag_venv)
check_command "AWK" "awk"
check_command "grep" "grep"
check_command "sed" "sed"

# Summarize and fail if dependencies not met
if ! summarize_deps "Phase 2: Jetlag Deployment"; then
    exit 1
fi

#------------------------------------------------------------------------------
# Stage 1: Create Inventory
#------------------------------------------------------------------------------

if is_stage_complete "INVENTORY_CREATED" && [ "$FORCE_DEPLOY" != "true" ]; then
    log "${GREEN}✓ Stage 1: Inventory already created, skipping${NC}"
    log "  (To re-run: make retry-inventory or make deploy-force)"
    log ""
else
    log "${BLUE}Stage 1: Creating Inventory${NC}"
    log "---------------------------------------------"
    log "Generating Jetlag inventory from QUADS cloud: ${CLOUD_NAME}"
    log ""

    # Ensure Jetlag venv is valid before proceeding
    ensure_jetlag_venv

    cd "${ROOT_DIR}/repos/jetlag"

    # Generate all.yml configuration
    log "Generating Jetlag configuration (ansible/vars/all.yml)..."

    cat > ansible/vars/all.yml << EOF
---
# Jetlag configuration generated by reg-agent
# Generated: $(date)

################################################################################
# Lab & cluster infrastructure vars
################################################################################
lab: ${LAB}
lab_cloud: ${CLOUD_NAME}
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

smcipmitool_url:

setup_bastion_gogs: false
setup_bastion_registry: false
use_bastion_registry: false
setup_bastion_proxy: false

setup_hv_metrics: false

################################################################################
# OCP node vars
################################################################################
enable_bond: false
enable_bond_vlan: false

################################################################################
# Extra vars
################################################################################
use_prega_content: false
EOF

    # Add IPv6-specific config if needed
    if [ "$NETWORK_STACK" = "ipv6" ] || [ "$NETWORK_STACK" = "dual" ]; then
        cat >> ansible/vars/all.yml << EOF

# IPv6 configuration
ipv6_enabled: true
EOF
    fi

    log "${GREEN}✓ Configuration generated${NC}"
    log ""

    # Run create-inventory playbook with retry logic for Foreman readiness
    log "Running create-inventory.yml..."
    log "This will query QUADS and generate inventory for ${CLOUD_NAME}..."
    log ""
    log "Note: Foreman may need time to provision the cloud after QUADS validation"
    log "      Will retry up to 10 times with 1-minute intervals if Foreman not ready"
    log ""

    MAX_RETRIES=10
    RETRY_INTERVAL=60
    ATTEMPT=1
    INVENTORY_SUCCESS=false

    while [ $ATTEMPT -le $MAX_RETRIES ]; do
        if [ $ATTEMPT -gt 1 ]; then
            log ""
            log "${YELLOW}Waiting ${RETRY_INTERVAL} seconds before retry...${NC}"
            sleep $RETRY_INTERVAL
            log ""
            log "${YELLOW}Attempt ${ATTEMPT}/${MAX_RETRIES}${NC} (Foreman may still be provisioning...)"
        fi

        # Capture playbook output to temp file for this attempt
        ATTEMPT_OUTPUT=$(mktemp)

        .ansible/bin/ansible-playbook -e "lab=${LAB}" -e "cloud=${CLOUD_NAME}" ansible/create-inventory.yml 2>&1 | tee -a "$LOG_FILE" | tee "$ATTEMPT_OUTPUT"
        PLAYBOOK_EXIT=$?

        # Check for failed tasks in PLAY RECAP (more reliable than exit code)
        if grep -q "failed=0" "$ATTEMPT_OUTPUT" 2>/dev/null && [ $PLAYBOOK_EXIT -eq 0 ]; then
            log ""
            log "${GREEN}✓ Inventory created successfully${NC}"

            # Extract bastion host from inventory
            INVENTORY_FILE="ansible/inventory/${CLOUD_NAME}.local"
            if [ -f "$INVENTORY_FILE" ]; then
                log "Inventory file: $INVENTORY_FILE"

                # Find bastion host (first host in bastion group or with bastion in name)
                BASTION_HOST=$(grep -A 10 "^\[bastion\]" "$INVENTORY_FILE" | grep -v "^\[" | grep -v "^#" | head -1 | awk '{print $1}' || true)

                if [ -z "$BASTION_HOST" ]; then
                    # Fallback: look for host with bastion in name
                    BASTION_HOST=$(grep -i "bastion" "$INVENTORY_FILE" | head -1 | awk '{print $1}' || true)
                fi

                if [ -z "$BASTION_HOST" ]; then
                    # Fallback: use first host
                    BASTION_HOST=$(grep -v "^\[" "$INVENTORY_FILE" | grep -v "^#" | grep -v "^$" | head -1 | awk '{print $1}')
                fi

                log "Bastion host: ${BASTION_HOST}"
                save_state_var "BASTION_HOST" "$BASTION_HOST"

                mark_stage_complete "INVENTORY_CREATED"
                INVENTORY_SUCCESS=true
                rm -f "$ATTEMPT_OUTPUT"
                log ""
                break
            else
                log ""
                log "${RED}✗ Inventory file not created: ${INVENTORY_FILE}${NC}"
                log "Playbook succeeded but inventory file is missing"
                save_state_var "JETLAG_STATUS" "failed"
                rm -f "$ATTEMPT_OUTPUT"
                exit 1
            fi

        else
            # Check if this is a Foreman authentication error (401)
            if grep -q "Status code was 401\|Unable to authenticate user" "$ATTEMPT_OUTPUT" 2>/dev/null; then
                if [ $ATTEMPT -lt $MAX_RETRIES ]; then
                    log ""
                    log "${YELLOW}⚠ Foreman not ready yet (authentication failed)${NC}"
                    log "   This is normal - Foreman needs time to provision the cloud allocation"
                    rm -f "$ATTEMPT_OUTPUT"
                    ATTEMPT=$((ATTEMPT + 1))
                    continue
                else
                    log ""
                    log "${RED}✗ Foreman still not ready after ${MAX_RETRIES} attempts${NC}"
                    save_state_var "JETLAG_STATUS" "failed"
                    rm -f "$ATTEMPT_OUTPUT"
                fi
            else
                # Different error, don't retry
                log ""
                log "${RED}✗ Inventory creation failed (not a Foreman timing issue)${NC}"
                save_state_var "JETLAG_STATUS" "failed"
                rm -f "$ATTEMPT_OUTPUT"
                log ""
                log "Common issues:"
                log "  - CLOUD_NAME not found in QUADS: ${CLOUD_NAME}"
                log "  - LAB incorrect: ${LAB} (should be 'scalelab' or 'performancelab')"
                log "  - Ansible vault password required"
                log "  - Network access to QUADS API"
                log ""
                log "To retry:"
                log "  make -C modules/jetlag retry-inventory"
                log "  OR"
                log "  make -C modules/jetlag deploy  # Auto-resumes"
                rm -f "$ATTEMPT_OUTPUT"
                exit 1
            fi
        fi
    done

    # If we exhausted retries without success
    if [ "$INVENTORY_SUCCESS" != "true" ]; then
        log ""
        log "${RED}✗ Inventory creation failed after ${MAX_RETRIES} attempts${NC}"
        save_state_var "JETLAG_STATUS" "failed"
        log ""
        log "To retry:"
        log "  make -C modules/jetlag retry-inventory"
        log "  OR"
        log "  make -C modules/jetlag deploy  # Auto-resumes"
        exit 1
    fi
fi

# Reload state (bastion may have been set)
source "$STATE_FILE"

#------------------------------------------------------------------------------
# Stage 1.5: Power On Hosts and Verify Connectivity
#------------------------------------------------------------------------------

if is_stage_complete "HOSTS_POWERED_ON" && [ "$FORCE_DEPLOY" != "true" ]; then
    log "${GREEN}✓ Stage 1.5: Hosts already powered on and verified, skipping${NC}"
    log ""
else
    log "${BLUE}Stage 1.5: Powering On Hosts and Verifying Connectivity${NC}"
    log "---------------------------------------------"
    log ""

    cd "${ROOT_DIR}/repos/jetlag"
    INVENTORY_FILE="ansible/inventory/${CLOUD_NAME}.local"

    # Extract BMC credentials from inventory
    BMC_USER=$(grep -A 5 "^\[bastion:vars\]" "$INVENTORY_FILE" | grep "^bmc_user=" | cut -d= -f2)
    BMC_PASSWORD=$(grep -A 5 "^\[bastion:vars\]" "$INVENTORY_FILE" | grep "^bmc_password=" | cut -d= -f2)

    # Extract bastion BMC address
    BASTION_BMC=$(grep -A 1 "^\[bastion\]" "$INVENTORY_FILE" | grep -v "^\[" | grep "bmc_address=" | sed 's/.*bmc_address=\([^ ]*\).*/\1/')

    # SSH password for lab hosts (different from BMC password)
    # Must be configured in vars/config.json during 'make configure'
    LAB_SSH_PASSWORD=${LAB_SSH_PASSWORD:-""}

    if [ -n "$BASTION_BMC" ] && [ -n "$BMC_USER" ] && [ -n "$BMC_PASSWORD" ]; then
        log "Powering on bastion via BMC..."
        log "  Bastion: ${BASTION_HOST}"
        log "  BMC: ${BASTION_BMC}"

        # Try badfish first (Redfish via podman), fall back to ipmitool
        POWER_ON_SUCCESS=false

        if command -v podman &> /dev/null; then
            log "Using badfish (Redfish) to power on..."
            if podman run --rm quay.io/quads/badfish \
                -H "$BASTION_BMC" -u "$BMC_USER" -p "$BMC_PASSWORD" \
                --insecure --power-on &>/dev/null; then
                log "${GREEN}✓ Power on command sent via badfish${NC}"
                POWER_ON_SUCCESS=true
            else
                log "${YELLOW}⚠ badfish failed, trying ipmitool...${NC}"
            fi
        fi

        # Fallback to ipmitool if badfish not available or failed
        if [ "$POWER_ON_SUCCESS" = "false" ] && command -v ipmitool &> /dev/null; then
            log "Using ipmitool (IPMI) to power on..."
            if ipmitool -I lanplus -H "$BASTION_BMC" -U "$BMC_USER" -P "$BMC_PASSWORD" chassis power on &>/dev/null; then
                log "${GREEN}✓ Power on command sent via ipmitool${NC}"
                POWER_ON_SUCCESS=true
            fi
        fi

        if [ "$POWER_ON_SUCCESS" = "false" ]; then
            log "${YELLOW}⚠ Could not send power-on command (no podman or ipmitool)${NC}"
            log "  Install podman: yum install -y podman"
            log "  OR install ipmitool: yum install -y ipmitool"
        fi
    else
        log "${YELLOW}⚠ Could not extract BMC credentials from inventory${NC}"
    fi

    # Wait for bastion to be accessible (ping first, then SSH)
    log ""
    log "Waiting for bastion to be accessible..."
    log "  Host: ${BASTION_HOST}"
    log ""

    MAX_WAIT=600  # 10 minutes
    ELAPSED=0
    PING_INTERVAL=10
    PING_SUCCESS=false

    # Phase 1: Wait for ping response (host is booting)
    log "Phase 1: Waiting for network connectivity (ping)..."
    while [ $ELAPSED -lt $MAX_WAIT ] && [ "$PING_SUCCESS" = "false" ]; do
        if ping -c 1 -W 2 "$BASTION_HOST" &>/dev/null; then
            log "${GREEN}✓ Bastion is responding to ping${NC}"
            PING_SUCCESS=true
            break
        fi
        log "  Waiting for ping... (${ELAPSED}s / ${MAX_WAIT}s)"
        sleep $PING_INTERVAL
        ELAPSED=$((ELAPSED + PING_INTERVAL))
    done

    if [ "$PING_SUCCESS" = "false" ]; then
        log ""
        log "${RED}✗ Bastion not reachable via ping after ${MAX_WAIT}s${NC}"
        log ""
        log "Possible issues:"
        log "  1. Host failed to power on (check BMC)"
        log "  2. Network connectivity issues"
        log "  3. Wrong hostname/IP in inventory"
        log ""
        log "Debug commands:"
        log "  # Check power status:"
        log "  podman run --rm quay.io/quads/badfish -H ${BASTION_BMC} -u ${BMC_USER} -p <password> --insecure --check-power"
        log "  # Try ping manually:"
        log "  ping ${BASTION_HOST}"
        log ""
        exit 1
    fi

    # Phase 2: Wait for SSH access (OS is booting)
    log ""
    log "Phase 2: Waiting for SSH access..."

    SSH_SUCCESS=false
    while [ $ELAPSED -lt $MAX_WAIT ] && [ "$SSH_SUCCESS" = "false" ]; do
        # Try key-based auth first, then password-based
        if ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no "root@${BASTION_HOST}" "echo ok" &>/dev/null; then
            log "${GREEN}✓ Bastion is SSH accessible (key-based)${NC}"
            SSH_SUCCESS=true
            break
        elif [ -n "$LAB_SSH_PASSWORD" ] && command -v sshpass &> /dev/null; then
            if sshpass -p "$LAB_SSH_PASSWORD" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@${BASTION_HOST}" "echo ok" &>/dev/null; then
                log "${GREEN}✓ Bastion is SSH accessible (password)${NC}"
                # Copy SSH key now that we can connect
                sshpass -p "$LAB_SSH_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no "root@${BASTION_HOST}" &>/dev/null || true
                log "${GREEN}✓ SSH key copied${NC}"
                SSH_SUCCESS=true
                break
            fi
        fi
        log "  Waiting for SSH... (${ELAPSED}s / ${MAX_WAIT}s)"
        sleep $PING_INTERVAL
        ELAPSED=$((ELAPSED + PING_INTERVAL))
    done

    if [ "$SSH_SUCCESS" = "true" ]; then
        mark_stage_complete "HOSTS_POWERED_ON"
    else
        log ""
        log "${RED}✗ Bastion SSH not accessible after ${MAX_WAIT}s${NC}"
        log ""
        log "Possible issues:"
        log "  1. SSH service not started yet (still booting)"
        log "  2. Firewall blocking SSH port 22"
        log "  3. Wrong SSH credentials"
        log "  4. SELinux blocking SSH access"
        log ""
        log "Manual troubleshooting:"
        log "  # Try SSH manually:"
        log "  ssh root@${BASTION_HOST}"
        log ""
        log "  # Check if SSH port is open:"
        log "  nc -zv ${BASTION_HOST} 22"
        log ""
        exit 1
    fi

    log ""
fi

#------------------------------------------------------------------------------
# Stage 2: Setup Bastion
#------------------------------------------------------------------------------

if is_stage_complete "BASTION_SETUP" && [ "$FORCE_DEPLOY" != "true" ]; then
    log "${GREEN}✓ Stage 2: Bastion already setup, skipping${NC}"
    log "  (To re-run: make retry-bastion or make deploy-force)"
    log ""
else
    log "${BLUE}Stage 2: Setting Up Bastion${NC}"
    log "---------------------------------------------"
    log "Bastion host: ${BASTION_HOST}"
    log ""
    log "This will install on bastion:"
    log "  - Assisted Installer service"
    log "  - DNS server (dnsmasq)"
    log "  - HTTP server for ignition files"
    log "  - Optional: Registry/Proxy (IPv6 mode)"
    log ""

    cd "${ROOT_DIR}/repos/jetlag"

    # Copy pull secret if exists
    if [ -n "$PULL_SECRET_PATH" ] && [ -f "$PULL_SECRET_PATH" ]; then
        log "Copying pull secret..."
        cp "$PULL_SECRET_PATH" pull-secret.txt
    elif [ -f "${ROOT_DIR}/pull-secret.txt" ]; then
        log "Using pull secret from repo root..."
        cp "${ROOT_DIR}/pull-secret.txt" pull-secret.txt
    else
        log "${YELLOW}Warning: No pull secret found${NC}"
        log "  Looked at: $PULL_SECRET_PATH"
        log "  Looked at: ${ROOT_DIR}/pull-secret.txt"
    fi

    # Run setup-bastion playbook
    log "Running setup-bastion.yml..."
    log "This may take 10-20 minutes..."
    log ""

    if timeout 1800 .ansible/bin/ansible-playbook -i ansible/inventory/${CLOUD_NAME}.local ansible/setup-bastion.yml 2>&1 | tee -a "$LOG_FILE"; then
        log ""
        log "${GREEN}✓ Bastion setup completed successfully${NC}"
        mark_stage_complete "BASTION_SETUP"
        log ""

    else
        log ""
        log "${RED}✗ Bastion setup failed${NC}"
        save_state_var "JETLAG_STATUS" "failed"
        log ""
        log "Common issues:"
        log "  - DNS configuration failure"
        log "  - Assisted Installer download failure"
        log "  - Registry setup failure (IPv6 disconnected mode)"
        log "  - Firewall blocking required ports"
        log ""
        log "To debug:"
        log "  ssh root@${BASTION_HOST}"
        log "  systemctl status assisted-installer"
        log "  journalctl -u assisted-installer -f"
        log ""
        log "To retry:"
        log "  make -C modules/jetlag retry-bastion"
        log "  OR"
        log "  make -C modules/jetlag deploy  # Auto-resumes"
        exit 1
    fi
fi

#------------------------------------------------------------------------------
# Stage 3: Deploy Cluster
#------------------------------------------------------------------------------

if is_stage_complete "CLUSTER_DEPLOY" && [ "$FORCE_DEPLOY" != "true" ]; then
    log "${GREEN}✓ Stage 3: Cluster already deployed, skipping${NC}"
    log ""
else
    log "${BLUE}Stage 3: Deploying OpenShift Cluster${NC}"
    log "---------------------------------------------"
    log "Cluster type: ${CLUSTER_TYPE}"
    log ""

    cd "${ROOT_DIR}/repos/jetlag"

    # Determine playbook based on cluster type
    if [ "$CLUSTER_TYPE" = "sno" ]; then
        DEPLOY_PLAYBOOK="sno-deploy.yml"
        KUBECONFIG_PATH="/root/sno/kubeconfig"
    else
        DEPLOY_PLAYBOOK="mno-deploy.yml"
        KUBECONFIG_PATH="/root/mno/kubeconfig"
    fi

    log "Running ${DEPLOY_PLAYBOOK}..."
    log "This may take 30-60 minutes..."
    log "Progress: Installing OpenShift ${OCP_VERSION} (${OCP_BUILD})..."
    log ""

    # 2 hour timeout for cluster deployment
    if timeout 7200 .ansible/bin/ansible-playbook -i ansible/inventory/${CLOUD_NAME}.local ansible/${DEPLOY_PLAYBOOK} 2>&1 | tee -a "$LOG_FILE"; then
        log ""
        log "${GREEN}✓ Cluster deployment completed successfully${NC}"

        # Save final state
        save_state_var "KUBECONFIG_PATH" "$KUBECONFIG_PATH"
        save_state_var "JETLAG_STATUS" "completed"
        save_state_var "DEPLOYMENT_METHOD" "jetlag"
        save_state_var "JETLAG_DEPLOY_COMPLETED" "true"
        save_state_var "JETLAG_DEPLOY_TIMESTAMP" "$(date -u +%Y%m%d_%H%M%S)"

        mark_stage_complete "CLUSTER_DEPLOY"
        log ""

    else
        log ""
        log "${RED}✗ Cluster deployment failed${NC}"
        save_state_var "JETLAG_STATUS" "failed"
        log ""
        log "Common issues:"
        log "  - BMC access failure (check BMC credentials)"
        log "  - Insufficient hosts (need 3+ control plane + N workers for MNO)"
        log "  - Network connectivity issues"
        log "  - OpenShift version not available: ${OCP_VERSION}"
        log "  - Timeout waiting for nodes to boot"
        log "  - Assisted Installer API errors"
        log ""
        log "To debug:"
        log "  ssh root@${BASTION_HOST}"
        log "  tail -f /root/assisted-installer.log"
        log "  # Check if nodes are attempting to boot:"
        log "  curl -s http://localhost:8080/api/assisted-install/v2/clusters | jq"
        log ""
        log "To retry:"
        log "  make -C modules/jetlag retry-cluster"
        log "  OR"
        log "  make -C modules/jetlag deploy  # Auto-resumes"
        exit 1
    fi
fi

# Reload final state
source "$STATE_FILE"

#------------------------------------------------------------------------------
# Sync to Global State
#------------------------------------------------------------------------------

log "Syncing state to global state file..."

# Copy relevant variables to global state
cat >> "${ROOT_DIR}/vars/state.env" << EOF

# Phase 2: Jetlag Deployment (added $(date))
CLOUD_NAME=${CLOUD_NAME}
LAB=${LAB}
BASTION_HOST=${BASTION_HOST}
KUBECONFIG_PATH=${KUBECONFIG_PATH}
CLUSTER_TYPE=${CLUSTER_TYPE}
DEPLOYMENT_METHOD=jetlag
JETLAG_DEPLOY_COMPLETED=true
JETLAG_DEPLOY_TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
EOF

log "${GREEN}✓ State synced to ${ROOT_DIR}/vars/state.env${NC}"
log ""

#------------------------------------------------------------------------------
# Success Summary
#------------------------------------------------------------------------------

log "${GREEN}=========================================${NC}"
log "${GREEN}Jetlag Deployment Complete!${NC}"
log "${GREEN}=========================================${NC}"
log ""
log "Cluster details:"
log "  Cloud:      ${CLOUD_NAME}"
log "  Lab:        ${LAB}"
log "  Bastion:    ${BASTION_HOST}"
log "  Kubeconfig: ${KUBECONFIG_PATH}"
log "  Type:       ${CLUSTER_TYPE}"
log ""
log "State saved to:"
log "  - ${STATE_FILE}"
log "  - ${ROOT_DIR}/vars/state.env"
log ""
log "Verify cluster:"
log "  ssh root@${BASTION_HOST}"
log "  oc --kubeconfig=${KUBECONFIG_PATH} get nodes"
log ""
log "Next phase:"
log "  make test-crucible"
log ""
