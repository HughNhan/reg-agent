#!/bin/bash
# Phase 4: Workspace Validation (for regulus-only mode)
# Validates that Regulus workspace is ready to run tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG_AGENT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source configuration
# Load JSON configuration
source "${REG_AGENT_ROOT}/modules/lib/json-config.sh"
json_export_env ".regulus" "REGULUS"

echo "============================================="
echo "Phase 4: Workspace Validation"
echo "============================================="
echo ""
echo "Bastion: $BASTION_HOST"
echo "Regulus Path: $REGULUS_PATH"
echo "Kubeconfig: $KUBECONFIG_PATH"
echo ""

# Check if variables are set
if [ -z "$BASTION_HOST" ]; then
    echo "Error: BASTION_HOST not set in config"
    exit 1
fi

if [ -z "$REGULUS_PATH" ]; then
    echo "Error: REGULUS_PATH not set in config"
    exit 1
fi

if [ -z "$KUBECONFIG_PATH" ]; then
    echo "Error: KUBECONFIG_PATH not set in config"
    exit 1
fi

# Check 1: SSH access
echo "Check 1: SSH Access"
echo "--------------------------------------"
if ssh -o ConnectTimeout=10 -o BatchMode=yes root@$BASTION_HOST "echo ok" &>/dev/null; then
    echo "✓ SSH access confirmed"
else
    echo "✗ Cannot SSH to bastion at $BASTION_HOST"
    echo ""
    echo "Fix: ssh-copy-id root@$BASTION_HOST"
    exit 1
fi
echo ""

# Check 2: Regulus directory exists
echo "Check 2: Regulus Installation"
echo "--------------------------------------"
if ssh root@$BASTION_HOST "[ -d $REGULUS_PATH ]"; then
    echo "✓ Regulus directory found at $REGULUS_PATH"
else
    echo "✗ Regulus directory not found at $REGULUS_PATH"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Find Regulus on bastion:"
    echo "     ssh root@$BASTION_HOST 'find /root -name \"cpt-regulus\" -type d'"
    echo "  2. Update REGULUS_PATH in vars/config.json"
    echo "  3. Or switch to existing-cluster mode to install Regulus"
    exit 1
fi
echo ""

# Check 3: Regulus is configured
echo "Check 3: Regulus Configuration"
echo "--------------------------------------"
MISSING_FILES=()

if ! ssh root@$BASTION_HOST "[ -f ${REGULUS_PATH}/bootstrap.sh ]"; then
    MISSING_FILES+=("bootstrap.sh")
fi

if ! ssh root@$BASTION_HOST "[ -f ${REGULUS_PATH}/run_cpt.sh ]"; then
    MISSING_FILES+=("run_cpt.sh")
fi

if ! ssh root@$BASTION_HOST "[ -f ${REGULUS_PATH}/lab.config ]"; then
    MISSING_FILES+=("lab.config")
fi

if ! ssh root@$BASTION_HOST "[ -f ${REGULUS_PATH}/jobs.config ]"; then
    MISSING_FILES+=("jobs.config")
fi

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    echo "⚠ Missing configuration files:"
    for file in "${MISSING_FILES[@]}"; do
        echo "  - $file"
    done
    echo ""

    if [[ " ${MISSING_FILES[@]} " =~ " lab.config " ]] || [[ " ${MISSING_FILES[@]} " =~ " jobs.config " ]]; then
        echo "Warning: Missing config files - will regenerate"
        echo "Consider switching to existing-cluster mode for full setup"
    fi

    if [[ " ${MISSING_FILES[@]} " =~ " bootstrap.sh " ]] || [[ " ${MISSING_FILES[@]} " =~ " run_cpt.sh " ]]; then
        echo "✗ Critical Regulus files missing"
        echo ""
        echo "Fix: Use existing-cluster mode to setup Regulus properly:"
        echo "  DEPLOY_MODE=existing-cluster make deploy"
        exit 1
    fi
