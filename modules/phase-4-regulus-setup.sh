#!/bin/bash
# Phase 4: Regulus Setup
# Configures Regulus on bastion with auto-generated configs

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
json_export_env ".regulus" "REGULUS"
json_export_env ".lab" "LAB"

# Source state
if [ ! -f "${REG_AGENT_ROOT}/vars/state.env" ]; then
    echo -e "${RED}Error: State file not found${NC}"
    echo "This should be created by Phase 1/2/3"
    exit 1
fi

# Capture existing REGULUS_PATH before sourcing state (to compare later)
REGULUS_PATH_FROM_STATE=$(grep "^REGULUS_PATH=" "${REG_AGENT_ROOT}/vars/state.env" 2>/dev/null | tail -1 | cut -d= -f2)

source "${REG_AGENT_ROOT}/vars/state.env"

# Load dependency checking library
source "${REG_AGENT_ROOT}/modules/lib/check-dependencies.sh"

# Load logging library
source "${REG_AGENT_ROOT}/modules/lib/logging.sh"
init_logging "regulus" "phase-4-regulus-setup"

# Log configuration and state loading
log "Configuration loaded from: ${REG_AGENT_ROOT}/vars/config.json"
log "State loaded from: ${REG_AGENT_ROOT}/vars/state.env"

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Phase 4: Regulus Setup${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
log "========================================"
log "Phase 4: Regulus Setup"
log "========================================"

#------------------------------------------------------------------------------
# Determine Installation Host
#------------------------------------------------------------------------------
log "Determining installation host..."
CRUCIBLE_CONTROLLER_TARGET=${CRUCIBLE_CONTROLLER_TARGET:-bastion}

if [ "$CRUCIBLE_CONTROLLER_TARGET" = "bastion" ]; then
    # Use bastion from Jetlag deployment
    CRUCIBLE_CONTROLLER_HOST="$BASTION_HOST"
    CRUCIBLE_CONTROLLER_USER="root"
    echo "Controller target: Cluster bastion"
    log "Controller target: Cluster bastion (${CRUCIBLE_CONTROLLER_HOST})"
elif [ "$CRUCIBLE_CONTROLLER_TARGET" = "other" ]; then
    # Use user-specified host
    CRUCIBLE_CONTROLLER_HOST="$CRUCIBLE_CONTROLLER_OTHER_HOST"
    CRUCIBLE_CONTROLLER_USER="${CRUCIBLE_CONTROLLER_USER:-root}"
    echo "Controller target: Other server"
    log "Controller target: Other server (${CRUCIBLE_CONTROLLER_HOST})"
else
    echo -e "${RED}Error: Invalid CRUCIBLE_CONTROLLER_TARGET: $CRUCIBLE_CONTROLLER_TARGET${NC}"
    log "ERROR: Invalid CRUCIBLE_CONTROLLER_TARGET: $CRUCIBLE_CONTROLLER_TARGET"
    exit 1
fi

# Set default for REG_KNI_USER (user that runs Regulus commands on bastion)
# Typically same as CRUCIBLE_CONTROLLER_USER (root on bastion)
REG_KNI_USER=${REG_KNI_USER:-$CRUCIBLE_CONTROLLER_USER}
export REG_KNI_USER
log "REG_KNI_USER set to: ${REG_KNI_USER}"

#------------------------------------------------------------------------------
# Determine Regulus Installation Path
#------------------------------------------------------------------------------
log "Determining Regulus installation path..."
# Use provided timestamp or generate in local timezone
# When called from workspace, REGULUS_TIMESTAMP can be pre-set to use workspace timezone
TIMESTAMP=${REGULUS_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}
REGULUS_INSTALL_SUBDIR=${REGULUS_INSTALL_SUBDIR:-}

if [ -n "$REGULUS_INSTALL_SUBDIR" ]; then
    REGULUS_PATH="/root/${REGULUS_INSTALL_SUBDIR}/cpt-regulus-${TIMESTAMP}"
else
    REGULUS_PATH="/root/cpt-regulus-${TIMESTAMP}"
fi

echo "Regulus will be installed to: ${REGULUS_PATH}"
log "Regulus installation path: ${REGULUS_PATH}"
echo ""

# Check dependencies
echo "Checking Phase 4 dependencies..."
log "Checking Phase 4 dependencies..."
echo ""
reset_dep_check

# Required state variables from previous phases
if [ "$CRUCIBLE_CONTROLLER_TARGET" = "bastion" ]; then
    check_var "Bastion host (from Jetlag)" "BASTION_HOST"
    check_var "Kubeconfig path" "KUBECONFIG_PATH"
else
    check_var "Controller host" "CRUCIBLE_CONTROLLER_OTHER_HOST"
    # KUBECONFIG_PATH may be provided by user or from Jetlag
    if [ -z "$KUBECONFIG_PATH" ]; then
        echo -e "${YELLOW}⚠  KUBECONFIG_PATH not set - you'll need to provide it${NC}"
    fi
fi

# SSH access to installation host
check_ssh "Controller host" "$CRUCIBLE_CONTROLLER_HOST"

# Check if Crucible command is available (required dependency)
if ! ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} "command -v crucible &>/dev/null"; then
    echo -e "${RED}✗${NC} Crucible command not available on ${CRUCIBLE_CONTROLLER_HOST}"
    echo "   Install Crucible first (Phase 3)"
    DEP_FAILED=$((DEP_FAILED + 1))
