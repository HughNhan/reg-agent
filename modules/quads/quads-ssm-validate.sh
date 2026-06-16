#!/bin/bash
# QUADS assignment validation using ansible-quads-ssm API
# Checks if current allocation is still valid and active

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
LOG_FILE="${LOG_DIR}/validate_${TIMESTAMP}.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Load configuration
if [ -f "${REG_AGENT_ROOT}/vars/config.json" ]; then
    # Load JSON configuration
source "${REG_AGENT_ROOT}/modules/lib/json-config.sh"
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
echo -e "${BLUE}QUADS SSM Assignment Validation${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Check dependencies
echo "Checking dependencies..."
echo ""
reset_dep_check

# Required configuration variables
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
    echo "   Set either QUADS_API_TOKEN or QUADS_PASSWORD in vars/config.json"
    exit 1
fi

# Required commands
check_command "JSON parser" "jq"
check_command "curl" "curl"

# Summarize and fail if dependencies not met
if ! summarize_deps "QUADS Validation"; then
    exit 1
fi

# Set defaults
QUADS_USER_DOMAIN=${QUADS_USER_DOMAIN:-"redhat.com"}
QUADS_USER_EMAIL="${QUADS_USERNAME}@${QUADS_USER_DOMAIN}"

# Get authentication token if using password
if [ "$USE_API_TOKEN" = "false" ]; then
    echo ""
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
fi

# Check if we have state from this workspace
if [ -z "$ASSIGNMENT_ID" ]; then
    echo ""
    echo -e "${BLUE}No active allocation from this workspace${NC}"
    echo ""
    echo "No state file found. This workspace has not created any allocations."
    echo ""
    echo "Next step:"
    echo "  make allocate"
    echo ""
    exit 0
fi

# Query assignment details
echo ""
echo "Querying assignment status..."

ASSIGNMENT_INFO=$(curl -s -k \
    -H "Authorization: Bearer ${QUADS_TOKEN}" \
    "https://${QUADS_API_SERVER}/api/v3/assignments/${ASSIGNMENT_ID}" 2>/dev/null)

# Check if assignment exists (API returns error field if not found)
ERROR_MSG=$(echo "$ASSIGNMENT_INFO" | jq -r '.error // empty' 2>/dev/null)

if [ -n "$ERROR_MSG" ] || [ -z "$ASSIGNMENT_INFO" ] || [ "$ASSIGNMENT_INFO" = "null" ]; then
    echo -e "${YELLOW}Old allocation has expired${NC}"
    echo ""
    echo "Assignment ID ${ASSIGNMENT_ID} (${CLOUD_NAME}) no longer exists in QUADS."
    echo "The allocation has likely expired or been terminated."
    echo ""
    echo "Next steps:"
    echo "  rm ${STATE_DIR}/current.env"
    echo "  make allocate"
    echo ""
    exit 0
fi

# Parse assignment details
VALIDATED=$(echo "$ASSIGNMENT_INFO" | jq -r '.validated // false' 2>/dev/null)
DESCRIPTION=$(echo "$ASSIGNMENT_INFO" | jq -r '.description // "none"' 2>/dev/null)
OWNER=$(echo "$ASSIGNMENT_INFO" | jq -r '.owner // "unknown"' 2>/dev/null)
CLOUD_NAME_API=$(echo "$ASSIGNMENT_INFO" | jq -r '.cloud.name // "unknown"' 2>/dev/null)
TICKET=$(echo "$ASSIGNMENT_INFO" | jq -r '.ticket // "none"' 2>/dev/null)
ACTIVE=$(echo "$ASSIGNMENT_INFO" | jq -r '.active // false' 2>/dev/null)
WIPE=$(echo "$ASSIGNMENT_INFO" | jq -r '.wipe // "unknown"' 2>/dev/null)
QINQ=$(echo "$ASSIGNMENT_INFO" | jq -r '.qinq // "0"' 2>/dev/null)

# Query hosts in this assignment
echo "Querying assigned hosts..."

HOSTS_INFO=$(curl -s -k \
    -H "Authorization: Bearer ${QUADS_TOKEN}" \
    "https://${QUADS_API_SERVER}/api/v3/hosts?cloud=${CLOUD_NAME_API}" 2>/dev/null)

