#!/bin/bash
# Phase 5: Regulus Run
# Executes Regulus tests via run_cpt.sh (which handles reg-smart-config, init-lab, and test execution)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG_AGENT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Source configuration and state
# Load JSON configuration
source "${REG_AGENT_ROOT}/modules/lib/json-config.sh"
json_export_env ".regulus" "REGULUS"
json_export_env ".crucible_controller" "CRUCIBLE_CONTROLLER"

# Normalize CRUCIBLE_CONTROLLER_TARGET
# If target is set to a hostname that matches BASTION_HOST, normalize it to "bastion"
if [ -n "$CRUCIBLE_CONTROLLER_TARGET" ] && [ -n "$BASTION_HOST" ]; then
    if [ "$CRUCIBLE_CONTROLLER_TARGET" = "$BASTION_HOST" ]; then
        CRUCIBLE_CONTROLLER_TARGET="bastion"
    fi
fi

source "${REG_AGENT_ROOT}/vars/state.env"

# Load logging library
source "${REG_AGENT_ROOT}/modules/lib/logging.sh"
init_logging "regulus" "phase-5-regulus-run"

# Determine execution host (mirror Phase 4 logic)
# User is always root for crucible/regulus
CRUCIBLE_CONTROLLER_TARGET=${CRUCIBLE_CONTROLLER_TARGET:-bastion}

if [ "$CRUCIBLE_CONTROLLER_TARGET" = "bastion" ]; then
    REGULUS_HOST="$BASTION_HOST"
elif [ "$CRUCIBLE_CONTROLLER_TARGET" = "other" ]; then
    REGULUS_HOST="$CRUCIBLE_CONTROLLER_OTHER_HOST"
else
    echo -e "${RED}Error: Invalid CRUCIBLE_CONTROLLER_TARGET: $CRUCIBLE_CONTROLLER_TARGET${NC}"
    echo "Valid values: 'bastion' or 'other'"
    echo ""
    echo "Next steps:"
    echo "  1. Check vars/config.json: crucible_controller.target"
    echo "  2. Run: make -C modules/regulus configure"
    log "ERROR: Invalid CRUCIBLE_CONTROLLER_TARGET: $CRUCIBLE_CONTROLLER_TARGET"
    exit 1
fi

# Validate BASTION_HOST is set (always required for OCP access)
if [ -z "$BASTION_HOST" ]; then
    echo -e "${RED}Error: BASTION_HOST not set${NC}"
    echo "BASTION_HOST is required for Regulus to access the OpenShift cluster"
    echo ""
    echo "Next steps:"
    echo "  1. Verify Phase 2 completed: check vars/state.env"
    echo "  2. Or manually set BASTION_HOST in vars/state.env"
    log "ERROR: BASTION_HOST not set - cannot proceed"
    exit 1
fi

echo "============================================="
echo "Phase 5: Regulus Test Execution"
echo "============================================="
echo ""
log "========================================"
log "Phase 5: Regulus Test Execution"
log "========================================"
echo "Controller: $REGULUS_HOST"
echo "Regulus: $REGULUS_PATH"
echo "Test: $REGULUS_TEST"
echo ""

# Check SSH access
if ! ssh -o ConnectTimeout=10 root@${REGULUS_HOST} "echo ok" &>/dev/null; then
    echo -e "${RED}Error: Cannot SSH to controller at root@${REGULUS_HOST}${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Verify SSH access: ssh root@${REGULUS_HOST}"
    echo "  2. Check Phase 4 completed: make -C modules/regulus status"
    echo "  3. Verify CRUCIBLE_CONTROLLER settings in vars/config.json"
    log "ERROR: SSH access failed to root@${REGULUS_HOST}"
    exit 1
fi

# Verify Regulus is setup
echo "Verifying Regulus setup..."
if ! ssh root@${REGULUS_HOST} "[ -f ${REGULUS_PATH}/run_cpt.sh ]"; then
    echo -e "${RED}Error: run_cpt.sh not found at ${REGULUS_PATH}${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Run Phase 4: make -C modules/regulus install"
    echo "  2. Verify REGULUS_PATH in vars/state.env"
    log "ERROR: run_cpt.sh not found at ${REGULUS_HOST}:${REGULUS_PATH}"
    exit 1
fi
echo -e "${GREEN}✓ Regulus ready${NC}"
echo ""

