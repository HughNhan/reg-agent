#!/bin/bash
# Import existing cluster configuration
# For use when cluster already exists and was not deployed by reg-agent

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
    echo -e "$@" | tee -a "$LOG_FILE"
}

log ""
log "${BLUE}=========================================${NC}"
log "${BLUE}Import Existing Cluster${NC}"
log "${BLUE}=========================================${NC}"
log ""
log "Log file: $LOG_FILE"
log ""

#------------------------------------------------------------------------------
# Input Resolution
#------------------------------------------------------------------------------

# Priority 1: Command-line arguments (make import BASTION_HOST=...)
if [[ -n "$BASTION_HOST" ]] && [[ -n "$KUBECONFIG_PATH" ]] && [[ -n "$CLUSTER_TYPE" ]]; then
    log "Using cluster details from command-line arguments"

# Priority 2: Interactive configuration file
elif [[ -f "$SCRIPT_DIR/generated/config/import.env" ]]; then
    log "Loading cluster details from import configuration..."
    source "$SCRIPT_DIR/generated/config/import.env"

# Priority 3: Global config
elif [[ -f "$ROOT_DIR/vars/config.json" ]]; then
    log "Loading cluster details from vars/config.json..."
    # Load JSON configuration
source "$ROOT_DIR/modules/lib/json-config.sh"
json_export_env ".jetlag" ""
json_export_env ".lab" "LAB"

else
    log "${RED}ERROR: Missing cluster details for import${NC}"
    log ""
    log "Provide via:"
    log "  1. Command line:"
    log "     make -C modules/jetlag import BASTION_HOST=my-cluster.example.com \\"
    log "       KUBECONFIG_PATH=/root/mno/kubeconfig CLUSTER_TYPE=mno"
    log ""
    log "  2. Interactive setup:"
    log "     make -C modules/jetlag init"
    log "     # Choose option 3: Import existing cluster"
    log "     make -C modules/jetlag import"
    log ""
    log "  3. Edit vars/config.json and set:"
    log "     BASTION_HOST=my-cluster.example.com"
    log "     KUBECONFIG_PATH=/root/mno/kubeconfig"
    log "     CLUSTER_TYPE=mno"
    log ""
    exit 1
fi

# Validate required variables
if [ -z "$BASTION_HOST" ]; then
    log "${RED}ERROR: BASTION_HOST not set${NC}"
    exit 1
fi

if [ -z "$KUBECONFIG_PATH" ]; then
    log "${RED}ERROR: KUBECONFIG_PATH not set${NC}"
    exit 1
fi

if [ -z "$CLUSTER_TYPE" ]; then
    log "${YELLOW}Warning: CLUSTER_TYPE not set, defaulting to 'mno'${NC}"
    CLUSTER_TYPE="mno"
fi

log "Cluster details to import:"
log "  BASTION_HOST:    ${BASTION_HOST}"
log "  KUBECONFIG_PATH: ${KUBECONFIG_PATH}"
log "  CLUSTER_TYPE:    ${CLUSTER_TYPE}"
log ""

# Try to extract CLOUD_NAME from bastion hostname
# Format: cloudXX-h01-000-r740xd.lab.domain.com -> cloudXX
CLOUD_NAME=""
if [[ "$BASTION_HOST" =~ ^(cloud[0-9]+) ]]; then
    CLOUD_NAME="${BASH_REMATCH[1]}"
    log "Detected CLOUD_NAME from bastion hostname: ${CLOUD_NAME}"
    log ""
fi

# If we couldn't detect it, ask the user
if [ -z "$CLOUD_NAME" ]; then
    log "${YELLOW}Could not auto-detect CLOUD_NAME from bastion hostname${NC}"
    log ""
    read -p "Enter CLOUD_NAME (e.g., cloud16) or press Enter to skip: " CLOUD_NAME_INPUT
    CLOUD_NAME="$CLOUD_NAME_INPUT"
    log ""