else
    echo -e "${GREEN}✓${NC} Crucible command available"
    DEP_PASSED=$((DEP_PASSED + 1))
fi

# Required commands
check_command "SSH" "ssh"
check_command "SCP" "scp"
check_command "Tar" "tar"

echo ""
echo "Regulus-specific checks:"
log "Regulus-specific checks..."

# Check for bc command on Regulus host (required for Regulus calculations)
echo -n "  Checking bc (calculator) on Regulus host... "
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Check: bc (calculator) availability on Regulus host"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  Regulus host: ${CRUCIBLE_CONTROLLER_HOST}"
log "  bc is required for Regulus performance calculations"
log ""

BC_CHECK=$(ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} "command -v bc >/dev/null 2>&1 && echo 'INSTALLED' || echo 'NOT_INSTALLED'")

if [ "$BC_CHECK" = "INSTALLED" ]; then
    echo -e "${GREEN}✓${NC}"
    log "  ✓ bc is installed on Regulus host"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    DEPS_PASSED=$((DEPS_PASSED + 1))
else
    echo -e "${YELLOW}⚠${NC} (installing...)"
    log "  ⚠ bc not found - installing..."

    # Install bc
    BC_INSTALL=$(ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} "yum install -y bc 2>&1")
    log "  Installation output:"
    log "${BC_INSTALL}"

    # Verify installation
    BC_VERIFY=$(ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} "command -v bc >/dev/null 2>&1 && echo 'OK' || echo 'FAILED'")

    if [ "$BC_VERIFY" = "OK" ]; then
        echo "    ✓ bc installed successfully"
        log "  ✓ bc installed successfully"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        DEPS_PASSED=$((DEPS_PASSED + 1))
    else
        echo -e "    ${RED}✗ Failed to install bc${NC}"
        echo "    Manual installation required: ssh root@${CRUCIBLE_CONTROLLER_HOST} 'yum install -y bc'"
        log "  ✗ bc installation failed"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        DEPS_FAILED=$((DEPS_FAILED + 1))
    fi
fi

# Pre-check: Detect cluster type and validate worker label configuration
echo -n "  Detecting cluster type and worker configuration... "
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Pre-check: Cluster Type Detection and Worker Label Configuration"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  Analyzing cluster to determine correct worker selection criteria..."

# Get all nodes and their roles
CLUSTER_ANALYSIS=$(ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} bash <<CLUSTER_CHECK
export KUBECONFIG="${KUBECONFIG_PATH}"

# Count total nodes
TOTAL_NODES=\$(oc get nodes --no-headers 2>&1 | wc -l)

# Count nodes with worker role
WORKER_NODES=\$(oc get nodes -l node-role.kubernetes.io/worker= --no-headers 2>&1 | wc -l)

# Count nodes with both worker AND control-plane roles
WORKER_CP_NODES=\$(oc get nodes -l node-role.kubernetes.io/worker=,node-role.kubernetes.io/control-plane= --no-headers 2>&1 | wc -l)

# Count dedicated workers (worker role but NOT control-plane)
DEDICATED_WORKERS=\$(oc get nodes -l node-role.kubernetes.io/worker= --no-headers 2>&1 | \
  while read name rest; do
    if ! oc get node \$name -o jsonpath='{.metadata.labels}' 2>&1 | grep -q "node-role.kubernetes.io/control-plane"; then
      echo \$name
    fi
  done | wc -l)

echo "TOTAL_NODES=\$TOTAL_NODES"
echo "WORKER_NODES=\$WORKER_NODES"
echo "WORKER_CP_NODES=\$WORKER_CP_NODES"
echo "DEDICATED_WORKERS=\$DEDICATED_WORKERS"
CLUSTER_CHECK
)

# Parse the results
eval "$CLUSTER_ANALYSIS"

log "  Cluster analysis results:"
log "    Total nodes: ${TOTAL_NODES}"
log "    Nodes with worker role: ${WORKER_NODES}"
log "    Nodes with worker+control-plane: ${WORKER_CP_NODES}"
log "    Dedicated worker nodes: ${DEDICATED_WORKERS}"

# Determine cluster type
if [ "$TOTAL_NODES" -eq 1 ] && [ "$WORKER_CP_NODES" -eq 1 ]; then
    DETECTED_CLUSTER_TYPE="SNO"
    NEEDS_LABEL_FIX="yes"
    log "  Detected: Single Node OpenShift (SNO)"
elif [ "$WORKER_NODES" -eq "$WORKER_CP_NODES" ] && [ "$DEDICATED_WORKERS" -eq 0 ]; then
    DETECTED_CLUSTER_TYPE="Compact MNO"
    NEEDS_LABEL_FIX="yes"
    log "  Detected: Compact Multi-Node OpenShift (all nodes are control-plane+worker)"
elif [ "$DEDICATED_WORKERS" -gt 0 ]; then
    DETECTED_CLUSTER_TYPE="Standard MNO"
    NEEDS_LABEL_FIX="no"
    log "  Detected: Standard Multi-Node OpenShift (dedicated workers)"
else
    DETECTED_CLUSTER_TYPE="Unknown"
    NEEDS_LABEL_FIX="maybe"
    log "  WARNING: Could not determine cluster type"
fi

log ""
log "  Cluster type: ${DETECTED_CLUSTER_TYPE}"
log "  Requires worker label configuration fix: ${NEEDS_LABEL_FIX}"