# Create artifact directory for this run
RUN_ID="run-$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${REG_AGENT_ROOT}/artifacts/${RUN_ID}"
mkdir -p "$ARTIFACT_DIR/logs"

echo ""
echo "Run ID: $RUN_ID"
echo "Artifacts: $ARTIFACT_DIR"
echo ""

# Run Regulus tests on bastion
echo "========================================="
echo "Executing Regulus Tests (run_cpt.sh)"
echo "========================================="
echo ""
echo "run_cpt.sh will:"
echo "  1. Run reg-smart-config (auto-detect NICs)"
echo "  2. Run make init-lab (lab-analyzer, SRIOV_INIT, INVENTORY)"
echo "  3. Run make init-jobs (test job configuration)"
echo "  4. Execute performance tests"
echo ""
echo "This may take several minutes to hours depending on test configuration..."
echo ""

# Execute run_cpt.sh directly (it handles bootstrap and all initialization)
ssh root@${REGULUS_HOST} "cd ${REGULUS_PATH} && bash run_cpt.sh" 2>&1 | tee "${ARTIFACT_DIR}/logs/regulus-run.log"

# Capture the actual SSH command exit code, not tee's exit code
RUN_EXIT_CODE=${PIPESTATUS[0]}

# Save run metadata
echo "RUN_ID=${RUN_ID}" >> "${REG_AGENT_ROOT}/vars/state.env"
echo "RUN_EXIT_CODE=${RUN_EXIT_CODE}" >> "${REG_AGENT_ROOT}/vars/state.env"
echo "RUN_TIMESTAMP=$(date -Iseconds)" >> "${REG_AGENT_ROOT}/vars/state.env"

if [ $RUN_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ Regulus tests completed successfully"
else
    echo ""
    echo "⚠️  Regulus tests failed with exit code: $RUN_EXIT_CODE"
    echo "Check logs: ${ARTIFACT_DIR}/logs/regulus-run.log"
fi

# Collect results from Regulus host
echo ""
echo "Collecting results from ${REGULUS_HOST}..."

# Find latest results directory
LATEST_RESULT=$(ssh root@${REGULUS_HOST} "cd ${REGULUS_PATH} && readlink -f latest 2>/dev/null || echo ''")

if [ -n "$LATEST_RESULT" ] && ssh root@${REGULUS_HOST} "[ -d '$LATEST_RESULT' ]"; then
    echo "Latest results: $LATEST_RESULT"

    # Copy results
    mkdir -p "${ARTIFACT_DIR}/regulus-results"

    if command -v rsync &>/dev/null; then
        rsync -az root@${REGULUS_HOST}:${LATEST_RESULT}/ "${ARTIFACT_DIR}/regulus-results/"
        echo -e "${GREEN}✓ Results copied via rsync${NC}"
    else
        scp -r root@${REGULUS_HOST}:${LATEST_RESULT}/* "${ARTIFACT_DIR}/regulus-results/" 2>/dev/null || echo "⚠️  Some results may not have copied"
        echo -e "${GREEN}✓ Results copied via scp${NC}"
    fi

    # Copy result-summary.txt if it exists
    if [ -f "${ARTIFACT_DIR}/regulus-results/result-summary.txt" ]; then
        echo ""
        echo "========================================="
        echo "Result Summary"
        echo "========================================="
        cat "${ARTIFACT_DIR}/regulus-results/result-summary.txt"
        echo ""
    fi
else
    echo "⚠️  No results directory found on bastion"
fi

# Create symlink to latest artifacts
cd "${REG_AGENT_ROOT}/artifacts"
rm -f latest
ln -s "$RUN_ID" latest
echo "✓ Created symlink: artifacts/latest -> $RUN_ID"

echo ""
echo "========================================="
echo "✅ Phase 5: Test Execution Complete"
echo "========================================="
echo "Run ID: $RUN_ID"
echo "Exit Code: $RUN_EXIT_CODE"
echo "Artifacts: $ARTIFACT_DIR"
echo "Latest: ${REG_AGENT_ROOT}/artifacts/latest"
echo ""

if [ $RUN_EXIT_CODE -eq 0 ]; then
    echo "✅ Tests completed successfully"
else
    echo "❌ Tests failed - check logs for details"
fi

echo ""

exit $RUN_EXIT_CODE
