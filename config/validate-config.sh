#!/bin/bash
# Config JSON Validator
# Validates configuration JSON files against schema before deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCHEMA_FILE="${SCRIPT_DIR}/config.schema.json"

# Colors
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
# Deployment Mode Validation
#------------------------------------------------------------------------------

echo -e "${BLUE}Checking deployment configuration...${NC}"

DEPLOY_MODE=$(jq -r '.deployment_mode // "full"' "$CONFIG_FILE")
if [ "$DEPLOY_MODE" != "full" ] && [ "$DEPLOY_MODE" != "cluster-ready" ]; then
    report_error "Invalid deployment_mode: ${DEPLOY_MODE} (valid: full, cluster-ready)" ".deployment_mode"
else
    echo -e "${GREEN}✓ Deployment mode: ${DEPLOY_MODE}${NC}"
fi

#------------------------------------------------------------------------------
# QUADS Configuration
#------------------------------------------------------------------------------

echo ""
echo -e "${BLUE}Checking QUADS configuration...${NC}"

QUADS_MODE=$(jq -r '.quads.mode // "allocate"' "$CONFIG_FILE")
if [ "$QUADS_MODE" != "allocate" ] && [ "$QUADS_MODE" != "import" ]; then
    report_error "Invalid quads.mode: ${QUADS_MODE} (valid: allocate, import)" ".quads.mode"
else
    echo -e "${GREEN}✓ QUADS mode: ${QUADS_MODE}${NC}"
fi

# Required fields
API_SERVER=$(jq -r '.quads.api_server // empty' "$CONFIG_FILE")
USERNAME=$(jq -r '.quads.username // empty' "$CONFIG_FILE")
LAB=$(jq -r '.quads.lab // empty' "$CONFIG_FILE")

if [ -z "$API_SERVER" ]; then
    report_error "Missing quads.api_server" ".quads.api_server"
fi

if [ -z "$USERNAME" ]; then
    report_error "Missing quads.username" ".quads.username"
fi

if [ -z "$LAB" ]; then
    report_error "Missing quads.lab" ".quads.lab"
elif [ "$LAB" != "scalelab" ] && [ "$LAB" != "performancelab" ]; then
    report_error "Invalid quads.lab: ${LAB} (valid: scalelab, performancelab)" ".quads.lab"
fi

# Authentication
PASSWORD=$(jq -r '.quads.password // empty' "$CONFIG_FILE")
API_TOKEN=$(jq -r '.quads.api_token // empty' "$CONFIG_FILE")
if [ -z "$PASSWORD" ] && [ -z "$API_TOKEN" ]; then
    report_warning "No password or api_token configured (at least one required)" ".quads.password"
fi

# Mode-specific validation
if [ "$QUADS_MODE" = "allocate" ]; then
    NUM_HOSTS=$(jq -r '.quads.num_hosts // empty' "$CONFIG_FILE")
    PREFERRED_MODEL=$(jq -r '.quads.preferred_model // empty' "$CONFIG_FILE")
    WORKLOAD_NAME=$(jq -r '.quads.workload_name // empty' "$CONFIG_FILE")

    if [ -z "$NUM_HOSTS" ]; then
        report_error "Missing quads.num_hosts (required for allocate mode)" ".quads.num_hosts"
    fi

    if [ -z "$PREFERRED_MODEL" ]; then
        report_warning "Missing quads.preferred_model" ".quads.preferred_model"
    fi

    if [ -z "$WORKLOAD_NAME" ]; then
        report_warning "Missing quads.workload_name" ".quads.workload_name"
    fi
elif [ "$QUADS_MODE" = "import" ]; then
    CLOUD_NAME=$(jq -r '.quads.cloud_name // empty' "$CONFIG_FILE")
    if [ -z "$CLOUD_NAME" ]; then
        report_error "Missing quads.cloud_name (required for import mode)" ".quads.cloud_name"
    fi
fi

#------------------------------------------------------------------------------
# Jetlag Configuration (only required for full mode)
#------------------------------------------------------------------------------

