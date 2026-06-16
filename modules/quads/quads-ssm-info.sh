#!/bin/bash
# QUADS information query - show available resources
# Displays available hosts that can be self-scheduled

# Note: No 'set -e' here due to arithmetic operations with associative arrays

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG_AGENT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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

# Load dependency checking library
source "${REG_AGENT_ROOT}/modules/lib/check-dependencies.sh"

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}QUADS Available Resources${NC}"
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
if ! summarize_deps "QUADS Info Query"; then
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
        echo ""
        echo "Please verify QUADS credentials in: ${REG_AGENT_ROOT}/vars/config.json"
        echo "  - QUADS_PASSWORD (current password authentication)"
        echo "  - Or use QUADS_API_TOKEN (token-based authentication)"
        echo ""
        echo "To reconfigure: cd ${REG_AGENT_ROOT}/modules/quads && make init"
        echo ""
        exit 1
    fi

    echo -e "${GREEN}✓ Authenticated${NC}"
else
    QUADS_TOKEN="$QUADS_API_TOKEN"
fi

# Query available hosts for self-scheduling
echo ""
echo "Querying available hosts from QUADS API..."
echo ""

AVAILABLE_HOSTS=$(curl -s -k \
    -H "Authorization: Bearer ${QUADS_TOKEN}" \
    "https://${QUADS_API_SERVER}/api/v3/available?can_self_schedule=true" 2>/dev/null)

# Check for API errors
ERROR_MSG=$(echo "$AVAILABLE_HOSTS" | jq -r '.error // empty' 2>/dev/null)

if [ -n "$ERROR_MSG" ] || [ -z "$AVAILABLE_HOSTS" ] || [ "$AVAILABLE_HOSTS" = "null" ]; then
    echo -e "${YELLOW}⚠  Could not retrieve available hosts${NC}"
    echo "Please check your QUADS API access"
    exit 1
fi

# Parse and display results
TOTAL_AVAILABLE=$(echo "$AVAILABLE_HOSTS" | jq '. | length' 2>/dev/null || echo "0")

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Available Hosts Summary${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "Lab: ${LAB:-not configured}"
echo "QUADS Server: $QUADS_API_SERVER"
echo ""
echo -e "${GREEN}Total Available Hosts: $TOTAL_AVAILABLE${NC}"
echo ""

if [ "$TOTAL_AVAILABLE" -eq 0 ]; then
    echo -e "${YELLOW}No hosts currently available for self-scheduling${NC}"
    echo ""
    echo "This could mean:"
    echo "  - All hosts are currently allocated"
    echo "  - Try again later when hosts are released"
    echo "  - Contact lab admins if you need immediate access"
    echo ""
    exit 0
fi

# Group by model (extract from hostname)
echo -e "${BLUE}Available by Model:${NC}"
echo ""

# Extract models from hostnames and count them
declare -A MODEL_COUNTS

while IFS= read -r hostname; do
    if [ -n "$hostname" ] && [ "$hostname" != "null" ]; then
        # Extract model from hostname (e.g., "bb37-h09-000-r750.domain" -> "r750")
        MODEL=$(echo "$hostname" | sed 's/.*-\([^.]*\)\..*/\1/')
        if [ -n "$MODEL" ]; then
            MODEL_COUNTS[$MODEL]=$((${MODEL_COUNTS[$MODEL]:-0} + 1))
        fi
    fi
done < <(echo "$AVAILABLE_HOSTS" | jq -r '.[]' 2>/dev/null)

# Display model counts sorted
for model in $(echo "${!MODEL_COUNTS[@]}" | tr ' ' '\n' | sort); do
    printf "  %-20s: %s hosts\n" "$model" "${MODEL_COUNTS[$model]}"
done

# Show hosts
echo ""
if [ "$TOTAL_AVAILABLE" -le 10 ]; then
    echo -e "${BLUE}Available Hosts:${NC}"
else
    echo -e "${BLUE}Available Hosts (showing 10 of ${TOTAL_AVAILABLE}):${NC}"
fi
echo ""

SAMPLE_HOSTS=$(echo "$AVAILABLE_HOSTS" | jq -r '.[:10] | .[]' 2>/dev/null)
while IFS= read -r hostname; do
    if [ -n "$hostname" ]; then
        MODEL=$(echo "$hostname" | sed 's/.*-\([^.]*\)\..*/\1/')
        echo "  - $hostname ($MODEL)"
    fi
done <<< "$SAMPLE_HOSTS"

if [ "$TOTAL_AVAILABLE" -gt 10 ]; then
    echo ""
    echo "  ... and $((TOTAL_AVAILABLE - 10)) more hosts"
fi

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Next Steps${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "To allocate hosts:"
echo "  1. Configure: vi ${REG_AGENT_ROOT}/vars/config.json"
echo "  2. Set NUM_HOSTS (how many you need)"
echo "  3. Set PREFERRED_MODEL (or 'any' for any model)"
echo "  4. Allocate: make allocate"
echo ""

exit 0
