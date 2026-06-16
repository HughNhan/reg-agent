#!/bin/bash
# QUADS deallocation using ansible-quads-ssm API
# Terminates an existing QUADS assignment

set -e

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
LOG_FILE="${LOG_DIR}/deallocate_${TIMESTAMP}.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Load configuration from JSON
if [ -f "${REG_AGENT_ROOT}/vars/config.json" ]; then
    source "${REG_AGENT_ROOT}/modules/lib/json-config.sh"
    export REG_AGENT_ROOT
    json_export_env ".quads" "QUADS"
fi

# Load state from SSM directory (primary) or main vars (fallback)
if [ -f "${STATE_DIR}/current.env" ]; then
    source "${STATE_DIR}/current.env"
elif [ -f "${REG_AGENT_ROOT}/vars/state.env" ]; then
    source "${REG_AGENT_ROOT}/vars/state.env"
fi

# Load dependency checking library
source "${REG_AGENT_ROOT}/modules/lib/check-dependencies.sh"

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}QUADS SSM Deallocation${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Check dependencies
echo "Checking dependencies..."
echo ""
reset_dep_check

# Check if we have state to clean
HAS_STATE=false
if [ -f "${STATE_DIR}/current.env" ] || [ -f "${REG_AGENT_ROOT}/vars/state.env" ]; then
    HAS_STATE=true
fi

# Check for credentials
HAS_CREDENTIALS=false
if [ -n "$QUADS_API_SERVER" ] && [ -n "$QUADS_USERNAME" ]; then
    HAS_CREDENTIALS=true
fi

# If no state and no credentials, nothing to do
if [ "$HAS_STATE" = "false" ]; then
    echo -e "${YELLOW}No QUADS state found${NC}"
    echo "Nothing to deallocate"
    exit 0
fi

# If we have state but no credentials, offer state-only cleanup
if [ "$HAS_CREDENTIALS" = "false" ]; then
    echo -e "${YELLOW}⚠  QUADS credentials not found in vars/config.json${NC}"
    echo ""
    echo "Cannot terminate assignment in QUADS API without credentials."
    echo "However, local state can still be cleaned up."
    echo ""

    if [ -f "${STATE_DIR}/current.env" ]; then
        echo "Current state:"
        cat "${STATE_DIR}/current.env"
        echo ""
    fi

    echo "Options:"
    echo "  1) Clean local state only (assignment remains in QUADS)"
    echo "  2) Cancel (restore credentials and retry)"
    echo ""
    read -p "Choice [1-2]: " cleanup_choice

    if [ "$cleanup_choice" = "1" ]; then
        echo ""
        echo -e "${YELLOW}Cleaning local state only...${NC}"
        rm -f "${STATE_DIR}/current.env"
        rm -f "${REG_AGENT_ROOT}/vars/state.env"
        echo -e "${GREEN}✓ Local state cleaned${NC}"
        echo ""
        echo -e "${RED}WARNING: Assignment may still be active in QUADS!${NC}"
        echo "To fully deallocate:"
        echo "  1. Restore credentials: make configure"
        echo "  2. Run: make deallocate-by-cloud CLOUD_NAME=${CLOUD_NAME:-cloudXX}"
        echo ""
        exit 0
    else
        echo "Cancelled. Restore credentials in vars/config.json and retry."
        exit 1
    fi
fi

# Required configuration variables (only if we have credentials)
check_var "QUADS API server" "QUADS_API_SERVER"
check_var "QUADS username" "QUADS_USERNAME"

# Check for authentication method
if [ -n "$QUADS_API_TOKEN" ]; then
    USE_API_TOKEN=true
    echo -e "${GREEN}✓${NC} Using API token authentication"
elif [ -n "$QUADS_PASSWORD" ]; then
    USE_API_TOKEN=false
    echo -e "${GREEN}✓${NC} Using password authentication"
else
    echo -e "${RED}✗${NC} No authentication configured"
    echo "   Set either QUADS_API_TOKEN or QUADS_PASSWORD in vars/config.json (.quads section)"
    exit 1
fi

# Required state variables
check_var "Assignment ID" "ASSIGNMENT_ID"
check_var "Cloud name" "CLOUD_NAME"

# Required commands
check_command "JSON parser" "jq"
check_command "curl" "curl"

# Summarize and fail if dependencies not met
if ! summarize_deps "QUADS Deallocation"; then
    exit 1
fi

# Set defaults
QUADS_USER_DOMAIN=${QUADS_USER_DOMAIN:-"redhat.com"}
QUADS_USER_EMAIL="${QUADS_USERNAME}@${QUADS_USER_DOMAIN}"

echo ""
echo -e "${BLUE}Current Assignment Details:${NC}"
echo "  Assignment ID: $ASSIGNMENT_ID"
echo "  Cloud Name: $CLOUD_NAME"
echo "  Lab: ${LAB:-unknown}"
echo ""

# Get authentication token if using password
if [ "$USE_API_TOKEN" = "false" ]; then
    echo "Authenticating with QUADS API..."

    LOGIN_RESPONSE=$(curl -s -k -X POST \
        -u "${QUADS_USER_EMAIL}:${QUADS_PASSWORD}" \
        "https://${QUADS_API_SERVER}/api/v3/login/" 2>/dev/null)

    QUADS_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.auth_token // empty' 2>/dev/null)

    if [ -z "$QUADS_TOKEN" ]; then
        echo -e "${RED}✗ Authentication failed${NC}"
        echo "Please check your QUADS username and password"
        exit 1
    fi

    echo -e "${GREEN}✓ Authenticated${NC}"
else
    QUADS_TOKEN="$QUADS_API_TOKEN"
    echo -e "${GREEN}✓ Using API token${NC}"
fi

# Check assignment status before terminating
echo ""
echo "Checking assignment status..."

ASSIGNMENT_INFO=$(curl -s -k \
    -H "Authorization: Bearer ${QUADS_TOKEN}" \
    "https://${QUADS_API_SERVER}/api/v3/assignments/${ASSIGNMENT_ID}" 2>/dev/null)

if [ -z "$ASSIGNMENT_INFO" ] || [ "$ASSIGNMENT_INFO" = "null" ]; then
    echo -e "${YELLOW}⚠  Could not retrieve assignment info${NC}"
    echo "Assignment may have already been terminated or does not exist"
    echo ""
    read -p "Do you want to clear the local state anyway? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "${STATE_DIR}/current.env"
        rm -f "${REG_AGENT_ROOT}/vars/state.env"
        echo -e "${GREEN}✓ Local state cleared${NC}"
    fi
    exit 0
fi

# Extract and display assignment details
VALIDATED=$(echo "$ASSIGNMENT_INFO" | jq -r '.validated // "unknown"' 2>/dev/null)
DESCRIPTION=$(echo "$ASSIGNMENT_INFO" | jq -r '.description // "none"' 2>/dev/null)
OWNER=$(echo "$ASSIGNMENT_INFO" | jq -r '.owner // "unknown"' 2>/dev/null)

echo ""
echo -e "${BLUE}Assignment Information:${NC}"
echo "  Description: $DESCRIPTION"
echo "  Owner: $OWNER"
echo "  Validated: $VALIDATED"
echo "  Cloud: $CLOUD_NAME"
echo ""

# Confirm deallocation
read -p "Are you sure you want to terminate this assignment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deallocation cancelled"
    exit 0
fi

# Terminate assignment
echo ""
echo "Terminating assignment..."

TERMINATE_RESPONSE=$(curl -s -k -X POST \
    -H "Authorization: Bearer ${QUADS_TOKEN}" \
    "https://${QUADS_API_SERVER}/api/v3/assignments/terminate/${ASSIGNMENT_ID}" 2>/dev/null)

# Check if termination was successful
TERMINATE_STATUS=$(echo "$TERMINATE_RESPONSE" | jq -r '.status // .message // empty' 2>/dev/null)

if [ -n "$TERMINATE_STATUS" ]; then
    echo -e "${GREEN}✓ Assignment terminated${NC}"
    echo "  Response: $TERMINATE_STATUS"
else
    # Check if we got an error
    ERROR_MSG=$(echo "$TERMINATE_RESPONSE" | jq -r '.error // .detail // empty' 2>/dev/null)
    if [ -n "$ERROR_MSG" ]; then
        echo -e "${RED}✗ Termination failed${NC}"
        echo "  Error: $ERROR_MSG"
        exit 1
    else
        # Assume success if no error
        echo -e "${GREEN}✓ Assignment termination requested${NC}"
    fi
fi

# Save termination response
TERMINATE_RESPONSE_FILE="${OUTPUT_DIR}/terminate_response_${TIMESTAMP}.json"
echo "$TERMINATE_RESPONSE" | jq '.' > "${TERMINATE_RESPONSE_FILE}" 2>/dev/null || echo "$TERMINATE_RESPONSE" > "${TERMINATE_RESPONSE_FILE}"

# Clear state
echo ""
echo "Clearing local state..."
rm -f "${STATE_DIR}/current.env"
rm -f "${REG_AGENT_ROOT}/vars/state.env"
echo -e "${GREEN}✓ State cleared${NC}"

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✅ QUADS Deallocation Complete${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Assignment ${ASSIGNMENT_ID} (${CLOUD_NAME}) has been terminated"
echo ""
echo "Generated files:"
echo "  Termination response: ${TERMINATE_RESPONSE_FILE}"
echo "  Log: ${LOG_FILE}"
echo ""
echo "You can now allocate a new assignment with: make allocate"
echo ""

exit 0