if [ "$NEEDS_LABEL_FIX" = "yes" ]; then
    echo -e "${YELLOW}⚠${NC}"
    echo "    Detected: ${DETECTED_CLUSTER_TYPE}"
    echo "    Action required: Worker label configuration needs adjustment"
    echo ""
    log "  ⚠ Worker label configuration incompatible with ${DETECTED_CLUSTER_TYPE}"
    log "  Default worker_labels.config excludes control-plane nodes"
    log "  This will cause reg-smart-config to fail with 'No worker nodes found'"
    DEPS_PASSED=$((DEPS_PASSED + 1))  # Warning, not failure
else
    echo -e "${GREEN}✓${NC}"
    log "  ✓ Cluster type compatible with default worker label configuration"
    DEPS_PASSED=$((DEPS_PASSED + 1))
fi

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check 1: Passwordless SSH from Regulus host to bastion (REG_OCPHOST) as REG_KNI_USER
# REG_OCPHOST will be set to CRUCIBLE_CONTROLLER_HOST (which could be bastion or another host)
echo -n "  Checking passwordless SSH on Regulus host to bastion... "
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Check 1: Passwordless SSH from Regulus host to bastion (REG_OCPHOST)"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  Current host (reg-agent client): $(hostname)"
log "  Regulus host: ${CRUCIBLE_CONTROLLER_HOST}"
log "  REG_OCPHOST (bastion): ${CRUCIBLE_CONTROLLER_HOST}"
log "  SSH test command: ssh ${REG_KNI_USER}@${CRUCIBLE_CONTROLLER_HOST}"
log ""

# First verify REG_KNI_USER is set
if [ -z "$REG_KNI_USER" ]; then
    echo -e "${RED}✗${NC}"
    echo "    REG_KNI_USER not set in config"
    log "  ERROR: REG_KNI_USER not set in config"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    DEPS_FAILED=$((DEPS_FAILED + 1))
else
    # Test SSH connection FROM Regulus host TO bastion as REG_KNI_USER
    # This runs ON the Regulus host to test if it can SSH to the bastion
    log "  Executing test on Regulus host..."
    log "  Command: ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} \"ssh -o BatchMode=yes ${REG_KNI_USER}@${CRUCIBLE_CONTROLLER_HOST} 'hostname'\""

    SSH_TEST_RESULT=$(ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} "echo 'On Regulus host: '\$(hostname) && ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no ${REG_KNI_USER}@${CRUCIBLE_CONTROLLER_HOST} 'echo Connected to: \$(hostname)' 2>&1" || echo "SSH_FAILED")

    log "  Test output:"
    log "${SSH_TEST_RESULT}"
    log ""

    if echo "$SSH_TEST_RESULT" | grep -q "Connected to:"; then
        echo -e "${GREEN}✓${NC}"
        log "  ✓ Result: PASS - Passwordless SSH works"
        log "    ${REG_KNI_USER}@${CRUCIBLE_CONTROLLER_HOST} is accessible from Regulus host"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        DEPS_PASSED=$((DEPS_PASSED + 1))
    else
        echo -e "${RED}✗${NC}"
        echo "    Regulus host cannot SSH to bastion as ${REG_KNI_USER}@${CRUCIBLE_CONTROLLER_HOST} without password"
        echo "    This is required for Regulus to access the cluster"
        echo ""
        echo "    Error details:"
        echo "${SSH_TEST_RESULT}" | sed 's/^/      /'
        echo ""
        log "  ✗ Result: FAIL - Passwordless SSH failed"
        log "  Error output: ${SSH_TEST_RESULT}"

        # Offer auto-fix
        echo "    Attempting auto-fix..."
        echo "    Setting up passwordless SSH..."
        log "  Attempting auto-fix: Adding public key to authorized_keys"

        # First, ensure SSH key exists on Regulus host
        ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} bash <<'AUTOFIX_PREP'
# Check if SSH key exists, create if not
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "  → Generating SSH key on Regulus host..."
    ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa -q
    echo "  ✓ SSH key generated"
else
    echo "  ✓ SSH key already exists"
fi
AUTOFIX_PREP

        # Now copy the key to bastion
        echo "    Copying SSH key to authorized_keys..."
        log "  Appending public key to ${REG_KNI_USER}@${CRUCIBLE_CONTROLLER_HOST}:~/.ssh/authorized_keys"

        # Since we're on the Regulus host and bastion might be the same machine,
        # we can directly append the public key to authorized_keys
        COPY_RESULT=$(ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} bash <<'SSHCOPY' 2>&1
# Ensure .ssh directory exists with correct permissions
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Append public key to authorized_keys if not already present
if [ -f ~/.ssh/id_rsa.pub ]; then
    if ! grep -q -f ~/.ssh/id_rsa.pub ~/.ssh/authorized_keys 2>/dev/null; then
        cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        echo "✓ Public key added to authorized_keys"
    else
        echo "✓ Public key already in authorized_keys"
    fi
else
    echo "✗ Public key not found"
    exit 1
