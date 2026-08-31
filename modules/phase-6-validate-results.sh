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

# Check 1: Wrapper exit code (advisory only)
# "make jobs" is a loop over jobs.config and does not produce a reliable
# aggregate exit code, so RUN_EXIT_CODE only tells us whether the run_cpt.sh
# wrapper/SSH invocation crashed. It is reported but does NOT decide the
# verdict -- the jobs.log ERROR scan (Check 2) is the source of truth.
echo "Check 1: Wrapper Execution Status (advisory)"
echo "--------------------------------------" >> "$VALIDATION_REPORT"

if [ "$RUN_EXIT_CODE" = "0" ]; then
    echo "✅ run_cpt.sh wrapper: exit code 0" | tee -a "$VALIDATION_REPORT"
else
    echo "⚠️  run_cpt.sh wrapper: non-zero exit code (${RUN_EXIT_CODE:-unknown}) — advisory, see Check 2" | tee -a "$VALIDATION_REPORT"
fi
echo "" >> "$VALIDATION_REPORT"

# Check 2: Jobs log collected and error-free (the verdict)
# "make jobs" writes a timestamped jobs.log-<date>. Success = the log was
# collected from the controller AND contains no ERROR lines.
echo ""
echo "Check 2: Jobs Log"
echo "--------------------------------------" >> "$VALIDATION_REPORT"

# Prefer the log recorded by Phase 5; fall back to newest collected jobs.log-*.
JOBS_LOG_PATH=""
if [ -n "$JOBS_LOG" ] && [ -f "${ARTIFACT_DIR}/regulus-results/${JOBS_LOG}" ]; then
    JOBS_LOG_PATH="${ARTIFACT_DIR}/regulus-results/${JOBS_LOG}"
else
    JOBS_LOG_PATH=$(ls -1t "${ARTIFACT_DIR}"/regulus-results/jobs.log-* 2>/dev/null | head -1)
fi

if [ -n "$JOBS_LOG_PATH" ] && [ -f "$JOBS_LOG_PATH" ]; then
    ERROR_COUNT=$(grep -c "ERROR" "$JOBS_LOG_PATH" || true)
    if [ "$ERROR_COUNT" -eq 0 ]; then
        echo "✅ Jobs log: $(basename "$JOBS_LOG_PATH") (no ERRORs)" | tee -a "$VALIDATION_REPORT"
    else
        echo "❌ Jobs log: $(basename "$JOBS_LOG_PATH") ($ERROR_COUNT ERROR line(s))" | tee -a "$VALIDATION_REPORT"
        grep -n "ERROR" "$JOBS_LOG_PATH" | tee -a "$VALIDATION_REPORT"
        VALIDATION_PASSED=false
    fi
else
    echo "❌ Jobs log: NOT COLLECTED — make jobs may not have run" | tee -a "$VALIDATION_REPORT"
    VALIDATION_PASSED=false
fi
echo "" >> "$VALIDATION_REPORT"

# Check 3: Run summary (tail of the jobs log, for context)
echo ""
echo "Check 3: Run Summary"
echo "--------------------------------------" >> "$VALIDATION_REPORT"

if [ -n "$JOBS_LOG_PATH" ] && [ -f "$JOBS_LOG_PATH" ]; then
    echo "Last 20 lines of $(basename "$JOBS_LOG_PATH"):" | tee -a "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"
    tail -20 "$JOBS_LOG_PATH" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"
else
    echo "⚠️  No jobs log to summarize" | tee -a "$VALIDATION_REPORT"
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