else
    echo "✓ Regulus configuration files found"

    # Show current configs
    echo ""
    echo "Current lab.config:"
    ssh root@$BASTION_HOST "grep -v '^#' ${REGULUS_PATH}/lab.config | grep -v '^$' | head -5" || echo "  (empty or commented)"

    echo ""
    echo "Current jobs.config:"
    ssh root@$BASTION_HOST "grep -v '^#' ${REGULUS_PATH}/jobs.config | grep -v '^$' | head -5" || echo "  (empty or commented)"
fi
echo ""

# Check 4: Kubeconfig exists and works
echo "Check 4: Cluster Access"
echo "--------------------------------------"
if ssh root@$BASTION_HOST "[ -f $KUBECONFIG_PATH ]"; then
    echo "✓ Kubeconfig found at $KUBECONFIG_PATH"
else
    echo "✗ Kubeconfig not found at $KUBECONFIG_PATH"
    exit 1
fi

# Test cluster access
if ssh root@$BASTION_HOST "export KUBECONFIG=$KUBECONFIG_PATH && oc cluster-info &>/dev/null"; then
    echo "✓ Cluster API is reachable"

    # Get node count
    NODE_COUNT=$(ssh root@$BASTION_HOST "export KUBECONFIG=$KUBECONFIG_PATH && oc get nodes --no-headers 2>/dev/null | wc -l" || echo "0")
    echo "  Nodes: $NODE_COUNT"
else
    echo "✗ Cannot reach cluster API"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check cluster status:"
    echo "     ssh root@$BASTION_HOST 'export KUBECONFIG=$KUBECONFIG_PATH && oc get nodes'"
    echo "  2. Verify kubeconfig path is correct"
    exit 1
fi
echo ""

# Check 5: Crucible is installed
echo "Check 5: Crucible Installation"
echo "--------------------------------------"
if ssh root@$BASTION_HOST "[ -d /root/crucible ]"; then
    echo "✓ Crucible found at /root/crucible"

    # Check if oc wrapper exists
    if ssh root@$BASTION_HOST "[ -f /root/crucible/bin/oc ]"; then
        echo "  ✓ oc wrapper found"
    fi
else
    echo "⚠ Crucible not found at /root/crucible"
    echo ""
    echo "Warning: Regulus tests may fail without Crucible"
    echo "Consider using existing-cluster mode to install Crucible"
fi
echo ""

# Check 6: Regulus bootstrap works
echo "Check 6: Regulus Bootstrap"
echo "--------------------------------------"
BOOTSTRAP_TEST=$(ssh root@$BASTION_HOST "cd $REGULUS_PATH && source bootstrap.sh &>/dev/null && echo 'ok'" || echo "fail")

if [ "$BOOTSTRAP_TEST" = "ok" ]; then
    echo "✓ Regulus bootstrap.sh works"
else
    echo "⚠ Regulus bootstrap.sh has issues"
    echo ""
    echo "Warning: May need to run make init-lab"
fi
echo ""

# Save workspace info to state
mkdir -p "${REG_AGENT_ROOT}/vars"
cat >> "${REG_AGENT_ROOT}/vars/state.env" <<EOF
BASTION_HOST=${BASTION_HOST}
REGULUS_PATH=${REGULUS_PATH}
KUBECONFIG_PATH=${KUBECONFIG_PATH}
WORKSPACE_VALIDATED=true
VALIDATION_TIMESTAMP=$(date -Iseconds)
EOF

echo "========================================="
echo "✅ Phase 4: Workspace Validation Complete"
echo "========================================="
echo "Bastion: $BASTION_HOST"
echo "Regulus: $REGULUS_PATH"
echo "Cluster: $NODE_COUNT nodes"
echo ""
echo "Workspace is ready for test execution"
echo ""
echo "Next: Run tests with 'make run'"
echo ""

exit 0