fi
SSHCOPY
)

        log "  authorized_keys update:"
        log "${COPY_RESULT}"

        # Re-test SSH after auto-fix
        echo "    Re-testing SSH connection..."
        log "  Re-testing SSH after auto-fix..."

        SSH_RETEST=$(ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} "ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no ${REG_KNI_USER}@${CRUCIBLE_CONTROLLER_HOST} 'echo Connected to: \$(hostname)' 2>&1" || echo "SSH_FAILED")

        log "  Re-test output: ${SSH_RETEST}"

        if echo "$SSH_RETEST" | grep -q "Connected to:"; then
            echo -e "    ${GREEN}✓ Auto-fix successful! Passwordless SSH now works${NC}"
            log "  ✓ Auto-fix successful! SSH connection now works"
            log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            DEPS_PASSED=$((DEPS_PASSED + 1))
        else
            echo -e "    ${RED}✗ Auto-fix failed${NC}"
            echo "    You may need to manually set up SSH keys"
            echo ""
            echo "    Manual fix: On Regulus host (${CRUCIBLE_CONTROLLER_HOST}), run:"
            echo "      ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST}"
            echo "      ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa  # If no key exists"
            echo "      ssh-copy-id ${REG_KNI_USER}@${CRUCIBLE_CONTROLLER_HOST}"
            echo ""
            log "  ✗ Auto-fix failed - manual intervention required"
            log "  Re-test output: ${SSH_RETEST}"
            log "  Manual fix required: ssh-copy-id ${REG_KNI_USER}@${CRUCIBLE_CONTROLLER_HOST}"
            log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            DEPS_FAILED=$((DEPS_FAILED + 1))
        fi
    fi
fi

# Check 2: SSH from bastion to worker nodes as core user
echo -n "  Checking SSH from bastion to worker nodes... "
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Check 2: SSH from Bastion to Worker Nodes"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  Bastion: ${CRUCIBLE_CONTROLLER_HOST}"
log "  Target user: core (CoreOS default for workers)"
log "  Detecting worker nodes from cluster..."
log ""

# Get worker nodes from cluster
WORKER_CHECK=$(ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} bash <<WORKER_SSH_CHECK
export KUBECONFIG="${KUBECONFIG_PATH}"
export DETECTED_CLUSTER_TYPE="${DETECTED_CLUSTER_TYPE}"

# Get worker node names (use the ones that will pass worker_labels filter)
if [ "\${DETECTED_CLUSTER_TYPE}" = "SNO" ] || [ "\${DETECTED_CLUSTER_TYPE}" = "Compact MNO" ]; then
    # For SNO/Compact, all nodes with worker label (including control-plane)
    WORKERS=\$(oc get nodes -l node-role.kubernetes.io/worker= -o jsonpath='{.items[*].metadata.name}' 2>&1)
else
    # For Standard MNO, only dedicated workers (exclude control-plane)
    WORKERS=\$(oc get nodes -l node-role.kubernetes.io/worker= -o jsonpath='{.items[*].metadata.name}' 2>&1 | tr ' ' '\n' | while read node; do
        if ! oc get node \$node -o jsonpath='{.metadata.labels}' 2>&1 | grep -q "node-role.kubernetes.io/control-plane"; then
            echo \$node
        fi
    done | tr '\n' ' ')
fi

# Test SSH to each worker
SSH_FAILURES=0
SSH_SUCCESS=0

for worker in \$WORKERS; do
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no core@\${worker} 'echo OK' >/dev/null 2>&1; then
        SSH_SUCCESS=\$((SSH_SUCCESS + 1))
    else
        SSH_FAILURES=\$((SSH_FAILURES + 1))
    fi
done

# Output only the variables we need to parse
echo "WORKERS=\"\${WORKERS}\""
echo "SSH_SUCCESS=\${SSH_SUCCESS}"
echo "SSH_FAILURES=\${SSH_FAILURES}"
WORKER_SSH_CHECK
)

# Parse results - source the output instead of eval
source <(echo "$WORKER_CHECK")

log "  Worker SSH check results:"
log "    Workers detected: ${WORKERS}"
log "    Successful: ${SSH_SUCCESS}"
log "    Failed: ${SSH_FAILURES}"
log ""

if [ "$SSH_FAILURES" -eq 0 ] && [ "$SSH_SUCCESS" -gt 0 ]; then
    echo -e "${GREEN}✓${NC}"
    log "  ✓ Result: PASS - Bastion can SSH to all worker nodes as core"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    DEPS_PASSED=$((DEPS_PASSED + 1))
else
    echo -e "${YELLOW}⚠${NC}"
    echo "    WARNING: Bastion cannot SSH to worker nodes as core user"
    echo "    This will be required for init-lab (INVENTORY) in Phase 5"
    echo ""
    echo "    Workers detected: ${WORKERS}"
    echo "    Successful: ${SSH_SUCCESS}"
    echo "    Failed: ${SSH_FAILURES}"
    echo ""
    log "  ⚠ Result: WARNING - SSH to workers failed"
    log "    Workers: ${WORKERS}"
    log "    Success: ${SSH_SUCCESS}, Failures: ${SSH_FAILURES}"

    # This is usually configured by Jetlag during cluster deployment
    # Manual fix instructions
    echo ""
    echo -e "    ${YELLOW}Note: This SSH access is typically configured during cluster deployment${NC}"
    echo "    If init-lab fails in Phase 5, fix with one of these options:"
    echo ""
    echo "    Option 1: SSH copy-id (if you have worker password):"
    echo "      ssh root@${CRUCIBLE_CONTROLLER_HOST}"
    for worker in $WORKERS; do
        echo "      ssh-copy-id core@${worker}"
    done
    echo ""
    echo "    Option 2: Check if already configured (test manually):"
    echo "      ssh root@${CRUCIBLE_CONTROLLER_HOST}"
    for worker in $WORKERS; do
        echo "      ssh core@${worker} hostname"
    done
    echo ""
    log "  Note: Treating as WARNING - will be validated again in Phase 5 before init-lab"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    DEPS_PASSED=$((DEPS_PASSED + 1))  # Count as passed for now, will validate in Phase 5
