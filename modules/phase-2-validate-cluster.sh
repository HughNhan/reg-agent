#!/bin/bash
# Phase 2: Cluster Validation (for existing-cluster mode)
# Validates that cluster is accessible and healthy

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG_AGENT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source configuration
# Load JSON configuration
source "${REG_AGENT_ROOT}/modules/lib/json-config.sh"
json_export_env ".jetlag" ""

echo "============================================="
echo "Phase 2: Cluster Validation"
echo "============================================="
echo ""
echo "Bastion: $BASTION_HOST"
echo "Kubeconfig: $KUBECONFIG_PATH"
echo "Cluster Type: $CLUSTER_TYPE"
echo ""

# Check if variables are set
if [ -z "$BASTION_HOST" ]; then
    echo "Error: BASTION_HOST not set in config"
    exit 1
fi

if [ -z "$KUBECONFIG_PATH" ]; then
    echo "Error: KUBECONFIG_PATH not set in config"
    exit 1
fi

# Check 1: SSH access to bastion
echo "Check 1: SSH Access"
echo "--------------------------------------"
if ssh -o ConnectTimeout=10 -o BatchMode=yes root@$BASTION_HOST "echo ok" &>/dev/null; then
    echo "✓ SSH access confirmed"
else
    echo "✗ Cannot SSH to bastion at $BASTION_HOST"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Verify bastion hostname/IP: $BASTION_HOST"
    echo "  2. Check SSH key access: ssh root@$BASTION_HOST"
    echo "  3. Copy SSH key if needed: ssh-copy-id root@$BASTION_HOST"
    exit 1
fi
echo ""

# Check 2: Kubeconfig exists
echo "Check 2: Kubeconfig"
echo "--------------------------------------"
if ssh root@$BASTION_HOST "[ -f $KUBECONFIG_PATH ]"; then
    echo "✓ Kubeconfig found at $KUBECONFIG_PATH"
else
    echo "✗ Kubeconfig not found at $KUBECONFIG_PATH"
    echo ""
    echo "Troubleshooting:"
    echo "  1. List kubeconfigs on bastion:"
    echo "     ssh root@$BASTION_HOST 'find /root -name kubeconfig -type f'"
    echo "  2. Update KUBECONFIG_PATH in vars/config.json"
    echo "  3. For MNO: usually /root/mno/kubeconfig"
    echo "  4. For SNO: usually /root/sno/<hostname>/kubeconfig"
    exit 1
fi
echo ""

# Check 3: Cluster API reachable
echo "Check 3: Cluster API"
echo "--------------------------------------"
if ssh root@$BASTION_HOST "export KUBECONFIG=$KUBECONFIG_PATH && oc cluster-info &>/dev/null"; then
    echo "✓ Cluster API is reachable"

    # Get cluster info
    CLUSTER_INFO=$(ssh root@$BASTION_HOST "export KUBECONFIG=$KUBECONFIG_PATH && oc cluster-info" 2>/dev/null | head -1 || echo "N/A")
    echo "  Cluster: $CLUSTER_INFO"
else
    echo "✗ Cannot reach cluster API"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Verify cluster is running:"
    echo "     ssh root@$BASTION_HOST 'export KUBECONFIG=$KUBECONFIG_PATH && oc get nodes'"
    echo "  2. Check cluster status on bastion"
    echo "  3. Verify kubeconfig is valid and not expired"
    exit 1
fi
echo ""

# Check 4: Nodes are ready
echo "Check 4: Node Status"
echo "--------------------------------------"
NODE_STATUS=$(ssh root@$BASTION_HOST "export KUBECONFIG=$KUBECONFIG_PATH && oc get nodes --no-headers 2>/dev/null" || echo "")

if [ -z "$NODE_STATUS" ]; then
    echo "✗ Cannot get node status"
    exit 1
fi

TOTAL_NODES=$(echo "$NODE_STATUS" | wc -l)
READY_NODES=$(echo "$NODE_STATUS" | grep -c " Ready " || echo "0")
NOT_READY=$(echo "$NODE_STATUS" | grep -v " Ready " || echo "")

echo "Total nodes: $TOTAL_NODES"
echo "Ready nodes: $READY_NODES"

if [ "$TOTAL_NODES" -eq "$READY_NODES" ]; then
    echo "✓ All nodes are Ready"
    echo ""
    echo "Node list:"
    echo "$NODE_STATUS" | awk '{print "  - " $1 " (" $2 ")"}'
else
    echo "⚠ Some nodes are not Ready:"
    echo "$NOT_READY"
    echo ""
    echo "Warning: Proceeding anyway, but tests may fail"
    echo "Consider fixing node issues before running tests"
fi
echo ""

# Check 5: Basic cluster components
echo "Check 5: Cluster Components"
echo "--------------------------------------"

# Check operators
OPERATOR_STATUS=$(ssh root@$BASTION_HOST "export KUBECONFIG=$KUBECONFIG_PATH && oc get co --no-headers 2>/dev/null | grep -v 'True.*False.*False' || echo ''" | wc -l)

if [ "$OPERATOR_STATUS" -gt 0 ]; then
    echo "⚠ Some cluster operators are not healthy"
    ssh root@$BASTION_HOST "export KUBECONFIG=$KUBECONFIG_PATH && oc get co | grep -v 'True.*False.*False' || true"
    echo ""
    echo "Warning: Cluster may not be fully ready"
else
    echo "✓ Cluster operators are healthy"
fi
echo ""

# Check 6: OCP version
echo "Check 6: OpenShift Version"
echo "--------------------------------------"
OCP_VER=$(ssh root@$BASTION_HOST "export KUBECONFIG=$KUBECONFIG_PATH && oc version -o json 2>/dev/null | grep 'gitVersion' | head -1 | cut -d'\"' -f4" || echo "Unknown")
echo "OpenShift version: $OCP_VER"
echo ""

# Save cluster info to state
mkdir -p "${REG_AGENT_ROOT}/vars"
cat >> "${REG_AGENT_ROOT}/vars/state.env" <<EOF
BASTION_HOST=${BASTION_HOST}
KUBECONFIG_PATH=${KUBECONFIG_PATH}
CLUSTER_TYPE=${CLUSTER_TYPE}
OCP_VERSION=${OCP_VER}
TOTAL_NODES=${TOTAL_NODES}
READY_NODES=${READY_NODES}
VALIDATION_TIMESTAMP=$(date -Iseconds)
EOF

echo "========================================="
echo "✅ Phase 2: Cluster Validation Complete"
echo "========================================="
echo "Bastion: $BASTION_HOST"
echo "Nodes: $READY_NODES/$TOTAL_NODES Ready"
echo "Version: $OCP_VER"
echo ""
echo "Cluster is accessible and ready for Regulus testing"
echo ""

exit 0
