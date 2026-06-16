#!/bin/bash
# Import existing QUADS allocation
# For use when allocation already exists and was not created by reg-agent

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Generated directories
STATE_DIR="${SCRIPT_DIR}/generated/state"
LOG_DIR="${SCRIPT_DIR}/generated/logs"
mkdir -p "${STATE_DIR}" "${LOG_DIR}"

# Timestamped log
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/import_${TIMESTAMP}.log"
STATE_FILE="${STATE_DIR}/current.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "$@" >> "$LOG_FILE"
}

log ""
log "${BLUE}=========================================${NC}"
log "${BLUE}Import Existing QUADS Allocation${NC}"
log "${BLUE}=========================================${NC}"
log ""
log "Log file: $LOG_FILE"
log ""

#------------------------------------------------------------------------------
# Load Dependencies
#------------------------------------------------------------------------------

# Load dependency checking library
source "${ROOT_DIR}/modules/lib/check-dependencies.sh"

#------------------------------------------------------------------------------
# Input Resolution
#------------------------------------------------------------------------------

# Set REG_AGENT_ROOT BEFORE loading JSON config (json-config.sh needs it)
export REG_AGENT_ROOT="$ROOT_DIR"

# Load JSON config early to get QUADS_* variables
source "$ROOT_DIR/modules/lib/json-config.sh"
json_export_env ".quads" "QUADS"

# Priority 1: Command-line arguments (make import CLOUD_NAME=...)
# Note: LAB can come as command-line arg OR as QUADS_LAB from JSON
if [[ -n "$CLOUD_NAME" ]] && [[ -n "$LAB" ]]; then
    log "Using allocation details from command-line arguments"

# Priority 2: Interactive configuration file
elif [[ -f "$SCRIPT_DIR/generated/config/import.env" ]]; then
    log "Loading allocation details from import configuration..."
    source "$SCRIPT_DIR/generated/config/import.env"
fi

# If CLOUD_NAME not set from command-line or import.env, use QUADS_CLOUD_NAME from JSON
if [ -z "$CLOUD_NAME" ] && [ -n "$QUADS_CLOUD_NAME" ]; then
    CLOUD_NAME="$QUADS_CLOUD_NAME"
    log "Using CLOUD_NAME from config.json: $CLOUD_NAME"
fi

# If LAB not set from command-line or import.env, use QUADS_LAB from JSON
if [ -z "$LAB" ] && [ -n "$QUADS_LAB" ]; then
    LAB="$QUADS_LAB"
    log "Using LAB from config.json: $LAB"
fi

# Final fallback check
if [[ -z "$CLOUD_NAME" ]] || [[ -z "$LAB" ]]; then
    log "${RED}ERROR: Missing allocation details for import${NC}"
    log ""
    log "Provide via:"
    log "  1. Command line:"
    log "     make -C modules/quads import CLOUD_NAME=cloud23 LAB=scalelab"
    log ""
    log "  2. Interactive setup:"
    log "     make -C modules/quads init"
    log "     # Choose option 3: Import existing allocation"
    log "     make -C modules/quads import"
    log ""
    log "  3. Edit vars/config.json and set .quads.lab"
    log ""
    exit 1
fi

# Set defaults
QUADS_USER_DOMAIN=${QUADS_USER_DOMAIN:-"redhat.com"}

# Check dependencies
log "Checking dependencies..."
log ""
reset_dep_check

check_var "QUADS API server" "QUADS_API_SERVER"
check_var "QUADS username" "QUADS_USERNAME"

# Either password or token required
if [ -z "$QUADS_API_TOKEN" ] && [ -z "$QUADS_PASSWORD" ]; then
    echo -e "${RED}✗ QUADS_API_TOKEN or QUADS_PASSWORD required${NC}"
    echo "  Set in: vars/config.json"
    increment_failed_deps
fi

check_command "JSON parser" "jq"
check_command "curl" "curl"

# Summarize and fail if dependencies not met
if ! summarize_deps "QUADS Import"; then
    exit 1
fi

log ""
log "Allocation details to import:"
log "  CLOUD_NAME: ${CLOUD_NAME}"
log "  LAB:        ${LAB}"
log ""

#------------------------------------------------------------------------------
# Authenticate with QUADS API
#------------------------------------------------------------------------------

log "${BLUE}Authenticating with QUADS API...${NC}"

QUADS_USER_EMAIL="${QUADS_USERNAME}@${QUADS_USER_DOMAIN}"

# Get authentication token
if [ -n "$QUADS_API_TOKEN" ]; then
    QUADS_TOKEN="$QUADS_API_TOKEN"
    log "${GREEN}✓ Using API token from config${NC}"