fi

# Summarize and fail if dependencies not met
if ! summarize_deps "Phase 4: Regulus Setup"; then
    exit 1
fi

echo ""
echo "Controller host: ${CRUCIBLE_CONTROLLER_HOST}"
echo "Installation user: ${CRUCIBLE_CONTROLLER_USER}"
echo "Installation path: ${REGULUS_PATH}"
echo ""

# If CHECK_ONLY mode, exit after dependency checks
if [ "${CHECK_ONLY}" = "true" ]; then
    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}✅ Dependency Checks Complete${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    echo "All dependency checks passed!"
    echo "Log file: ${LOG_FILE}"
    echo ""
    echo "To proceed with installation:"
    echo "  cd modules/regulus && make install"
    echo ""
    log "========================================="
    log "CHECK_ONLY mode: Dependency checks completed successfully"
    log "Exiting without installation"
    log "Log file: ${LOG_FILE}"
    log "========================================="
    exit 0
fi

# Check if Regulus already installed (check state.env for existing installation)
if [ -n "$REGULUS_PATH_FROM_STATE" ] && [ "$REGULUS_PATH_FROM_STATE" != "$REGULUS_PATH" ]; then
    echo ""
    echo "Checking for existing Regulus installation..."
    log "Checking for existing Regulus installation..."
    log "  Existing path from state: ${REGULUS_PATH_FROM_STATE}"

    # Check if the path from state still exists
    if ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} "[ -d ${REGULUS_PATH_FROM_STATE} ]" 2>/dev/null; then
        echo -e "${GREEN}✓ Existing Regulus found at: ${REGULUS_PATH_FROM_STATE}${NC}"
        log "✓ Existing Regulus installation found at: ${REGULUS_PATH_FROM_STATE}"

        # Manual mode - default to using existing (preserving test data)
        if [ -z "$AUTO_MODE" ]; then
            echo ""
            echo "Using existing Regulus installation (preserving test data)"
            echo ""
            log "Using existing Regulus installation (preserving test data)"

            # Update state to confirm existing installation
            if ! grep -q "REGULUS_PATH=" "${REG_AGENT_ROOT}/vars/state.env" 2>/dev/null; then
                echo "REGULUS_PATH=${REGULUS_PATH_FROM_STATE}" >> "${REG_AGENT_ROOT}/vars/state.env"
            fi

            # Update 'latest' symlink to point to existing installation
            echo "Updating 'latest' symlink..."
            log "Updating 'latest' symlink to ${REGULUS_PATH_FROM_STATE}..."

            # Determine the parent directory
            REGULUS_PARENT_DIR=$(dirname "${REGULUS_PATH_FROM_STATE}")

            ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} bash <<SYMLINK_UPDATE
# Remove old symlink if it exists
if [ -L ${REGULUS_PARENT_DIR}/latest ]; then
    rm ${REGULUS_PARENT_DIR}/latest
fi

# Create new symlink
ln -s ${REGULUS_PATH_FROM_STATE} ${REGULUS_PARENT_DIR}/latest
echo "✓ Symlink updated: ${REGULUS_PARENT_DIR}/latest -> ${REGULUS_PATH_FROM_STATE}"
SYMLINK_UPDATE

            log "✓ Symlink updated: ${REGULUS_PARENT_DIR}/latest -> ${REGULUS_PATH_FROM_STATE}"

            # Update jobs.config if user specified REGULUS_JOBS
            echo ""
            if [ -n "${REGULUS_JOBS}" ]; then
                echo "Updating jobs.config with user-specified JOBS..."
                log "Updating jobs.config in existing installation:"
                log "  JOBS: ${REGULUS_JOBS}"

                # Use existing installation path
                REGULUS_PATH="${REGULUS_PATH_FROM_STATE}"

                # Check if jobs.config exists
                JOBS_CONFIG_EXISTS=$(ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} "[ -f ${REGULUS_PATH}/jobs.config ] && echo 'yes' || echo 'no'")

                if [ "$JOBS_CONFIG_EXISTS" = "yes" ]; then
                    # Update existing jobs.config - copy locally, edit, copy back
                    log "  Updating existing jobs.config"

                    # Backup on remote
                    ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} "cp ${REGULUS_PATH}/jobs.config ${REGULUS_PATH}/jobs.config.bak"

                    # Copy to local temp
                    scp ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST}:${REGULUS_PATH}/jobs.config /tmp/jobs.config.tmp

                    # Edit locally - delete multi-line JOBS and replace with single line
                    sed -i '/^export JOBS=/,/^[^[:space:]]/{/^export JOBS=/!{/^[^[:space:]]/!d}}' /tmp/jobs.config.tmp
                    sed -i "s|^export JOBS=.*|export JOBS=${REGULUS_JOBS}|" /tmp/jobs.config.tmp

                    # Copy back to remote
                    scp /tmp/jobs.config.tmp ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST}:${REGULUS_PATH}/jobs.config
                    rm /tmp/jobs.config.tmp

                    echo "✓ jobs.config updated with specified JOBS"
                    log "✓ jobs.config JOBS line updated"
                else
                    # Create new jobs.config
                    log "  Creating new jobs.config"
                    cat > /tmp/jobs.config <<EOF
