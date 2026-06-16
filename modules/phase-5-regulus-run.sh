#!/bin/bash
# Phase 5: Regulus Run
# Executes Regulus tests via run_cpt.sh (which handles reg-smart-config, init-lab, and test execution)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG_AGENT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source configuration and state
# Load JSON configuration
source "${REG_AGENT_ROOT}/modules/lib/json-config.sh"
json_export_env ".regulus" "REGULUS"
source "${REG_AGENT_ROOT}/vars/state.env"

# Load logging library
source "${REG_AGENT_ROOT}/modules/lib/logging.sh"
init_logging "regulus" "phase-5-regulus-run"

echo "============================================="
echo "Phase 5: Regulus Test Execution"
echo "============================================="
echo ""
log "========================================"
log "Phase 5: Regulus Test Execution"
log "========================================"
echo "Bastion: $BASTION_HOST"
echo "Regulus: $REGULUS_PATH"
echo "Test: $REGULUS_TEST"
echo ""

# Check SSH access
if ! ssh -o ConnectTimeout=10 root@$BASTION_HOST "echo ok" &>/dev/null; then
    echo "Error: Cannot SSH to bastion at $BASTION_HOST"
    exit 1
fi

# Verify Regulus is setup
echo "Verifying Regulus setup..."
if ! ssh root@$BASTION_HOST "[ -f ${REGULUS_PATH}/run_cpt.sh ]"; then
    echo "Error: run_cpt.sh not found at ${REGULUS_PATH}"
    echo "Run: make regulus-setup"
    exit 1
fi
echo "✓ Regulus ready"
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
ssh root@$BASTION_HOST "cd ${REGULUS_PATH} && bash run_cpt.sh" 2>&1 | tee "${ARTIFACT_DIR}/logs/regulus-run.log"

RUN_EXIT_CODE=$?

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

# Collect results from bastion
echo ""
echo "Collecting results from bastion..."

# Find latest results directory
LATEST_RESULT=$(ssh root@$BASTION_HOST "cd ${REGULUS_PATH} && readlink -f latest 2>/dev/null || echo ''")

if [ -n "$LATEST_RESULT" ] && ssh root@$BASTION_HOST "[ -d '$LATEST_RESULT' ]"; then
    echo "Latest results: $LATEST_RESULT"

    # Copy results
    mkdir -p "${ARTIFACT_DIR}/regulus-results"

    if command -v rsync &>/dev/null; then
        rsync -az root@${BASTION_HOST}:${LATEST_RESULT}/ "${ARTIFACT_DIR}/regulus-results/"
        echo "✓ Results copied via rsync"
    else
        scp -r root@${BASTION_HOST}:${LATEST_RESULT}/* "${ARTIFACT_DIR}/regulus-results/" 2>/dev/null || echo "⚠️  Some results may not have copied"
        echo "✓ Results copied via scp"
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
