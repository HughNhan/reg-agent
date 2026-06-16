#!/bin/bash
# Validate cluster is accessible and ready
# Works for both deployed and imported clusters

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Cluster Validation${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

#------------------------------------------------------------------------------
# Load State
#------------------------------------------------------------------------------

# Try module state first, then global state
if [ -f "${SCRIPT_DIR}/generated/state/current.env" ]; then
    source "${SCRIPT_DIR}/generated/state/current.env"
elif [ -f "${ROOT_DIR}/vars/state.env" ]; then
    source "${ROOT_DIR}/vars/state.env"
else
    echo -e "${RED}ERROR: No state file found${NC}"
    echo ""
    echo "Run one of:"
    echo "  make -C modules/jetlag deploy  # Deploy new cluster"
    echo "  make -C modules/jetlag import  # Import existing cluster"
    exit 1
fi

# Check variables
if [ -z "$BASTION_HOST" ]; then
    echo -e "${RED}ERROR: BASTION_HOST not set in state${NC}"
    exit 1
fi

if [ -z "$KUBECONFIG_PATH" ]; then
    echo -e "${RED}ERROR: KUBECONFIG_PATH not set in state${NC}"
    exit 1
fi

echo "Validating cluster:"
echo "  Bastion:    ${BASTION_HOST}"
echo "  Kubeconfig: ${KUBECONFIG_PATH}"
echo "  Type:       ${CLUSTER_TYPE:-unknown}"
echo ""

#------------------------------------------------------------------------------
# Check 1: SSH Access to Bastion
#------------------------------------------------------------------------------

echo -e "${BLUE}Check 1: SSH Access${NC}"
echo "-------------------------------------"

if ssh -o ConnectTimeout=10 -o BatchMode=yes root@${BASTION_HOST} "echo ok" &>/dev/null; then
    echo -e "${GREEN}✓ SSH access confirmed${NC}"
else
    echo -e "${RED}✗ Cannot SSH to bastion at ${BASTION_HOST}${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Verify bastion hostname/IP:"
    echo "     ping ${BASTION_HOST}"
    echo ""
    echo "  2. Check SSH key access:"
    echo "     ssh root@${BASTION_HOST}"
    echo ""
    echo "  3. Copy SSH key if needed:"
    echo "     ssh-copy-id root@${BASTION_HOST}"
    echo ""
    echo "  4. Check firewall/network:"
    echo "     telnet ${BASTION_HOST} 22"
    exit 1
fi
echo ""

#------------------------------------------------------------------------------
# Check 2: Kubeconfig Exists on Bastion
#------------------------------------------------------------------------------

echo -e "${BLUE}Check 2: Kubeconfig File${NC}"
echo "-------------------------------------"

if ssh root@${BASTION_HOST} "test -f ${KUBECONFIG_PATH}" 2>/dev/null; then
    echo -e "${GREEN}✓ Kubeconfig exists at ${KUBECONFIG_PATH}${NC}"

    # Get file info
    FILE_INFO=$(ssh root@${BASTION_HOST} "ls -lh ${KUBECONFIG_PATH}" 2>/dev/null)
    echo "  ${FILE_INFO}"
else
    echo -e "${RED}✗ Kubeconfig not found at ${KUBECONFIG_PATH}${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check if kubeconfig exists elsewhere on bastion:"
    echo "     ssh root@${BASTION_HOST} 'find /root -name kubeconfig'"
    echo ""
    echo "  2. For MNO clusters, typical path: /root/mno/kubeconfig"
    echo "  3. For SNO clusters, typical path: /root/sno/kubeconfig"
    echo ""
    echo "  4. If path is different, update KUBECONFIG_PATH and re-run"
    exit 1
fi
echo ""

#------------------------------------------------------------------------------
# Check 3: oc Command Available
#------------------------------------------------------------------------------

echo -e "${BLUE}Check 3: OpenShift Client (oc)${NC}"
echo "-------------------------------------"

if ssh root@${BASTION_HOST} "which oc" &>/dev/null; then
    OC_VERSION=$(ssh root@${BASTION_HOST} "oc version --client 2>/dev/null | head -1" || echo "unknown")
    echo -e "${GREEN}✓ oc command available${NC}"
    echo "  Version: ${OC_VERSION}"
else
    echo -e "${YELLOW}⚠ oc command not found on bastion${NC}"
    echo "  This is not critical, but recommended for cluster management"
    echo ""
    echo "  To install:"
    echo "    ssh root@${BASTION_HOST}"
    echo "    curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz"
    echo "    tar xvf openshift-client-linux.tar.gz"
    echo "    mv oc kubectl /usr/local/bin/"
fi
echo ""

#------------------------------------------------------------------------------
# Check 4: Cluster API Access
#------------------------------------------------------------------------------

echo -e "${BLUE}Check 4: Cluster API Access${NC}"
echo "-------------------------------------"

if ssh root@${BASTION_HOST} "oc --kubeconfig=${KUBECONFIG_PATH} cluster-info 2>&1 | head -3" 2>/dev/null; then
    echo -e "${GREEN}✓ Cluster API is accessible${NC}"
else
    echo -e "${RED}✗ Cannot access cluster API${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check cluster status on bastion:"
    echo "     ssh root@${BASTION_HOST}"
    echo "     oc --kubeconfig=${KUBECONFIG_PATH} get nodes"
    echo ""
    echo "  2. Check if cluster is still installing:"
    echo "     oc --kubeconfig=${KUBECONFIG_PATH} get clusterversion"
    echo ""
    echo "  3. Verify API server is running:"
    echo "     oc --kubeconfig=${KUBECONFIG_PATH} get pods -n openshift-kube-apiserver"
    exit 1
fi
echo ""

#------------------------------------------------------------------------------
# Check 5: Node Status
#------------------------------------------------------------------------------

echo -e "${BLUE}Check 5: Cluster Nodes${NC}"
echo "-------------------------------------"

NODE_OUTPUT=$(ssh root@${BASTION_HOST} "oc --kubeconfig=${KUBECONFIG_PATH} get nodes --no-headers 2>/dev/null" || echo "")

if [ -n "$NODE_OUTPUT" ]; then
    NODE_COUNT=$(echo "$NODE_OUTPUT" | wc -l)
    READY_COUNT=$(echo "$NODE_OUTPUT" | grep -c " Ready " || echo "0")

    echo -e "${GREEN}✓ Cluster has ${NODE_COUNT} nodes (${READY_COUNT} ready)${NC}"
    echo ""
    echo "Nodes:"
    echo "$NODE_OUTPUT" | while read line; do
        echo "  $line"
    done

    # Warn if not all ready
    if [ "$READY_COUNT" -lt "$NODE_COUNT" ]; then
        echo ""
        echo -e "${YELLOW}⚠ Not all nodes are ready${NC}"
        echo "  This may be normal if cluster just finished deploying"
        echo "  Wait a few minutes and check again"
    fi
else
    echo -e "${RED}✗ No nodes found${NC}"
    echo ""
    echo "Cluster may still be installing. Check:"
    echo "  ssh root@${BASTION_HOST}"
    echo "  tail -f /root/assisted-installer.log"
    exit 1
fi
echo ""

#------------------------------------------------------------------------------
# Check 6: Cluster Version
#------------------------------------------------------------------------------

echo -e "${BLUE}Check 6: Cluster Version${NC}"
echo "-------------------------------------"

CLUSTER_VERSION=$(ssh root@${BASTION_HOST} "oc --kubeconfig=${KUBECONFIG_PATH} get clusterversion -o jsonpath='{.items[0].status.desired.version}' 2>/dev/null" || echo "unknown")

if [ "$CLUSTER_VERSION" != "unknown" ] && [ -n "$CLUSTER_VERSION" ]; then
    echo -e "${GREEN}✓ OpenShift version: ${CLUSTER_VERSION}${NC}"

    # Check if upgrade in progress
    PROGRESSING=$(ssh root@${BASTION_HOST} "oc --kubeconfig=${KUBECONFIG_PATH} get clusterversion -o jsonpath='{.items[0].status.conditions[?(@.type==\"Progressing\")].status}' 2>/dev/null" || echo "")

    if [ "$PROGRESSING" = "True" ]; then
        echo -e "${YELLOW}⚠ Cluster upgrade in progress${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Could not determine cluster version${NC}"
fi
echo ""

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✓ Cluster Validation Successful${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Cluster is accessible and appears healthy."
echo ""
echo "To access cluster:"
echo "  ssh root@${BASTION_HOST}"
echo "  export KUBECONFIG=${KUBECONFIG_PATH}"
echo "  oc get nodes"
echo "  oc get pods -A"
echo ""