# reg-agent generated jobs.config
# Generated: $(date)

export OCP_PROJECT=crucible-regulus
export NODE_IP=
export IPSEC_EP=
export REMOTE_HOST_INTF=

# Test suite - user specified (GNU make syntax - no quotes)
export JOBS=${REGULUS_JOBS}

# Test parameters
export DRY_RUN=false
export TAG=${REGULUS_TAG:-REG-AGENT}
export NUM_SAMPLES=${NUM_SAMPLES:-3}
export DURATION=60
EOF
                    scp /tmp/jobs.config ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST}:${REGULUS_PATH}/jobs.config
                    rm /tmp/jobs.config
                    echo "✓ jobs.config created with specified JOBS"
                    log "✓ jobs.config created with JOBS=${REGULUS_JOBS}"
                fi
            else
                echo "No JOBS specified - leaving jobs.config unchanged"
                log "No REGULUS_JOBS specified - leaving jobs.config unchanged"
            fi

            echo ""
            echo -e "${GREEN}=========================================${NC}"
            echo -e "${GREEN}✅ Phase 4: Regulus Ready (Existing)${NC}"
            echo -e "${GREEN}=========================================${NC}"
            echo "Regulus path: ${REGULUS_PATH_FROM_STATE}"
            echo "Latest symlink: ${REGULUS_PARENT_DIR}/latest"
            if [ -n "${REGULUS_JOBS}" ]; then
                echo "Jobs configured: ${REGULUS_JOBS}"
            fi
            echo ""

            log "========================================"
            log "✅ Phase 4: Regulus Ready (Existing)"
            log "========================================"
            log "Regulus path: ${REGULUS_PATH_FROM_STATE}"
            log "Latest symlink: ${REGULUS_PARENT_DIR}/latest"
            if [ -n "${REGULUS_JOBS}" ]; then
                log "Jobs configured: ${REGULUS_JOBS}"
            fi
            log "Log file saved at: ${LOG_FILE}"
            log "========================================"
            exit 0
        fi
    else
        echo -e "${YELLOW}⚠ Previous Regulus installation not found at: ${REGULUS_PATH_FROM_STATE}${NC}"
        echo "  (Directory may have been manually removed)"
        echo "  Will create new installation..."
    fi
fi

echo ""
echo "Creating new Regulus installation (previous installations preserved)..."
log "Creating new Regulus installation..."

# Clone Regulus on controller host
echo "Cloning Regulus to ${REGULUS_PATH}..."
log "Cloning Regulus to ${REGULUS_PATH} on ${CRUCIBLE_CONTROLLER_HOST}..."

# Regulus Git repository
REGULUS_GIT_REPO="https://github.com/redhat-performance/regulus.git"
REGULUS_GIT_BRANCH="main"
log "Repository: ${REGULUS_GIT_REPO} (branch: ${REGULUS_GIT_BRANCH})"

ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} bash <<REGULUS_CLONE
set -e

# Create parent directory if using subdirectory
if [ -n "${REGULUS_INSTALL_SUBDIR}" ]; then
    mkdir -p /root/${REGULUS_INSTALL_SUBDIR}
fi

# Clone Regulus
echo "Cloning Regulus from ${REGULUS_GIT_REPO}..."
git clone -b ${REGULUS_GIT_BRANCH} ${REGULUS_GIT_REPO} ${REGULUS_PATH}

echo "✓ Regulus cloned"
REGULUS_CLONE
log "✓ Regulus cloned successfully"

# Generate lab.config
echo ""
echo "Generating lab.config..."
log "Generating lab.config..."

# Get bastion SSH user (default to root for most lab setups)
# kni: Multi-node OpenShift via Jetlag/IPI
# core: CoreOS-based systems
# root: Direct root access (most common in lab)
REG_KNI_USER=${REG_KNI_USER:-root}
log "  REG_KNI_USER: ${REG_KNI_USER}"
log "  REG_OCPHOST: ${CRUCIBLE_CONTROLLER_HOST}"
log "  KUBECONFIG: ${KUBECONFIG_PATH}"

# Create lab.config content
cat > /tmp/lab.config <<EOF
# reg-agent generated lab.config
# Generated: $(date)

export REG_KNI_USER=${REG_KNI_USER}
export REG_OCPHOST="${CRUCIBLE_CONTROLLER_HOST}"
export KUBECONFIG=${KUBECONFIG_PATH}

# Worker nodes (will be auto-detected by reg-smart-config)
export OCP_WORKER_0=
export OCP_WORKER_1=
export OCP_WORKER_2=

# NIC configuration (will be auto-detected by reg-smart-config)
export REG_SRIOV_NIC=
export REG_SRIOV_NIC_MODEL=
export REG_SRIOV_MTU=9000
export REG_MACVLAN_NIC=
export REG_DPDK_NIC=

# Bare metal hosts (optional)
export BMLHOSTA=
export BMLHOSTB=
export BM_HOSTS=
export TREX_HOSTS=

# Deployment identifier
export REG_DP=${REG_DP:-reg-agent}
EOF

# Copy lab.config to bastion
scp /tmp/lab.config ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST}:${REGULUS_PATH}/lab.config
rm /tmp/lab.config
echo "✓ lab.config generated and copied"
log "✓ lab.config generated and copied to ${REGULUS_PATH}/lab.config"

