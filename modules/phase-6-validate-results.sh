#!/bin/bash
# Phase 6: Result Validation
# Validates test results and generates reports

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG_AGENT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source configuration and state
# Load JSON configuration
source "${REG_AGENT_ROOT}/modules/lib/json-config.sh"
json_export_env ".regulus" "REGULUS"
source "${REG_AGENT_ROOT}/vars/state.env"

# Load logging library
source "${REG_AGENT_ROOT}/modules/lib/logging.sh"
init_logging "regulus" "phase-6-validate-results"

echo "============================================="
echo "Phase 6: Result Validation"
echo "============================================="
echo ""
log "========================================"
log "Phase 6: Result Validation"
log "========================================"

# Check if we have results
if [ -z "$RUN_ID" ]; then
    echo "Error: No run ID found in state"
    echo "Run: make run"
    exit 1
fi

ARTIFACT_DIR="${REG_AGENT_ROOT}/artifacts/${RUN_ID}"

if [ ! -d "$ARTIFACT_DIR" ]; then
    echo "Error: Artifact directory not found: $ARTIFACT_DIR"
    exit 1
fi

echo "Run ID: $RUN_ID"
echo "Artifacts: $ARTIFACT_DIR"
echo ""

# Validation checks
VALIDATION_PASSED=true
VALIDATION_REPORT="${ARTIFACT_DIR}/validation-report.txt"

echo "=========================================" > "$VALIDATION_REPORT"
echo "reg-agent Validation Report" >> "$VALIDATION_REPORT"
echo "=========================================" >> "$VALIDATION_REPORT"
echo "Run ID: $RUN_ID" >> "$VALIDATION_REPORT"
echo "Timestamp: $(date)" >> "$VALIDATION_REPORT"
echo "" >> "$VALIDATION_REPORT"

# Check 1: Test execution exit code
echo "Check 1: Test Execution Status"
echo "--------------------------------------" >> "$VALIDATION_REPORT"

if [ "$RUN_EXIT_CODE" = "0" ]; then
    echo "✅ Test execution: PASSED (exit code 0)" | tee -a "$VALIDATION_REPORT"
else
    echo "❌ Test execution: FAILED (exit code $RUN_EXIT_CODE)" | tee -a "$VALIDATION_REPORT"
    VALIDATION_PASSED=false
fi
echo "" >> "$VALIDATION_REPORT"

# Check 2: Result files exist
echo ""
echo "Check 2: Result Files"
echo "--------------------------------------" >> "$VALIDATION_REPORT"

if [ -d "${ARTIFACT_DIR}/regulus-results" ]; then
    NUM_FILES=$(find "${ARTIFACT_DIR}/regulus-results" -type f | wc -l)
    echo "✅ Result files: FOUND ($NUM_FILES files)" | tee -a "$VALIDATION_REPORT"

    # List key files
    if [ -f "${ARTIFACT_DIR}/regulus-results/result-summary.txt" ]; then
        echo "  ✓ result-summary.txt found" | tee -a "$VALIDATION_REPORT"
    fi
else
    echo "❌ Result files: NOT FOUND" | tee -a "$VALIDATION_REPORT"
    VALIDATION_PASSED=false
fi
echo "" >> "$VALIDATION_REPORT"

# Check 3: Parse results (if result-summary.txt exists)
echo ""
echo "Check 3: Result Summary"
echo "--------------------------------------" >> "$VALIDATION_REPORT"

if [ -f "${ARTIFACT_DIR}/regulus-results/result-summary.txt" ]; then
    echo "Result Summary:" | tee -a "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"
    cat "${ARTIFACT_DIR}/regulus-results/result-summary.txt" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    # Extract key metrics (this is basic - can be enhanced)
    if grep -q "result:" "${ARTIFACT_DIR}/regulus-results/result-summary.txt"; then
        echo "✅ Metrics found in result summary" | tee -a "$VALIDATION_REPORT"
    else
        echo "⚠️  No metrics found in result summary" | tee -a "$VALIDATION_REPORT"
    fi
else
    echo "⚠️  result-summary.txt not found" | tee -a "$VALIDATION_REPORT"
fi
echo "" >> "$VALIDATION_REPORT"

# Check 4: Logs
echo ""
echo "Check 4: Logs"
echo "--------------------------------------" >> "$VALIDATION_REPORT"

if [ -f "${ARTIFACT_DIR}/logs/regulus-run.log" ]; then
    LOG_SIZE=$(stat -f%z "${ARTIFACT_DIR}/logs/regulus-run.log" 2>/dev/null || stat -c%s "${ARTIFACT_DIR}/logs/regulus-run.log" 2>/dev/null || echo "0")
    echo "✅ Execution log: FOUND (${LOG_SIZE} bytes)" | tee -a "$VALIDATION_REPORT"

    # Check for errors in log
    if grep -qi "error" "${ARTIFACT_DIR}/logs/regulus-run.log"; then
        ERROR_COUNT=$(grep -ci "error" "${ARTIFACT_DIR}/logs/regulus-run.log")
        echo "  ⚠️  Found $ERROR_COUNT error mentions in log" | tee -a "$VALIDATION_REPORT"
    fi
else
    echo "⚠️  Execution log: NOT FOUND" | tee -a "$VALIDATION_REPORT"
fi
echo "" >> "$VALIDATION_REPORT"

# Overall validation result
echo ""
echo "=========================================" >> "$VALIDATION_REPORT"
echo "Overall Validation Result" >> "$VALIDATION_REPORT"
echo "=========================================" >> "$VALIDATION_REPORT"

if [ "$VALIDATION_PASSED" = "true" ]; then
    echo "✅ VALIDATION PASSED" | tee -a "$VALIDATION_REPORT"
    OVERALL_STATUS="PASSED"
else
    echo "❌ VALIDATION FAILED" | tee -a "$VALIDATION_REPORT"
    OVERALL_STATUS="FAILED"
fi
echo "" >> "$VALIDATION_REPORT"

# Save validation status to state
echo "VALIDATION_STATUS=${OVERALL_STATUS}" >> "${REG_AGENT_ROOT}/vars/state.env"

# Display report
echo ""
echo "========================================="
echo "Validation Report"
echo "========================================="
cat "$VALIDATION_REPORT"

# Generate summary JSON (optional, for programmatic access)
cat > "${ARTIFACT_DIR}/validation-summary.json" <<EOF
{
  "run_id": "$RUN_ID",
  "timestamp": "$(date -Iseconds)",
  "validation_status": "$OVERALL_STATUS",
  "test_exit_code": ${RUN_EXIT_CODE:-null},
  "artifacts_dir": "$ARTIFACT_DIR"
}
EOF

echo ""
echo "========================================="
echo "✅ Phase 6: Validation Complete"
echo "========================================="
echo "Status: $OVERALL_STATUS"
echo "Report: $VALIDATION_REPORT"
echo "Summary: ${ARTIFACT_DIR}/validation-summary.json"
echo ""

if [ "$OVERALL_STATUS" = "PASSED" ]; then
    exit 0
else
    exit 1
fi