HOST_COUNT=$(echo "$HOSTS_INFO" | jq '. | length' 2>/dev/null || echo "0")
HOST_NAMES=$(echo "$HOSTS_INFO" | jq -r '.[].name // empty' 2>/dev/null | tr '\n' ',' | sed 's/,$//')

# Save assignment details to output directory
ASSIGNMENT_DETAILS_FILE="${OUTPUT_DIR}/assignment_details_${TIMESTAMP}.json"
echo "$ASSIGNMENT_INFO" | jq '.' > "${ASSIGNMENT_DETAILS_FILE}" 2>/dev/null || echo "$ASSIGNMENT_INFO" > "${ASSIGNMENT_DETAILS_FILE}"

# Save hosts info
HOSTS_FILE="${OUTPUT_DIR}/hosts_${TIMESTAMP}.json"
echo "$HOSTS_INFO" | jq '.' > "${HOSTS_FILE}" 2>/dev/null || echo "$HOSTS_INFO" > "${HOSTS_FILE}"

# Display results
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Assignment Details${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "Assignment Information:"
echo "  Assignment ID: $ASSIGNMENT_ID"
echo "  Cloud Name: $CLOUD_NAME_API"
echo "  Description: $DESCRIPTION"
echo "  Owner: $OWNER"
echo "  Ticket: $TICKET"
echo ""
echo "Status:"
if [ "$VALIDATED" = "true" ]; then
    echo -e "  Validated: ${GREEN}✓ Yes${NC}"
else
    echo -e "  Validated: ${YELLOW}⚠ No (pending validation)${NC}"
fi

if [ "$ACTIVE" = "true" ]; then
    echo -e "  Active: ${GREEN}✓ Yes${NC}"
else
    echo -e "  Active: ${RED}✗ No (expired or terminated)${NC}"
fi

echo ""
echo "Configuration:"
echo "  Wipe Disks: $WIPE"
echo "  QINQ VLAN: $QINQ"
echo "  Lab: ${LAB:-unknown}"
echo ""
echo "Hosts (${HOST_COUNT}):"
if [ "$HOST_COUNT" -gt 0 ]; then
    echo "$HOSTS_INFO" | jq -r '.[] | "  - \(.name) (\(.model // "unknown"))"' 2>/dev/null || echo "  $HOST_NAMES"
else
    echo "  No hosts assigned yet"
fi
echo ""

# Verify cloud name matches
if [ "$CLOUD_NAME" != "$CLOUD_NAME_API" ]; then
    echo -e "${YELLOW}⚠  Warning: Cloud name mismatch${NC}"
    echo "  Local state: $CLOUD_NAME"
    echo "  API reports: $CLOUD_NAME_API"
    echo ""
fi

# Overall status
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Overall Status${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

if [ "$ACTIVE" = "true" ] && [ "$VALIDATED" = "true" ] && [ "$HOST_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✅ Assignment is VALID and READY${NC}"
    echo ""
    echo "Your cluster is active, validated, and has ${HOST_COUNT} host(s) assigned."
    echo "You can proceed with deployment."
    EXIT_CODE=0
elif [ "$ACTIVE" = "true" ] && [ "$VALIDATED" = "false" ]; then
    echo -e "${YELLOW}⚠  Assignment is ACTIVE but NOT VALIDATED${NC}"
    echo ""
    echo "Your cluster is active but pending validation."
    echo "Wait a few minutes and check again with: make validate"
    EXIT_CODE=2
elif [ "$ACTIVE" = "false" ]; then
    echo -e "${RED}✗ Assignment is INACTIVE${NC}"
    echo ""
    echo "Your assignment has expired or been terminated."
    echo "You need to allocate a new cluster with: make allocate"
    EXIT_CODE=1
else
    echo -e "${YELLOW}⚠  Assignment status is UNCERTAIN${NC}"
    echo ""
    echo "Active: $ACTIVE"
    echo "Validated: $VALIDATED"
    echo "Hosts: $HOST_COUNT"
    EXIT_CODE=2
fi

echo ""
echo "Generated files:"
echo "  Assignment details: ${ASSIGNMENT_DETAILS_FILE}"
echo "  Hosts list: ${HOSTS_FILE}"
echo "  Log: ${LOG_FILE}"
echo ""
echo "Helper Commands:"
echo "  Check status: curl -s https://${QUADS_API_SERVER}/api/v3/assignments/${ASSIGNMENT_ID} | jq"
echo "  Terminate: make deallocate"
echo ""

exit $EXIT_CODE