# Configure jobs.config if user specified JOBS
echo ""
if [ -n "${REGULUS_JOBS}" ]; then
    echo "Configuring jobs.config with user-specified JOBS..."
    log "Configuring jobs.config with user-specified JOBS:"
    log "  JOBS: ${REGULUS_JOBS}"

    # Check if jobs.config exists in Regulus repo
    JOBS_CONFIG_EXISTS=$(ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} "[ -f ${REGULUS_PATH}/jobs.config ] && echo 'yes' || echo 'no'")

    if [ "$JOBS_CONFIG_EXISTS" = "yes" ]; then
        # Update existing jobs.config - copy locally, edit, copy back
        log "  Updating existing jobs.config"

        # Backup on remote
        ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} "cp ${REGULUS_PATH}/jobs.config ${REGULUS_PATH}/jobs.config.bak"

        # Copy to local temp
        scp ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST}:${REGULUS_PATH}/jobs.config /tmp/jobs.config.tmp

        # Edit locally - delete multi-line JOBS and replace with single line
        sed -i '/^export JOBS=/,/^[^[:space:]]/{/^export JOBS=/!{/^[^[:space:]]/!d}}' /tmp/jobs.config.tmp
        sed -i "s|^export JOBS=.*|export JOBS=${REGULUS_JOBS}|" /tmp/jobs.config.tmp

        # Copy back to remote
        scp /tmp/jobs.config.tmp ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST}:${REGULUS_PATH}/jobs.config
        rm /tmp/jobs.config.tmp

        echo "✓ jobs.config updated with specified JOBS"
        log "✓ jobs.config JOBS line updated"
    else
        # Create new jobs.config with user-specified JOBS
        log "  Creating new jobs.config"
        cat > /tmp/jobs.config <<EOF
# reg-agent generated jobs.config
# Generated: $(date)

export OCP_PROJECT=crucible-regulus
export NODE_IP=
export IPSEC_EP=
export REMOTE_HOST_INTF=

# Test suite - user specified (GNU make syntax - no quotes)
export JOBS=${REGULUS_JOBS}

# Test parameters
export DRY_RUN=false
export TAG=${REGULUS_TAG:-REG-AGENT}
export NUM_SAMPLES=${NUM_SAMPLES:-3}
export DURATION=60
EOF
        scp /tmp/jobs.config ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST}:${REGULUS_PATH}/jobs.config
        rm /tmp/jobs.config
        echo "✓ jobs.config created with specified JOBS"
        log "✓ jobs.config created with JOBS=${REGULUS_JOBS}"
    fi
else
    echo "No JOBS specified - using Regulus default jobs.config"
    log "No REGULUS_JOBS specified - leaving jobs.config untouched"
    log "  jobs.config will use Regulus repository defaults"
fi

# Copy kubeconfig to bastion if needed
echo ""
echo "Setting up kubeconfig access..."
log "Verifying kubeconfig access..."
ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} bash <<KUBECONFIG_SETUP
if [ ! -f ${KUBECONFIG_PATH} ]; then
    echo "⚠️  Kubeconfig not found at ${KUBECONFIG_PATH}"
    echo "   This will be created by Jetlag deployment"
else
    echo "✓ Kubeconfig found at ${KUBECONFIG_PATH}"
fi
KUBECONFIG_SETUP

# Bootstrap Regulus environment
echo ""
echo "Bootstrapping Regulus..."
log "Bootstrapping Regulus environment..."
log "Running bootstrap commands on ${CRUCIBLE_CONTROLLER_HOST}:${REGULUS_PATH}"

ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} bash <<REGULUS_BOOTSTRAP
set -e
cd ${REGULUS_PATH}

# Pass cluster detection results from pre-check
NEEDS_LABEL_FIX="${NEEDS_LABEL_FIX}"
DETECTED_CLUSTER_TYPE="${DETECTED_CLUSTER_TYPE}"

# Source bootstrap
if [ -f bootstrap.sh ]; then
    source bootstrap.sh
    echo "✓ Regulus environment bootstrapped"
else
    echo "⚠️  bootstrap.sh not found"
fi

# Fix worker_labels.config for SNO/Compact clusters (will be used by reg-smart-config in Phase 5)
if [ -f templates/common/worker_labels.config ]; then
    if [ "\${NEEDS_LABEL_FIX}" = "yes" ]; then
        echo "Adjusting worker_labels.config for \${DETECTED_CLUSTER_TYPE}..."
        cat > templates/common/worker_labels.config <<'WORKER_LABELS_FIX'
# Define the labels for selecting the workers. Support one MATCH and one MATCH_NOT label.
# Auto-configured by reg-agent for SNO/Compact cluster
MATCH=worker
# MATCH_NOT filters disabled for SNO/Compact clusters where control-plane nodes also run workloads
#MATCH_NOT_1=control-plane
#MATCH_NOT_2=master
WORKER_LABELS_FIX
        echo "✓ worker_labels.config adjusted for \${DETECTED_CLUSTER_TYPE}"
    fi
fi

echo "✓ Regulus bootstrap complete"
echo ""
echo "Note: reg-smart-config and init-lab will run in Phase 5 before test execution"
REGULUS_BOOTSTRAP

log "✓ Regulus bootstrap completed"
log "  - bootstrap.sh: sourced"
log "  - worker_labels.config: fixed for ${DETECTED_CLUSTER_TYPE}"
log "  - reg-smart-config and init-lab: deferred to Phase 5"

# Create 'latest' symlink pointing to this installation
echo ""
echo "Creating 'latest' symlink..."
log "Creating 'latest' symlink to ${REGULUS_PATH}..."