fi

#------------------------------------------------------------------------------
# Save to State (Create temporary state for validation)
#------------------------------------------------------------------------------

log "${BLUE}Creating temporary state for validation...${NC}"

# Create module state first (so validate script can read it)
cat > "$STATE_FILE" << EOF
# Imported cluster state
# Imported: $(date)

BASTION_HOST=${BASTION_HOST}
KUBECONFIG_PATH=${KUBECONFIG_PATH}
CLUSTER_TYPE=${CLUSTER_TYPE}
${CLOUD_NAME:+CLOUD_NAME=${CLOUD_NAME}}

DEPLOYMENT_METHOD=imported
JETLAG_STATUS=in_progress
EOF

log "${GREEN}✓ Temporary state created${NC}"

#------------------------------------------------------------------------------
# Validate Cluster Accessibility
#------------------------------------------------------------------------------

log ""
log "${BLUE}Validating cluster accessibility...${NC}"
log ""

# Run validation script
if "${SCRIPT_DIR}/jetlag-validate.sh"; then
    log ""
    log "${GREEN}✓ Cluster validated successfully${NC}"
else
    log ""
    log "${RED}✗ Cluster validation failed${NC}"
    log ""
    log "Fix the validation issues above and try again."
    log ""
    log "To retry after fixing, run:"
    log "  make -C modules/jetlag import BASTION_HOST=${BASTION_HOST} KUBECONFIG_PATH=${KUBECONFIG_PATH} CLUSTER_TYPE=${CLUSTER_TYPE}"
    exit 1
fi

#------------------------------------------------------------------------------
# Update State with Validation Complete
#------------------------------------------------------------------------------

log ""
log "${BLUE}Updating cluster state...${NC}"

# Update module state with validation complete
cat > "$STATE_FILE" << EOF
# Imported cluster state
# Imported: $(date)

BASTION_HOST=${BASTION_HOST}
KUBECONFIG_PATH=${KUBECONFIG_PATH}
CLUSTER_TYPE=${CLUSTER_TYPE}
${CLOUD_NAME:+CLOUD_NAME=${CLOUD_NAME}}

DEPLOYMENT_METHOD=imported
JETLAG_STATUS=completed
JETLAG_IMPORT_COMPLETED=true
JETLAG_IMPORT_TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
CLUSTER_VALIDATED=true
EOF

log "${GREEN}✓ State updated: ${STATE_FILE}${NC}"

# Sync to global state
log "Syncing to global state..."

cat >> "${ROOT_DIR}/vars/state.env" << EOF

# Phase 2: Jetlag Import (added $(date))
BASTION_HOST=${BASTION_HOST}
KUBECONFIG_PATH=${KUBECONFIG_PATH}
CLUSTER_TYPE=${CLUSTER_TYPE}
${CLOUD_NAME:+CLOUD_NAME=${CLOUD_NAME}}
DEPLOYMENT_METHOD=imported
JETLAG_IMPORT_COMPLETED=true
JETLAG_IMPORT_TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
CLUSTER_VALIDATED=true
EOF

log "${GREEN}✓ State synced to ${ROOT_DIR}/vars/state.env${NC}"

#------------------------------------------------------------------------------
# Success Summary
#------------------------------------------------------------------------------

log ""
log "${GREEN}=========================================${NC}"
log "${GREEN}Cluster Import Complete!${NC}"
log "${GREEN}=========================================${NC}"
log ""
log "Imported cluster:"
log "  Bastion:    ${BASTION_HOST}"
log "  Kubeconfig: ${KUBECONFIG_PATH}"
log "  Type:       ${CLUSTER_TYPE}"
log ""
log "State saved to:"
log "  - ${STATE_FILE}"
log "  - ${ROOT_DIR}/vars/state.env"
log ""
log "Next phase:"
log "  make test-crucible"
log ""
