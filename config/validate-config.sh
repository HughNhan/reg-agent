#!/bin/bash
# Config JSON Validator - Top-level Orchestrator
# Validates configuration JSON files against schema before deployment
#
# ARCHITECTURE:
# This orchestrator sources modules/lib/validate-config.sh which contains
# the single source of truth for all validation logic, then calls each
# module's validation function.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCHEMA_FILE="${SCRIPT_DIR}/config.schema.json"

# Source the validation library (single source of truth)
source "${ROOT_DIR}/modules/lib/validate-config.sh"

# Colors (if not already defined by library)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

# Validation counters
ERRORS=0
WARNINGS=0

# Usage
if [ -z "$1" ]; then
    echo "Usage: $0 <config-file.json>"
    exit 1
fi

CONFIG_FILE="$1"

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

# Find line number for a JSON path (e.g., ".quads.api_server")
find_line() {
    local json_path="$1"
    local key=$(echo "$json_path" | awk -F. '{print $NF}' | tr -d '"')
    local section=$(echo "$json_path" | awk -F. '{print $(NF-1)}' | tr -d '"')
    local line_num=""

    if [ -n "$section" ] && [ "$section" != "$key" ]; then
        # Find section first, then search for key within that context
        local section_line=$(grep -n "\"$section\"" "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d: -f1)
        if [ -n "$section_line" ]; then
            # Search for key after the section line
            line_num=$(grep -n "\"$key\"" "$CONFIG_FILE" 2>/dev/null | awk -F: -v sl="$section_line" '$1 > sl {print $1; exit}')
        fi
    fi

    # Fallback: search globally if section search didn't work
    if [ -z "$line_num" ]; then
        line_num=$(grep -n "\"$key\"" "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d: -f1)
    fi

    echo "$line_num"
}

# Report error with line number
report_error() {
    local message="$1"
    local json_path="$2"

    echo -e "${RED}✗ ${message}${NC}"
    if [ -n "$json_path" ]; then
        local line=$(find_line "$json_path")
        [ -n "$line" ] && echo "  → Line ${line}"
    fi
    ERRORS=$((ERRORS + 1))
}

# Report warning with line number
report_warning() {
    local message="$1"
    local json_path="$2"

    echo -e "${YELLOW}⚠ ${message}${NC}"
    if [ -n "$json_path" ]; then
        local line=$(find_line "$json_path")
        [ -n "$line" ] && echo "  → Line ${line}"
    fi
    WARNINGS=$((WARNINGS + 1))
}

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Config Validator${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Validating: ${CONFIG_FILE}"
echo ""

#------------------------------------------------------------------------------
# Basic Checks
#------------------------------------------------------------------------------

# File exists check
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}✗ File not found: ${CONFIG_FILE}${NC}"
    exit 1
fi

# JSON syntax check
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    echo -e "${RED}✗ Invalid JSON syntax${NC}"
    echo ""
    jq empty "$CONFIG_FILE" 2>&1 || true
    exit 1
fi

echo -e "${GREEN}✓ Valid JSON syntax${NC}"

#------------------------------------------------------------------------------
# Schema Validation (if ajv-cli available)
#------------------------------------------------------------------------------

if command -v ajv &> /dev/null; then
    echo -e "${BLUE}Running JSON schema validation...${NC}"
    if ajv validate -s "$SCHEMA_FILE" -d "$CONFIG_FILE" 2>&1 | tee /tmp/ajv-output.log; then
        echo -e "${GREEN}✓ Schema validation passed${NC}"
    else
        echo -e "${RED}✗ Schema validation failed${NC}"
        cat /tmp/ajv-output.log
        ERRORS=$((ERRORS + 1))
    fi
    echo ""
else
    echo -e "${YELLOW}ℹ ajv-cli not installed, skipping formal schema validation${NC}"
    echo "  Install with: npm install -g ajv-cli"
    echo ""
fi

#------------------------------------------------------------------------------
# Module Validation (calls module validators from library)
#------------------------------------------------------------------------------

echo ""
# Call QUADS module validator
validate_quads_config "$CONFIG_FILE" "report_error" "report_warning"

echo ""
# Call Jetlag module validator
validate_jetlag_config "$CONFIG_FILE" "report_error" "report_warning"

# Cross-validation: QUADS allocation vs Jetlag cluster requirements
QUADS_MODE=$(jq -r '.quads.mode // "allocate"' "$CONFIG_FILE")
CLUSTER_TYPE=$(jq -r '.jetlag.cluster_type // empty' "$CONFIG_FILE")
if [[ "$CLUSTER_TYPE" == "mno" ]] && [[ "$QUADS_MODE" == "allocate" ]]; then
    NUM_HOSTS=$(jq -r '.quads.num_hosts // 0' "$CONFIG_FILE")
    WORKER_COUNT=$(jq -r '.jetlag.worker_node_count // 0' "$CONFIG_FILE")

    if [[ -n "$NUM_HOSTS" ]] && [[ -n "$WORKER_COUNT" ]]; then
        # MNO requires: 1 bastion + 3 control-plane + N workers
        REQUIRED_HOSTS=$((1 + 3 + WORKER_COUNT))

        if [[ "$NUM_HOSTS" -lt "$REQUIRED_HOSTS" ]]; then
            report_error "Insufficient hosts: QUADS allocating ${NUM_HOSTS}, but MNO with ${WORKER_COUNT} workers needs ${REQUIRED_HOSTS} (1 bastion + 3 control-plane + ${WORKER_COUNT} workers)" ".jetlag.worker_node_count"
            echo "  → Fix: Reduce worker_node_count to $((NUM_HOSTS - 4)) or increase num_hosts to ${REQUIRED_HOSTS}"
        elif [[ "$NUM_HOSTS" -gt "$REQUIRED_HOSTS" ]]; then
            MAX_WORKERS=$((NUM_HOSTS - 4))
            report_warning "Allocated ${NUM_HOSTS} hosts but only using ${REQUIRED_HOSTS}. You could have up to ${MAX_WORKERS} workers." ".jetlag.worker_node_count"
        else
            echo -e "${GREEN}✓ Host allocation matches cluster requirements (${NUM_HOSTS} hosts for ${WORKER_COUNT} workers)${NC}"
        fi
    fi
fi

echo ""
# Call Crucible module validator
validate_crucible_config "$CONFIG_FILE" "report_error" "report_warning"

echo ""
# Call Regulus module validator
validate_regulus_config "$CONFIG_FILE" "report_error" "report_warning"

#------------------------------------------------------------------------------
# Lab Configuration
#------------------------------------------------------------------------------

echo ""
echo -e "${BLUE}Checking lab configuration...${NC}"

SSH_PASSWORD=$(jq -r '.lab.ssh_password // empty' "$CONFIG_FILE")
if [ -z "$SSH_PASSWORD" ]; then
    report_warning "Missing lab.ssh_password (recommended for automated SSH)" ".lab.ssh_password"
fi

#------------------------------------------------------------------------------
# Security Checks
#------------------------------------------------------------------------------

echo ""
echo -e "${BLUE}Running security checks...${NC}"

# Check for common placeholder passwords
if grep -qiE '(your-lab-password|changeme|password123|example-password|placeholder)' "$CONFIG_FILE" 2>/dev/null; then
    PLACEHOLDER_LINES=$(grep -niE '(your-lab-password|changeme|password123|example-password|placeholder)' "$CONFIG_FILE" | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
    echo -e "${RED}✗ Placeholder values detected${NC}"
    echo "  Found placeholder text that must be replaced with real values"
    echo "  → Lines: ${PLACEHOLDER_LINES}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ No obvious placeholders detected${NC}"
fi

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}✗ Validation FAILED${NC}"
    echo ""
    echo "  Errors:   ${ERRORS}"
    echo "  Warnings: ${WARNINGS}"
    echo ""
    echo "Fix the errors above before deploying."
    echo "Each error shows the line number where the issue was found."
    echo ""
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠ Validation PASSED with warnings${NC}"
    echo ""
    echo "  Warnings: ${WARNINGS}"
    echo ""
    echo "Configuration is valid but has warnings."
    echo "Review warnings above - they may cause issues during deployment."
    echo ""
    exit 0
else
    echo -e "${GREEN}✓ Validation PASSED${NC}"
    echo ""
    echo "Configuration is valid and ready for deployment."
    echo ""
    exit 0
fi
