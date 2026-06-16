#!/bin/bash
# Deallocate QUADS assignment by CLOUD_NAME only
# Useful when you only know the cloud name (e.g., cloud04)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG_AGENT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

# Load configuration
if [ -f "${REG_AGENT_ROOT}/vars/config.json" ]; then
    # Load JSON configuration
source "${REG_AGENT_ROOT}/modules/lib/json-config.sh"
json_export_env ".quads" "QUADS"
fi

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}QUADS Deallocate by Cloud Name${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Get CLOUD_NAME from command line or prompt
if [ -n "$1" ]; then
    CLOUD_NAME="$1"
else
    read -p "Enter CLOUD_NAME (e.g., cloud04): " CLOUD_NAME
fi

if [ -z "$CLOUD_NAME" ]; then
    echo -e "${RED}ERROR: CLOUD_NAME required${NC}"
    exit 1
fi

# Check authentication
if [ -z "$QUADS_API_SERVER" ]; then
    echo -e "${RED}ERROR: QUADS_API_SERVER not configured${NC}"
    echo "Run: make -C modules/quads init"
    exit 1
fi

if [ -z "$QUADS_USERNAME" ]; then
    echo -e "${RED}ERROR: QUADS_USERNAME not configured${NC}"
    echo "Run: make -C modules/quads init"
    exit 1
fi

# Check for authentication method
if [ -n "$QUADS_API_TOKEN" ]; then
    USE_API_TOKEN=true
    QUADS_TOKEN="$QUADS_API_TOKEN"
    echo -e "${GREEN}✓ Using API token authentication${NC}"
elif [ -n "$QUADS_PASSWORD" ]; then
    USE_API_TOKEN=false
    # Get token via password
    QUADS_USER_DOMAIN=${QUADS_USER_DOMAIN:-"redhat.com"}
    QUADS_USER_EMAIL="${QUADS_USERNAME}@${QUADS_USER_DOMAIN}"

    echo "Authenticating with QUADS API..."
    echo "  User: ${QUADS_USER_EMAIL}"
    echo "  Server: https://${QUADS_API_SERVER}"
    echo ""

    LOGIN_RESPONSE=$(curl -sk -X POST \
        -u "${QUADS_USER_EMAIL}:${QUADS_PASSWORD}" \
        "https://${QUADS_API_SERVER}/api/v3/login/" 2>&1)

    # Check if response is valid JSON
    if ! echo "$LOGIN_RESPONSE" | jq . > /dev/null 2>&1; then
        echo -e "${RED}ERROR: Invalid response from QUADS API${NC}"
        echo ""
        echo "Response:"
        echo "$LOGIN_RESPONSE"
        echo ""
        echo "Possible issues:"
        echo "  1. Wrong QUADS_API_SERVER: ${QUADS_API_SERVER}"
        echo "  2. Server unreachable or SSL certificate issue"
        echo "  3. API endpoint changed"
        exit 1
    fi

    QUADS_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.auth_token // empty')

    if [ -z "$QUADS_TOKEN" ]; then
        echo -e "${RED}ERROR: Authentication failed${NC}"
        echo ""
        echo "Response:"
        echo "$LOGIN_RESPONSE" | jq .
        echo ""
        echo "Possible issues:"
        echo "  1. Wrong username: ${QUADS_USER_EMAIL}"
        echo "  2. Wrong password"
        echo "  3. Account disabled or insufficient permissions"
        exit 1
    fi

    echo -e "${GREEN}✓ Authentication successful${NC}"
else
    echo -e "${RED}ERROR: No authentication configured${NC}"
    echo "Set either QUADS_API_TOKEN or QUADS_PASSWORD in vars/config.json (.quads section)"
    exit 1
fi

echo ""
echo -e "${BLUE}Looking up assignment for: ${CLOUD_NAME}${NC}"
echo ""

# Query QUADS API to find active assignment for this cloud
ASSIGNMENTS_JSON=$(curl -sk -X GET "https://${QUADS_API_SERVER}/api/v3/assignments" \
    -H "Authorization: Bearer ${QUADS_TOKEN}" \
    -H "Content-Type: application/json")

# Find active assignment for this cloud
ASSIGNMENT_ID=$(echo "$ASSIGNMENTS_JSON" | jq -r \
    ".[] | select(.cloud.name == \"${CLOUD_NAME}\" and .active == true) | .id" | head -1)

if [ -z "$ASSIGNMENT_ID" ]; then
    echo -e "${YELLOW}No active assignment found for ${CLOUD_NAME}${NC}"
    echo ""
    echo "Possible reasons:"
    echo "  1. Cloud name is incorrect"
    echo "  2. Assignment already terminated"
    echo "  3. Cloud is not currently assigned to you"
    echo ""

    # Show all active assignments for this user
    echo "Your active assignments:"
    echo "$ASSIGNMENTS_JSON" | jq -r \
        '.[] | select(.active == true) | "  - " + .cloud.name + " (ID: " + (.id|tostring) + ")"'

    exit 1
fi

# Get assignment details
ASSIGNMENT_DETAILS=$(echo "$ASSIGNMENTS_JSON" | jq \
    ".[] | select(.id == ${ASSIGNMENT_ID})")

# Extract details
OWNER=$(echo "$ASSIGNMENT_DETAILS" | jq -r '.owner')
DESCRIPTION=$(echo "$ASSIGNMENT_DETAILS" | jq -r '.description // "N/A"')
VALIDATED=$(echo "$ASSIGNMENT_DETAILS" | jq -r '.validated')

echo -e "${GREEN}Found active assignment:${NC}"
echo "  Assignment ID: $ASSIGNMENT_ID"
echo "  Cloud Name: $CLOUD_NAME"
echo "  Owner: $OWNER"
echo "  Description: $DESCRIPTION"
echo "  Validated: $VALIDATED"
echo ""

# Confirm deallocation
echo -e "${YELLOW}WARNING: This will terminate the assignment and release the hosts.${NC}"
echo -e "${YELLOW}This action cannot be undone.${NC}"
echo ""
read -p "Deallocate $CLOUD_NAME? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cancelled"
    exit 0
fi

echo ""
echo "Terminating assignment $ASSIGNMENT_ID..."

# Terminate the assignment
TERMINATE_RESPONSE=$(curl -sk -X POST \
    -H "Authorization: Bearer ${QUADS_TOKEN}" \
    "https://${QUADS_API_SERVER}/api/v3/assignments/terminate/${ASSIGNMENT_ID}")

# Check if termination was successful
TERMINATE_STATUS=$(echo "$TERMINATE_RESPONSE" | jq -r '.status // .message // empty' 2>/dev/null)

if [ -n "$TERMINATE_STATUS" ]; then
    echo ""
    echo -e "${GREEN}✓ Assignment terminated${NC}"
    echo "  Response: $TERMINATE_STATUS"
    echo ""
    echo "Details:"
    echo "  Cloud: $CLOUD_NAME"
    echo "  Assignment ID: $ASSIGNMENT_ID"
    echo ""
    echo "The hosts have been returned to the pool."
else
    # Check if we got an error
    ERROR_MSG=$(echo "$TERMINATE_RESPONSE" | jq -r '.error // .detail // empty' 2>/dev/null)
    if [ -n "$ERROR_MSG" ]; then
        echo ""
        echo -e "${RED}✗ Termination failed${NC}"
        echo "  Error: $ERROR_MSG"
        exit 1
    else
        # Assume success if no error
        echo ""
        echo -e "${GREEN}✓ Assignment termination requested${NC}"
        echo ""
        echo "Details:"
        echo "  Cloud: $CLOUD_NAME"
        echo "  Assignment ID: $ASSIGNMENT_ID"
        echo ""
        echo "The hosts have been returned to the pool."
    fi
fi

echo ""