# Determine the parent directory based on REGULUS_INSTALL_SUBDIR
if [ -n "$REGULUS_INSTALL_SUBDIR" ]; then
    REGULUS_PARENT_DIR="/root/${REGULUS_INSTALL_SUBDIR}"
else
    REGULUS_PARENT_DIR="/root"
fi

ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} bash <<SYMLINK_CREATE
# Remove old symlink if it exists
if [ -L ${REGULUS_PARENT_DIR}/latest ]; then
    rm ${REGULUS_PARENT_DIR}/latest
fi

# Create new symlink
ln -s ${REGULUS_PATH} ${REGULUS_PARENT_DIR}/latest
echo "✓ Symlink created: ${REGULUS_PARENT_DIR}/latest -> ${REGULUS_PATH}"
SYMLINK_CREATE

log "✓ Symlink created: ${REGULUS_PARENT_DIR}/latest -> ${REGULUS_PATH}"

# Save Regulus path to state (update or append)
log "Saving state to ${REG_AGENT_ROOT}/vars/state.env..."
if grep -q "^REGULUS_PATH=" "${REG_AGENT_ROOT}/vars/state.env" 2>/dev/null; then
    # Update existing entry
    sed -i "s|^REGULUS_PATH=.*|REGULUS_PATH=${REGULUS_PATH}|" "${REG_AGENT_ROOT}/vars/state.env"
    log "  Updated REGULUS_PATH in state.env"
else
    # Append new entry
    echo "REGULUS_PATH=${REGULUS_PATH}" >> "${REG_AGENT_ROOT}/vars/state.env"
    log "  Added REGULUS_PATH to state.env"
fi

# Mark setup as completed with timestamp
SETUP_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
if grep -q "^REGULUS_SETUP_COMPLETED=" "${REG_AGENT_ROOT}/vars/state.env" 2>/dev/null; then
    sed -i "s|^REGULUS_SETUP_COMPLETED=.*|REGULUS_SETUP_COMPLETED=true|" "${REG_AGENT_ROOT}/vars/state.env"
    sed -i "s|^REGULUS_SETUP_TIMESTAMP=.*|REGULUS_SETUP_TIMESTAMP=${SETUP_TIMESTAMP}|" "${REG_AGENT_ROOT}/vars/state.env"
else
    echo "REGULUS_SETUP_COMPLETED=true" >> "${REG_AGENT_ROOT}/vars/state.env"
    echo "REGULUS_SETUP_TIMESTAMP=${SETUP_TIMESTAMP}" >> "${REG_AGENT_ROOT}/vars/state.env"
fi
log "  Marked setup as completed"

echo ""
echo "========================================="
echo "✅ Phase 4: Regulus Setup Complete"
echo "========================================="
echo "Regulus installed at: ${REGULUS_PATH} on ${CRUCIBLE_CONTROLLER_HOST}"
echo "Latest symlink: ${REGULUS_PARENT_DIR}/latest"
echo "Lab config: ${REGULUS_PATH}/lab.config (initial template)"
if [ -n "${REGULUS_JOBS}" ]; then
    echo "Jobs config: ${REGULUS_PATH}/jobs.config (JOBS configured)"
else
    echo "Jobs config: Using Regulus defaults (no JOBS specified)"
fi
echo ""
echo "Phase 4 completed:"
echo "  ✓ Regulus cloned to bastion"
echo "  ✓ lab.config generated (template)"
echo "  ✓ Regulus environment bootstrapped"
echo "  ✓ worker_labels.config fixed for ${DETECTED_CLUSTER_TYPE}"
if [ -n "${REGULUS_JOBS}" ]; then
    echo "  ✓ jobs.config JOBS updated with user specification"
else
    echo "  → jobs.config using Regulus defaults (no JOBS specified)"
fi
echo ""
echo "Next: Phase 5 will run reg-smart-config and init-lab before tests"
echo ""
echo "Verify:"
echo "  ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST}"
echo "  cd ${REGULUS_PARENT_DIR}/latest"
echo "  cat lab.config"
echo "  cat jobs.config"
echo ""

log "========================================"
log "✅ Phase 4: Regulus Setup Complete"
log "========================================"
log "Regulus installed at: ${REGULUS_PATH} on ${CRUCIBLE_CONTROLLER_HOST}"
log "Latest symlink: ${REGULUS_PARENT_DIR}/latest"
log "Lab config: ${REGULUS_PATH}/lab.config (initial template)"
if [ -n "${REGULUS_JOBS}" ]; then
    log "Jobs config: ${REGULUS_PATH}/jobs.config (JOBS configured)"
    log "  JOBS=${REGULUS_JOBS}"
else
    log "Jobs config: Using Regulus defaults (no JOBS specified)"
fi
log ""
log "Phase 4 scope:"
log "  ✓ Regulus cloned to bastion"
log "  ✓ lab.config generated (template)"
log "  ✓ Regulus environment bootstrapped"
log "  ✓ worker_labels.config fixed for ${DETECTED_CLUSTER_TYPE}"
if [ -n "${REGULUS_JOBS}" ]; then
    log "  ✓ jobs.config JOBS updated: ${REGULUS_JOBS}"
else
    log "  → jobs.config using Regulus defaults (no JOBS specified)"
fi
log "  → reg-smart-config and init-lab deferred to Phase 5"
log ""
log "Log file saved at: ${LOG_FILE}"
log "========================================"

exit 0
