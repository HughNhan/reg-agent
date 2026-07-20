#!/bin/bash
# QUADS allocation using ansible-quads-ssm
# This is the default and recommended method

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG_AGENT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Generated files directory
GENERATED_DIR="${SCRIPT_DIR}/generated"
STATE_DIR="${GENERATED_DIR}/state"
LOG_DIR="${GENERATED_DIR}/logs"
OUTPUT_DIR="${GENERATED_DIR}/output"

# Ensure directories exist
mkdir -p "${STATE_DIR}" "${LOG_DIR}" "${OUTPUT_DIR}"

# Log file for this run
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/allocate_${TIMESTAMP}.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Load JSON configuration library
source "${REG_AGENT_ROOT}/modules/lib/json-config.sh"

# Load configuration from JSON
json_export_env ".quads" "QUADS"

# Load dependency checking library
source "${REG_AGENT_ROOT}/modules/lib/check-dependencies.sh"

# Set defaults for optional variables
QUADS_USER_DOMAIN=${QUADS_USER_DOMAIN:-"redhat.com"}
QUADS_WIPE_DISKS=${QUADS_WIPE_DISKS:-"yes"}
SHORT_DESCRIPTION=${SHORT_DESCRIPTION:-"$QUADS_WORKLOAD_NAME"}
QUADS_PREFERRED_MODEL=${QUADS_PREFERRED_MODEL:-"any"}