else
    LOGIN_RESPONSE=$(curl -s -k -X POST \
        -u "${QUADS_USER_EMAIL}:${QUADS_PASSWORD}" \
        "https://${QUADS_API_SERVER}/api/v3/login/" 2>/dev/null)

    QUADS_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.auth_token // empty' 2>/dev/null)

    if [ -z "$QUADS_TOKEN" ]; then
        log "${RED}✗ Authentication failed${NC}"
        log "Please check your QUADS username and password in vars/config.json"
        exit 1
    fi
    log "${GREEN}✓ Authenticated with QUADS API${NC}"
fi

#------------------------------------------------------------------------------
# Find Active Assignment for Cloud Name
#------------------------------------------------------------------------------

log ""
log "${BLUE}Finding active assignment for ${CLOUD_NAME}...${NC}"

# Query assignments for this cloud
ASSIGNMENTS=$(curl -s -k \
    -H "Authorization: Bearer ${QUADS_TOKEN}" \
    "https://${QUADS_API_SERVER}/api/v3/assignments?cloud=${CLOUD_NAME}" 2>/dev/null)

if [ -z "$ASSIGNMENTS" ]; then
    log "${RED}✗ Failed to query assignments${NC}"
    log "API endpoint: https://${QUADS_API_SERVER}/api/v3/assignments?cloud=${CLOUD_NAME}"
    exit 1
fi

# Find active assignment
ASSIGNMENT_ID=$(echo "$ASSIGNMENTS" | jq -r '[.[] | select(.active == true)] | .[0].id // empty' 2>/dev/null || echo "")

if [ -z "$ASSIGNMENT_ID" ]; then
    log "${RED}✗ No active assignment found for ${CLOUD_NAME}${NC}"
    log ""
    log "This cloud may not have an active allocation."
    log ""
    log "To see your active assignments, run:"
    log "  curl -s -k -H \"Authorization: Bearer \$QUADS_TOKEN\" \\"
    log "    \"https://${QUADS_API_SERVER}/api/v3/assignments?owner=${QUADS_USERNAME}\" | jq"
    exit 1
fi

log "${GREEN}✓ Found active assignment: ${ASSIGNMENT_ID}${NC}"

#------------------------------------------------------------------------------
# Get Assignment Details
#------------------------------------------------------------------------------

log ""
log "${BLUE}Retrieving assignment details...${NC}"

ASSIGNMENT_INFO=$(curl -s -k \
    -H "Authorization: Bearer ${QUADS_TOKEN}" \
    "https://${QUADS_API_SERVER}/api/v3/assignments/${ASSIGNMENT_ID}" 2>/dev/null)

# Extract details
ASSIGNMENT_OWNER=$(echo "$ASSIGNMENT_INFO" | jq -r '.owner // "unknown"' 2>/dev/null)
ASSIGNMENT_DESC=$(echo "$ASSIGNMENT_INFO" | jq -r '.description // "No description"' 2>/dev/null)
ASSIGNMENT_VALIDATED=$(echo "$ASSIGNMENT_INFO" | jq -r '.validated // false' 2>/dev/null)
ASSIGNMENT_ACTIVE=$(echo "$ASSIGNMENT_INFO" | jq -r '.active // false' 2>/dev/null)
WIPE=$(echo "$ASSIGNMENT_INFO" | jq -r '.wipe // false' 2>/dev/null)

# Convert boolean to yes/no for consistency
if [ "$WIPE" = "true" ]; then
    WIPE_DISKS="yes"
else
    WIPE_DISKS="no"
fi

# Get host count
HOST_COUNT=$(curl -s -k \
    -H "Authorization: Bearer ${QUADS_TOKEN}" \
    "https://${QUADS_API_SERVER}/api/v3/hosts?cloud=${CLOUD_NAME}" 2>/dev/null | jq 'length' 2>/dev/null || echo "0")

log ""
log "Assignment details:"
log "  ID:          ${ASSIGNMENT_ID}"
log "  Owner:       ${ASSIGNMENT_OWNER}"
log "  Description: ${ASSIGNMENT_DESC}"
log "  Active:      ${ASSIGNMENT_ACTIVE}"
log "  Validated:   ${ASSIGNMENT_VALIDATED}"
log "  Hosts:       ${HOST_COUNT}"
log "  Wipe disks:  ${WIPE_DISKS}"
log ""

#------------------------------------------------------------------------------
# Verify Assignment Status
#------------------------------------------------------------------------------

if [ "$ASSIGNMENT_ACTIVE" != "true" ]; then
    log "${RED}✗ Assignment is not active${NC}"
    log ""
    log "This assignment may have expired or been terminated."
    exit 1
fi