if [ "$DEPLOY_MODE" = "full" ]; then
    echo ""
    echo -e "${BLUE}Checking Jetlag configuration...${NC}"

    CLUSTER_TYPE=$(jq -r '.jetlag.cluster_type // empty' "$CONFIG_FILE")
    if [ -z "$CLUSTER_TYPE" ]; then
        report_error "Missing jetlag.cluster_type" ".jetlag.cluster_type"
    elif [ "$CLUSTER_TYPE" != "mno" ] && [ "$CLUSTER_TYPE" != "sno" ]; then
        report_error "Invalid jetlag.cluster_type: ${CLUSTER_TYPE} (valid: mno, sno)" ".jetlag.cluster_type"
    else
        echo -e "${GREEN}✓ Cluster type: ${CLUSTER_TYPE}${NC}"
    fi

    OCP_BUILD=$(jq -r '.jetlag.ocp_build // empty' "$CONFIG_FILE")
    OCP_VERSION=$(jq -r '.jetlag.ocp_version // empty' "$CONFIG_FILE")
    NETWORK_STACK=$(jq -r '.jetlag.network_stack // empty' "$CONFIG_FILE")

    [ -z "$OCP_BUILD" ] && report_error "Missing jetlag.ocp_build" ".jetlag.ocp_build"
    [ -z "$OCP_VERSION" ] && report_error "Missing jetlag.ocp_version" ".jetlag.ocp_version"
    [ -z "$NETWORK_STACK" ] && report_error "Missing jetlag.network_stack" ".jetlag.network_stack"

    # Pull secret validation
    PULL_SECRET=$(jq -r '.jetlag.pull_secret_path // empty' "$CONFIG_FILE")
    if [ -n "$PULL_SECRET" ]; then
        # Expand tilde if present
        PULL_SECRET_EXPANDED="${PULL_SECRET/#\~/$HOME}"
        if [ ! -f "$PULL_SECRET_EXPANDED" ]; then
            report_warning "Pull secret file not found: ${PULL_SECRET}" ".jetlag.pull_secret_path"
        fi
    else
        report_warning "Missing jetlag.pull_secret_path" ".jetlag.pull_secret_path"
    fi

    # Cross-validate QUADS allocation vs Jetlag cluster requirements (MNO only)
    if [ "$CLUSTER_TYPE" = "mno" ] && [ "$QUADS_MODE" = "allocate" ]; then
        WORKER_COUNT=$(jq -r '.jetlag.worker_node_count // 0' "$CONFIG_FILE")

        if [ -n "$NUM_HOSTS" ] && [ -n "$WORKER_COUNT" ]; then
            # MNO requires: 1 bastion + 3 control-plane + N workers
            REQUIRED_HOSTS=$((1 + 3 + WORKER_COUNT))

            if [ "$NUM_HOSTS" -lt "$REQUIRED_HOSTS" ]; then
                report_error "Insufficient hosts: QUADS allocating ${NUM_HOSTS}, but MNO with ${WORKER_COUNT} workers needs ${REQUIRED_HOSTS} (1 bastion + 3 control-plane + ${WORKER_COUNT} workers)" ".jetlag.worker_node_count"
                echo "  → Fix: Reduce worker_node_count to $((NUM_HOSTS - 4)) or increase num_hosts to ${REQUIRED_HOSTS}"
            elif [ "$NUM_HOSTS" -gt "$REQUIRED_HOSTS" ]; then
                MAX_WORKERS=$((NUM_HOSTS - 4))
                report_warning "Allocated ${NUM_HOSTS} hosts but only using ${REQUIRED_HOSTS}. You could have up to ${MAX_WORKERS} workers." ".jetlag.worker_node_count"
            else
                echo -e "${GREEN}✓ Host allocation matches cluster requirements (${NUM_HOSTS} hosts for ${WORKER_COUNT} workers)${NC}"
            fi
        fi
    fi
fi

#------------------------------------------------------------------------------
# Crucible Configuration
#------------------------------------------------------------------------------

echo ""
echo -e "${BLUE}Checking Crucible configuration...${NC}"

CONTROLLER_TARGET=$(jq -r '.crucible_controller.target // empty' "$CONFIG_FILE")
if [ -z "$CONTROLLER_TARGET" ]; then
    report_error "Missing crucible_controller.target (valid: bastion, other)" ".crucible_controller.target"
elif [ "$CONTROLLER_TARGET" != "bastion" ] && [ "$CONTROLLER_TARGET" != "other" ]; then
    report_error "Invalid crucible_controller.target: ${CONTROLLER_TARGET} (valid: bastion, other)" ".crucible_controller.target"
else
    echo -e "${GREEN}✓ Controller target: ${CONTROLLER_TARGET}${NC}"
fi

if [ "$CONTROLLER_TARGET" = "other" ]; then
    OTHER_HOST=$(jq -r '.crucible_controller.other_host // empty' "$CONFIG_FILE")
    if [ -z "$OTHER_HOST" ]; then
        report_error "Missing crucible_controller.other_host (required when target=other)" ".crucible_controller.other_host"
    fi
fi

CRUCIBLE_REPO=$(jq -r '.crucible.git_repo // empty' "$CONFIG_FILE")
if [ -z "$CRUCIBLE_REPO" ]; then
    report_warning "Missing crucible.git_repo" ".crucible.git_repo"
fi

#------------------------------------------------------------------------------
# Regulus Configuration
#------------------------------------------------------------------------------

echo ""
echo -e "${BLUE}Checking Regulus configuration...${NC}"

REGULUS_JOBS=$(jq -r '.regulus.jobs // empty' "$CONFIG_FILE")
if [ -n "$REGULUS_JOBS" ]; then
    # Validate jobs syntax - should be space-separated paths starting with ./
    VALID_JOBS=true
    for job in $REGULUS_JOBS; do
        if [[ ! "$job" =~ ^\./.*$ ]]; then
            report_warning "Invalid job path format: ${job} (must start with './')" ".regulus.jobs"
            echo "  Example: './SANDBOX' or './1_GROUP/NO-PAO/4IP'"
            VALID_JOBS=false
            break
        fi
    done
    [ "$VALID_JOBS" = true ] && echo -e "${GREEN}✓ Jobs: ${REGULUS_JOBS}${NC}"
else
    echo -e "${YELLOW}ℹ No Regulus jobs configured (will use defaults)${NC}"
fi

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