QUADS_REPO="${REG_AGENT_ROOT}/repos/ansible-quads-ssm"

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}QUADS SSM Allocation${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Check dependencies
echo "Checking Phase 1 dependencies..."
echo ""
reset_dep_check

# Repository dependencies
check_repo "ansible-quads-ssm"

# Required configuration variables
check_var "QUADS API server" "QUADS_API_SERVER"
check_var "QUADS username" "QUADS_USERNAME"
check_var "QUADS password" "QUADS_PASSWORD"
check_var "Lab" "QUADS_LAB"
check_var "Number of hosts" "QUADS_NUM_HOSTS"
check_var "Workload name" "QUADS_WORKLOAD_NAME"

# Optional: QUADS_PREFERRED_MODEL defaults to "any" (see above)

# Required commands
check_command "Ansible playbook" "ansible-playbook"
check_command "JSON parser" "jq"
check_command "curl" "curl"

# Optional: Check network access to QUADS API
if [ -n "$QUADS_API_SERVER" ]; then
    check_network "QUADS API" "$QUADS_API_SERVER"
fi

# Summarize and fail if dependencies not met
if ! summarize_deps "Phase 1: QUADS Allocation"; then
    exit 1
fi

# Set defaults
QUADS_USER_DOMAIN=${QUADS_USER_DOMAIN:-"redhat.com"}
QUADS_USER_EMAIL="${QUADS_USERNAME}@${QUADS_USER_DOMAIN}"

# Check if this workspace already has an active allocation
echo ""
echo "Checking workspace allocation status..."

# Load state if it exists
WORKSPACE_ASSIGNMENT_ID=""
WORKSPACE_CLOUD_NAME=""
if [ -f "${STATE_DIR}/current.env" ]; then
    source "${STATE_DIR}/current.env"
    WORKSPACE_ASSIGNMENT_ID="$ASSIGNMENT_ID"
    WORKSPACE_CLOUD_NAME="$CLOUD_NAME"
elif [ -f "${REG_AGENT_ROOT}/vars/state.env" ]; then
    source "${REG_AGENT_ROOT}/vars/state.env"
    WORKSPACE_ASSIGNMENT_ID="$ASSIGNMENT_ID"
    WORKSPACE_CLOUD_NAME="$CLOUD_NAME"
fi

# Get authentication token
if [ -n "$QUADS_API_TOKEN" ]; then
    QUADS_TOKEN="$QUADS_API_TOKEN"
else
    LOGIN_RESPONSE=$(curl -s -k -X POST \
        -u "${QUADS_USER_EMAIL}:${QUADS_PASSWORD}" \
        "https://${QUADS_API_SERVER}/api/v3/login/" 2>/dev/null)

    QUADS_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.auth_token // empty' 2>/dev/null)

    if [ -z "$QUADS_TOKEN" ]; then
        echo -e "${RED}✗ Authentication failed${NC}"
        echo "Please check your QUADS username and password"
        exit 1
    fi
fi

# If workspace has state, check if that assignment is still active
if [ -n "$WORKSPACE_ASSIGNMENT_ID" ]; then
    echo "Found workspace state: Assignment $WORKSPACE_ASSIGNMENT_ID ($WORKSPACE_CLOUD_NAME)"

    ASSIGNMENT_INFO=$(curl -s -k \
        -H "Authorization: Bearer ${QUADS_TOKEN}" \
        "https://${QUADS_API_SERVER}/api/v3/assignments/${WORKSPACE_ASSIGNMENT_ID}" 2>/dev/null)

    ERROR_MSG=$(echo "$ASSIGNMENT_INFO" | jq -r '.error // empty' 2>/dev/null)
    ACTIVE=$(echo "$ASSIGNMENT_INFO" | jq -r '.active // false' 2>/dev/null)

    if [ -z "$ERROR_MSG" ] && [ "$ACTIVE" = "true" ]; then
        echo -e "${RED}✗ This workspace already has an active allocation${NC}"
        echo ""
        echo "Assignment: $WORKSPACE_ASSIGNMENT_ID ($WORKSPACE_CLOUD_NAME)"
        echo ""
        echo "Please deallocate it first:"
        echo "  make deallocate"
        echo ""
        exit 1
    else
        echo -e "${YELLOW}⚠  Workspace state exists but assignment is no longer active${NC}"
        echo "Clearing stale state and proceeding with new allocation..."
        rm -f "${STATE_DIR}/current.env" "${REG_AGENT_ROOT}/vars/state.env"
    fi
fi

# Inform about external assignments (but don't block)
ACTIVE_ASSIGNMENTS=$(curl -s -k \
    -H "Authorization: Bearer ${QUADS_TOKEN}" \
    "https://${QUADS_API_SERVER}/api/v3/assignments?owner=${QUADS_USERNAME}" 2>/dev/null)

ACTIVE_COUNT=$(echo "$ACTIVE_ASSIGNMENTS" | jq '[.[] | select(.active == true)] | length' 2>/dev/null || echo "0")

if [ "$ACTIVE_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}Note: You have ${ACTIVE_COUNT} active assignment(s) not managed by this workspace:${NC}"
    echo "$ACTIVE_ASSIGNMENTS" | jq -r '.[] | select(.active == true) | "  - Assignment \(.id): \(.cloud.name) - \(.description)"' 2>/dev/null
    echo ""
fi

echo -e "${GREEN}✓ Ready to allocate${NC}"
echo ""

# Check if using existing assignment
if [ "$USE_EXISTING_ASSIGNMENT" = "true" ] && [ -n "$CLOUD_NAME" ]; then
    echo -e "${YELLOW}Using existing assignment: $CLOUD_NAME${NC}"

    # Save to SSM state directory
    cat > "${STATE_DIR}/current.env" <<EOF
CLOUD_NAME="${CLOUD_NAME}"
QUADS_METHOD="quads-ssm"
USE_EXISTING_ASSIGNMENT="true"
LAB="${QUADS_LAB}"
EOF

    # Also update main state for backward compatibility
    cp "${STATE_DIR}/current.env" "${REG_AGENT_ROOT}/vars/state.env"

    echo ""
    echo -e "${GREEN}✅ Using existing allocation: $CLOUD_NAME${NC}"
    echo "State saved to: ${STATE_DIR}/current.env"
    exit 0
fi

# Generate QUADS configuration
echo "Generating QUADS configuration..."

# Handle preferred models
if [ "$QUADS_PREFERRED_MODEL" = "all" ] || [ "$QUADS_PREFERRED_MODEL" = "any" ]; then
    PREFERRED_MODELS_YAML='"all"'
else
    # Convert comma-separated to YAML list
    PREFERRED_MODELS_YAML=$(printf '\n'; echo "$QUADS_PREFERRED_MODEL" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^/  - "/' | sed 's/$/"/')
fi

# Create quads_config.yml
cat > "${QUADS_REPO}/quads_config.yml" <<EOF
---
quads_api_server: "${QUADS_API_SERVER}"
quads_username: "${QUADS_USERNAME}"
quads_user_domain: "${QUADS_USER_DOMAIN}"
quads_password: "${QUADS_PASSWORD}"
preferred_models: ${PREFERRED_MODELS_YAML}
EOF

echo -e "${GREEN}✓ QUADS config generated${NC}"

# Determine wipe setting
if [ "$QUADS_WIPE_DISKS" = "no" ]; then
    WIPE_VALUE="false"
else
    WIPE_VALUE="true"
fi

# Run QUADS self-schedule
echo ""
echo -e "${BLUE}Requesting QUADS allocation...${NC}"
echo "  Description: $SHORT_DESCRIPTION"
echo "  Workload: $QUADS_WORKLOAD_NAME"
echo "  Hosts: $QUADS_NUM_HOSTS"
echo "  Models: $QUADS_PREFERRED_MODEL"
echo "  Lab: $QUADS_LAB"
echo "  Wipe disks: $QUADS_WIPE_DISKS"
echo ""

cd "$QUADS_REPO"

# Run ansible playbook and save output
QUADS_OUTPUT="${OUTPUT_DIR}/quads_response_${TIMESTAMP}.log"

ansible-playbook quads_self_schedule.yml \
    -e "workload_name='${SHORT_DESCRIPTION}'" \
    -e "num_hosts=${QUADS_NUM_HOSTS}" \
    -e "wipe=${WIPE_VALUE}" \
    | tee "${QUADS_OUTPUT}"

# Extract cloud name from output
echo ""
echo "Parsing QUADS output..."

CLOUD_NAME=$(sed -n 's/.*"cloud_name":[[:space:]]*"\([^"]*\)".*/\1/p' "${QUADS_OUTPUT}" | head -1 || true)

if [ -z "$CLOUD_NAME" ]; then
    CLOUD_NAME=$(sed -n 's/.*"cloud":[[:space:]]*{"name":[[:space:]]*"\([^"]*\)".*/\1/p' "${QUADS_OUTPUT}" | head -1 || true)
fi

if [ -z "$CLOUD_NAME" ]; then
    echo -e "${RED}✗ Error: Could not extract cloud_name from QUADS output${NC}"
    echo "Please check ${QUADS_OUTPUT}"
    exit 1
fi

# Extract assignment ID
ASSIGNMENT_ID=$(sed -n 's/.*"assignment_id":[[:space:]]*"\([^"]*\)".*/\1/p' "${QUADS_OUTPUT}" | head -1 || true)

if [ -z "$ASSIGNMENT_ID" ]; then
    ASSIGNMENT_ID=$(sed -n 's/.*"assignment_id":[[:space:]]*\([0-9]*\).*/\1/p' "${QUADS_OUTPUT}" | head -1 || true)
fi

# Save state to SSM directory
cat > "${STATE_DIR}/current.env" <<EOF
CLOUD_NAME="${CLOUD_NAME}"
ASSIGNMENT_ID="${ASSIGNMENT_ID}"
QUADS_METHOD="quads-ssm"
LAB="${QUADS_LAB}"
ALLOCATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
WORKLOAD_NAME="${QUADS_WORKLOAD_NAME}"
SHORT_DESCRIPTION="${SHORT_DESCRIPTION}"
NUM_HOSTS="${QUADS_NUM_HOSTS}"
WIPE_DISKS="${QUADS_WIPE_DISKS}"
EOF

# Also update main state for backward compatibility
cp "${STATE_DIR}/current.env" "${REG_AGENT_ROOT}/vars/state.env"

echo ""
echo -e "${GREEN}✓ Allocation scheduled${NC}"
echo "  Cloud: $CLOUD_NAME"
echo "  Assignment ID: $ASSIGNMENT_ID"

# Wait for validation
if [ -n "$ASSIGNMENT_ID" ]; then
    echo ""
    echo "Waiting for assignment validation..."
    echo "Note: This can take 20-30 minutes if disk wiping is enabled"
    echo "      Maximum wait time: 3 hours"

    QUADS_HOST="${QUADS_API_SERVER}"
    MAX_WAIT=10800  # 3 hours (to handle wipe=true cases and heavy load)
    ELAPSED=0
    VALIDATION_SUCCESS=false

    while [ $ELAPSED -lt $MAX_WAIT ]; do
        ASSIGNMENT_DATA=$(curl -sk "https://${QUADS_HOST}/api/v3/assignments/${ASSIGNMENT_ID}" 2>/dev/null)
        STATUS=$(echo "$ASSIGNMENT_DATA" | jq -r '.validated | tostring' 2>/dev/null || echo "null")

        if [ "$STATUS" = "true" ]; then
            echo -e "${GREEN}✅ Assignment validated and ready!${NC}"
            echo ""
            echo "Note: Foreman may need additional time to fully provision the cloud"
            echo "      (create user accounts, configure credentials, etc.)"
            echo "      Jetlag will retry automatically if Foreman is not ready yet"
            echo ""
            VALIDATION_SUCCESS=true
            break
        elif [ "$STATUS" = "null" ] || [ -z "$STATUS" ]; then
            echo -e "${RED}✗ Error: Could not check validation status${NC}"
            echo "API Response: $ASSIGNMENT_DATA"
            echo ""
            echo "This could indicate:"
            echo "  - Network connectivity issues"
            echo "  - QUADS API problems"
            echo "  - Assignment was terminated"
            echo ""
            echo "Please check manually:"
            echo "  https://${QUADS_HOST}/api/v3/assignments/${ASSIGNMENT_ID}"
            exit 1
        fi

        echo "Waiting for validation... (status: $STATUS, elapsed: ${ELAPSED}s / ${MAX_WAIT}s)"
        sleep 30
        ELAPSED=$((ELAPSED + 30))
    done

    if [ "$VALIDATION_SUCCESS" = "false" ]; then
        echo ""
        echo -e "${RED}=========================================${NC}"
        echo -e "${RED}✗ QUADS Validation Failed${NC}"
        echo -e "${RED}=========================================${NC}"
        echo ""
        echo "Assignment ${ASSIGNMENT_ID} did not validate after 2 hours"
        echo ""
        echo "Possible causes:"
        echo "  - Insufficient available hosts in the lab"
        echo "  - Hardware issues with allocated machines"
        echo "  - Disk wiping taking longer than expected"
        echo "  - QUADS backend issues"
        echo ""
        echo "Next steps:"
        echo "  1. Check assignment status manually:"
        echo "     https://${QUADS_HOST}/assignments/${ASSIGNMENT_ID}"
        echo ""
        echo "  2. Wait longer and check again:"
        echo "     make -C modules/quads validate"
        echo ""
        echo "  3. Or deallocate and try again:"
        echo "     make deallocate-quads"
        echo "     make deploy"
        echo ""
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✅ QUADS Allocation Complete${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Cloud: $CLOUD_NAME"
echo "Assignment ID: $ASSIGNMENT_ID"
echo "Lab: $QUADS_LAB"
echo ""
echo "Generated files:"
echo "  State: ${STATE_DIR}/current.env"
echo "  Log: ${LOG_FILE}"
echo "  Output: ${QUADS_OUTPUT}"
echo ""
echo "Next steps:"
echo "  Check status: make validate"
echo ""

cd "${REG_AGENT_ROOT}"
exit 0