if [ "$ASSIGNMENT_VALIDATED" != "true" ]; then
    log "${YELLOW}⚠  Warning: Assignment not yet validated${NC}"
    log "The allocation may still be provisioning."
    log ""
fi

#------------------------------------------------------------------------------
# Check for Workspace Conflicts
#------------------------------------------------------------------------------

log "${BLUE}Checking workspace status...${NC}"

WORKSPACE_ASSIGNMENT_ID=""
if [ -f "${STATE_DIR}/current.env" ]; then
    source "${STATE_DIR}/current.env"
    WORKSPACE_ASSIGNMENT_ID="$ASSIGNMENT_ID"
elif [ -f "${ROOT_DIR}/vars/state.env" ]; then
    source "${ROOT_DIR}/vars/state.env"
    WORKSPACE_ASSIGNMENT_ID="$ASSIGNMENT_ID"
fi

if [ -n "$WORKSPACE_ASSIGNMENT_ID" ] && [ "$WORKSPACE_ASSIGNMENT_ID" != "$ASSIGNMENT_ID" ]; then
    log "${YELLOW}⚠  Warning: Workspace already has a different allocation${NC}"
    log "Existing: Assignment ${WORKSPACE_ASSIGNMENT_ID}"
    log "Importing: Assignment ${ASSIGNMENT_ID}"
    log ""
    log "This will replace the existing workspace allocation."
    log ""

    read -p "Continue? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log "Import cancelled"
        exit 0
    fi
    log ""
fi

#------------------------------------------------------------------------------
# Save to State
#------------------------------------------------------------------------------

log "${BLUE}Saving allocation state...${NC}"

# Create module state
cat > "$STATE_FILE" << EOF
# Imported QUADS allocation
# Imported: $(date)

CLOUD_NAME="${CLOUD_NAME}"
ASSIGNMENT_ID="${ASSIGNMENT_ID}"
QUADS_METHOD="quads-ssm"
LAB="${LAB}"

# Import metadata
DEPLOYMENT_METHOD="imported"
QUADS_IMPORT_COMPLETED="true"
QUADS_IMPORT_TIMESTAMP="$(date -u +%Y%m%d_%H%M%S)"
ASSIGNMENT_OWNER="${ASSIGNMENT_OWNER}"
ASSIGNMENT_DESC="${ASSIGNMENT_DESC}"
NUM_HOSTS="${HOST_COUNT}"
WIPE_DISKS="${WIPE_DISKS}"
EOF

log "${GREEN}✓ State saved: ${STATE_FILE}${NC}"

# Sync to global state (create or update)
log "Syncing to global state..."

# If global state doesn't exist, create it
if [ ! -f "${ROOT_DIR}/vars/state.env" ]; then
    cat > "${ROOT_DIR}/vars/state.env" << EOF
# Phase 1: QUADS Import (added $(date))
CLOUD_NAME="${CLOUD_NAME}"
ASSIGNMENT_ID="${ASSIGNMENT_ID}"
QUADS_METHOD="quads-ssm"
LAB="${LAB}"
DEPLOYMENT_METHOD="imported"
QUADS_IMPORT_COMPLETED="true"
QUADS_IMPORT_TIMESTAMP="$(date -u +%Y%m%d_%H%M%S)"
EOF
else
    # Append to existing state
    cat >> "${ROOT_DIR}/vars/state.env" << EOF

# Phase 1: QUADS Import (added $(date))
CLOUD_NAME="${CLOUD_NAME}"
ASSIGNMENT_ID="${ASSIGNMENT_ID}"
QUADS_METHOD="quads-ssm"
LAB="${LAB}"
DEPLOYMENT_METHOD="imported"
QUADS_IMPORT_COMPLETED="true"
QUADS_IMPORT_TIMESTAMP="$(date -u +%Y%m%d_%H%M%S)"
EOF
fi

log "${GREEN}✓ State synced to ${ROOT_DIR}/vars/state.env${NC}"

#------------------------------------------------------------------------------
# Success Summary
#------------------------------------------------------------------------------

log ""
log "${GREEN}=========================================${NC}"
log "${GREEN}QUADS Allocation Import Complete!${NC}"
log "${GREEN}=========================================${NC}"
log ""
log "Imported allocation:"
log "  Cloud:       ${CLOUD_NAME}"
log "  Assignment:  ${ASSIGNMENT_ID}"
log "  Lab:         ${LAB}"
log "  Hosts:       ${HOST_COUNT}"
log ""
log "State saved to:"
log "  - ${STATE_FILE}"
log "  - ${ROOT_DIR}/vars/state.env"
log ""
log "Next steps:"
log "  Validate:    make -C modules/quads validate"
log "  Next phase:  make test-jetlag"
log ""
