#!/bin/bash
# Quick QUADS configuration helper with intelligent detection

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG_AGENT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VARS_DIR="${REG_AGENT_ROOT}/vars"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}QUADS Configuration Setup${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Check if config.env exists and if QUADS is configured
CONFIG_EXISTS=false
QUADS_CONFIGURED=false
CURRENT_QUADS_API_SERVER=""
CURRENT_QUADS_USERNAME=""
CURRENT_LAB=""
CURRENT_AUTH_TYPE=""

if [ -f "${VARS_DIR}/config.env" ]; then
    CONFIG_EXISTS=true

    # Source config to check QUADS variables
    source "${VARS_DIR}/config.env" 2>/dev/null || true

    # Check if QUADS is configured
    if [ -n "$QUADS_API_SERVER" ] && [ -n "$QUADS_USERNAME" ] &&
       ([ -n "$QUADS_API_TOKEN" ] || [ -n "$QUADS_PASSWORD" ]); then
        QUADS_CONFIGURED=true
        CURRENT_QUADS_API_SERVER="$QUADS_API_SERVER"
        CURRENT_QUADS_USERNAME="$QUADS_USERNAME"
        CURRENT_LAB="${LAB:-not set}"
        if [ -n "$QUADS_API_TOKEN" ]; then
            CURRENT_AUTH_TYPE="API Token"
        else
            CURRENT_AUTH_TYPE="Password"
        fi
    fi
fi

# Handle different scenarios
if [ "$QUADS_CONFIGURED" = "true" ]; then
    # QUADS is already configured - show settings and ask if they want to change
    echo -e "${GREEN}✓ QUADS is already configured${NC}"
    echo ""
    echo "Current QUADS settings:"
    echo "  API Server: $CURRENT_QUADS_API_SERVER"
    echo "  Username: $CURRENT_QUADS_USERNAME"
    echo "  Lab: $CURRENT_LAB"
    echo "  Auth Method: $CURRENT_AUTH_TYPE"
    echo ""

    # In AUTO_MODE, skip interactive prompt and use existing config
    if [ -n "$AUTO_MODE" ] || [ ! -t 0 ]; then
        echo -e "${YELLOW}Running in non-interactive mode${NC}"
        echo "Using existing QUADS configuration"
        echo ""
        exit 0
    fi

    echo -e "${YELLOW}Your QUADS configuration is ready. You can:${NC}"
    echo "  - Test allocation: make allocate"
    echo "  - Edit manually: vi ${VARS_DIR}/config.env"
    echo ""
    read -p "Do you want to CHANGE your QUADS configuration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Keeping existing configuration."
        exit 0
    fi
    MODE="reconfigure"

elif [ "$CONFIG_EXISTS" = "true" ]; then
    # config.env exists but QUADS not configured
    if [ -n "$AUTO_MODE" ] || [ ! -t 0 ]; then
        # In AUTO_MODE, check if we have required environment variables from JSON
        if [ -n "$QUADS_API_SERVER" ] && [ -n "$QUADS_USERNAME" ] && [ -n "$LAB" ] && [ -n "$NUM_HOSTS" ] &&
           ([ -n "$QUADS_API_TOKEN" ] || [ -n "$QUADS_PASSWORD" ]); then
            echo -e "${GREEN}Using QUADS configuration from environment${NC}"
            echo "  API Server: $QUADS_API_SERVER"
            echo "  Username: $QUADS_USERNAME"
            echo "  Lab: $LAB"
            echo ""
            MODE="append"
        else
            echo -e "${RED}ERROR: config.env exists but QUADS is NOT configured${NC}"
            echo ""
            echo "In non-interactive mode, QUADS configuration must be provided via environment variables:"
            echo "  - QUADS_API_SERVER"
            echo "  - QUADS_USERNAME"
            echo "  - QUADS_PASSWORD (or QUADS_API_TOKEN)"
            echo "  - LAB"
            echo "  - NUM_HOSTS"
            echo ""
            echo "These are typically set by orchestrate-config.sh from JSON file."
            echo ""
            echo "To configure interactively:"
            echo "  make -C modules/quads init-debug"
            exit 1
        fi
    else
        # Interactive mode
        echo -e "${YELLOW}⚠  config.env exists but QUADS is NOT configured${NC}"
        echo ""
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}  QUADS MUST be configured to proceed  ${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "reg-agent Phase 1 requires QUADS credentials."
        echo "Press Enter to configure now, or Ctrl+C to cancel..."
        read
        MODE="append"
    fi

else
    # No config.env at all
    if [ -n "$AUTO_MODE" ] || [ ! -t 0 ]; then
        # In AUTO_MODE, check if we have required environment variables from JSON
        # For import mode, we need CLOUD_NAME instead of password/num_hosts
        if [ "$QUADS_MODE" = "import" ] && [ -n "$QUADS_API_SERVER" ] && [ -n "$QUADS_USERNAME" ] && [ -n "$LAB" ] && [ -n "$CLOUD_NAME" ]; then
            echo -e "${GREEN}Creating configuration for import mode from environment${NC}"
            echo "  API Server: $QUADS_API_SERVER"
            echo "  Username: $QUADS_USERNAME"
            echo "  Lab: $LAB"
            echo "  Cloud Name: $CLOUD_NAME"
            echo ""
            MODE="create"
        elif [ "$QUADS_MODE" != "import" ] && [ -n "$QUADS_API_SERVER" ] && [ -n "$QUADS_USERNAME" ] && [ -n "$LAB" ] && [ -n "$NUM_HOSTS" ] &&
           ([ -n "$QUADS_API_TOKEN" ] || [ -n "$QUADS_PASSWORD" ]); then
            echo -e "${GREEN}Creating configuration for allocate mode from environment${NC}"
            echo "  API Server: $QUADS_API_SERVER"
            echo "  Username: $QUADS_USERNAME"
            echo "  Lab: $LAB"
            echo ""
            MODE="create"
        else
            echo -e "${RED}ERROR: No configuration file found and no environment variables provided${NC}"
            echo ""
            echo "In non-interactive mode, QUADS configuration must be provided via environment variables:"
            echo "  - QUADS_API_SERVER"
            echo "  - QUADS_USERNAME"
            echo "  - LAB"
            echo ""
            echo "For allocate mode:"
            echo "  - QUADS_PASSWORD (or QUADS_API_TOKEN)"
            echo "  - NUM_HOSTS"
            echo ""
            echo "For import mode:"
            echo "  - CLOUD_NAME"
            echo ""
            echo "These are typically set by orchestrate-config.sh from JSON file."
            echo ""
            echo "To configure interactively:"
            echo "  make configure"
            exit 1
        fi
    else
        # Interactive mode
        echo -e "${YELLOW}⚠  No configuration file found${NC}"
        echo ""
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}  QUADS MUST be configured to proceed  ${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "This will create vars/config.env with QUADS settings."
        echo "Press Enter to continue, or Ctrl+C to cancel..."
        read
        MODE="create"
    fi
fi

echo ""
echo -e "${BLUE}Configuring QUADS...${NC}"
echo ""

# In AUTO_MODE, use environment variables; otherwise prompt interactively
if [ -n "$AUTO_MODE" ] || [ ! -t 0 ]; then
    # AUTO_MODE: Use environment variables (already validated above)
    echo "Using configuration from environment variables"

    # Determine mode from QUADS_MODE environment variable
    QUADS_MODE=${QUADS_MODE:-allocate}
    echo "  QUADS Mode: $QUADS_MODE"

    # Set defaults for optional variables
    if [ "$QUADS_MODE" = "import" ]; then
        # Import mode - minimal required values
        NUM_HOSTS=${NUM_HOSTS:-0}
        PREFERRED_MODEL=${PREFERRED_MODEL:-any}
        WIPE_DISKS=${WIPE_DISKS:-no}
        SHORT_DESCRIPTION=${SHORT_DESCRIPTION:-Imported allocation}
        WORKLOAD_NAME=${WORKLOAD_NAME:-imported-$(date +%Y%m%d-%H%M)}
        IMPORT_CLOUD_NAME=${CLOUD_NAME}
    else
        # Allocate mode - normal defaults
        PREFERRED_MODEL=${PREFERRED_MODEL:-r750,r740xd}
        WIPE_DISKS=${WIPE_DISKS:-no}
        SHORT_DESCRIPTION=${SHORT_DESCRIPTION:-reg-agent}
        WORKLOAD_NAME=${WORKLOAD_NAME:-reg-agent-$(date +%Y%m%d-%H%M)}
    fi

    # Determine USE_TOKEN flag
    if [ -n "$QUADS_API_TOKEN" ]; then
        USE_TOKEN=true
    else
        USE_TOKEN=false
    fi
else
    # Interactive mode: Prompt for all values

    # Ask: allocate new or import existing?
    echo "QUADS Configuration Mode:"
    echo "  1) Allocate new hosts (create new allocation)"
    echo "  2) Import existing allocation (use already-allocated cloud)"
    echo ""
    read -p "Enter choice [1 or 2]: " CONFIG_MODE_CHOICE

    if [ "$CONFIG_MODE_CHOICE" = "2" ]; then
        QUADS_MODE="import"
    else
        QUADS_MODE="allocate"
    fi

    echo ""

    # Choose lab
    echo "Select your lab:"
    echo "  1) Scalelab (quads2.rdu2.scalelab.redhat.com)"
    echo "  2) Performancelab (quads2.rdu3.labs.perfscale.redhat.com)"
    echo ""
    read -p "Enter choice [1 or 2]: " LAB_CHOICE

    case "$LAB_CHOICE" in
        1)
            QUADS_API_SERVER="quads2.rdu2.scalelab.redhat.com"
            LAB="scalelab"
            ;;
        2)
            QUADS_API_SERVER="quads2.rdu3.labs.perfscale.redhat.com"
            LAB="performancelab"
            ;;
        *)
            echo -e "${RED}Invalid choice. Exiting.${NC}"
            exit 1
            ;;
    esac

    echo ""
    echo -e "${GREEN}Selected: $LAB ($QUADS_API_SERVER)${NC}"
    echo ""

    # Get username
    read -p "Enter your QUADS username (without @redhat.com): " QUADS_USERNAME

    if [ -z "$QUADS_USERNAME" ]; then
        echo -e "${RED}Username cannot be empty. Exiting.${NC}"
        exit 1
    fi

    # Choose auth method
    echo ""
    echo "Choose authentication method:"
    echo "  1) API Token (recommended)"
    echo "  2) Password"
    echo ""
    read -p "Enter choice [1 or 2]: " AUTH_CHOICE

    USE_TOKEN=false
    QUADS_API_TOKEN=""
    QUADS_PASSWORD=""

    case "$AUTH_CHOICE" in
        1)
            echo ""
            echo -e "${BLUE}Get your API token from: http://${QUADS_API_SERVER}/login${NC}"
            echo "  → Login → Profile → API Tokens → Generate"
            echo ""
            read -p "Enter your API token (qat_xxxxx) [or press Enter to skip]: " QUADS_API_TOKEN_INPUT

            if [ -n "$QUADS_API_TOKEN_INPUT" ]; then
                QUADS_API_TOKEN="$QUADS_API_TOKEN_INPUT"
                USE_TOKEN=true
            else
                echo -e "${YELLOW}No API token provided. Falling back to password.${NC}"
                read -sp "Enter your QUADS password: " QUADS_PASSWORD
                echo ""
                USE_TOKEN=false
            fi
            ;;
        2)
            echo ""
            read -sp "Enter your QUADS password: " QUADS_PASSWORD
            echo ""
            if [ -z "$QUADS_PASSWORD" ]; then
                echo -e "${RED}Password cannot be empty. Exiting.${NC}"
                exit 1
            fi
            USE_TOKEN=false
            ;;
        *)
            echo -e "${RED}Invalid choice. Exiting.${NC}"
            exit 1
            ;;
    esac

    # Cluster settings (only for allocate mode)
    if [ "$QUADS_MODE" = "allocate" ]; then
        echo ""
        echo "Cluster Configuration:"
        read -p "Number of hosts [default: 3]: " NUM_HOSTS_INPUT
        NUM_HOSTS=${NUM_HOSTS_INPUT:-3}

        read -p "Preferred models [default: r750,r740xd]: " PREFERRED_MODEL_INPUT
        PREFERRED_MODEL=${PREFERRED_MODEL_INPUT:-r750,r740xd}

        read -p "Wipe disks? (yes/no) [default: no]: " WIPE_DISKS_INPUT
        WIPE_DISKS=${WIPE_DISKS_INPUT:-no}

        read -p "Short description [default: Dataplane development]: " SHORT_DESCRIPTION_INPUT
        SHORT_DESCRIPTION=${SHORT_DESCRIPTION_INPUT:-Dataplane development}

        # Generate workload name
        WORKLOAD_NAME="reg-agent-$(date +%Y%m%d-%H%M)"
    else
        # Import mode - get cloud name
        echo ""
        echo "Import Existing Allocation:"
        read -p "Enter CLOUD_NAME (e.g., cloud23): " IMPORT_CLOUD_NAME

        if [ -z "$IMPORT_CLOUD_NAME" ]; then
            echo -e "${RED}Cloud name cannot be empty. Exiting.${NC}"
            exit 1
        fi

        # Set minimal required values for import
        NUM_HOSTS="0"
        PREFERRED_MODEL="any"
        WIPE_DISKS="no"
        SHORT_DESCRIPTION="Imported allocation"
        WORKLOAD_NAME="imported-$(date +%Y%m%d-%H%M)"
    fi
fi

# Write config
echo ""
echo "Writing configuration..."

# DISABLED: config.env creation/modification (passive mode - JSON only)
if false; then
    if [ "$MODE" = "create" ]; then
        # Create new config with base settings
        # In AUTO_MODE, respect DEPLOY_MODE from orchestrator; otherwise default to full
        INITIAL_DEPLOY_MODE=${DEPLOY_MODE:-full}

        cat > "${VARS_DIR}/config.env" <<EOF
# reg-agent Configuration
# Generated: $(date)

# ========================================
# Deployment Mode
# ========================================
DEPLOY_MODE=${INITIAL_DEPLOY_MODE}
EXPERT_PHASE_1=true
EXPERT_PHASE_2=false
EXPERT_PHASE_3=false
EXPERT_PHASE_4=false
EXPERT_PHASE_5=false
EXPERT_PHASE_6=false

EOF
    fi

    if [ "$MODE" = "reconfigure" ]; then
        # Remove existing QUADS configuration
        sed -i '/^# ========================================$/,/^QUADS_USER_DOMAIN=/d' "${VARS_DIR}/config.env" 2>/dev/null || true
        sed -i '/^QUADS_API_SERVER=/d' "${VARS_DIR}/config.env" 2>/dev/null || true
        sed -i '/^QUADS_USERNAME=/d' "${VARS_DIR}/config.env" 2>/dev/null || true
        sed -i '/^QUADS_PASSWORD=/d' "${VARS_DIR}/config.env" 2>/dev/null || true
        sed -i '/^QUADS_API_TOKEN=/d' "${VARS_DIR}/config.env" 2>/dev/null || true
        sed -i '/^LAB=/d' "${VARS_DIR}/config.env" 2>/dev/null || true
        sed -i '/^NUM_HOSTS=/d' "${VARS_DIR}/config.env" 2>/dev/null || true
        sed -i '/^PREFERRED_MODEL=/d' "${VARS_DIR}/config.env" 2>/dev/null || true
        sed -i '/^WORKLOAD_NAME=/d' "${VARS_DIR}/config.env" 2>/dev/null || true
        sed -i '/^SHORT_DESCRIPTION=/d' "${VARS_DIR}/config.env" 2>/dev/null || true
        sed -i '/^WIPE_DISKS=/d' "${VARS_DIR}/config.env" 2>/dev/null || true
    fi
fi

# DISABLED: config.env write (passive mode - JSON only)
# Temporarily disabled to migrate to JSON-only configuration
if false; then
    # Append QUADS config
    echo "DEBUG: About to write QUADS config to ${VARS_DIR}/config.env"
    echo "DEBUG: VARS_DIR=$VARS_DIR"
    echo "DEBUG: File exists before write: $([ -f "${VARS_DIR}/config.env" ] && echo 'YES' || echo 'NO')"
    cat >> "${VARS_DIR}/config.env" <<EOF

# ========================================
# QUADS Configuration
# ========================================
QUADS_API_SERVER="${QUADS_API_SERVER}"
QUADS_USERNAME="${QUADS_USERNAME}"
QUADS_USER_DOMAIN="redhat.com"
LAB="${LAB}"
NUM_HOSTS="${NUM_HOSTS}"
PREFERRED_MODEL="${PREFERRED_MODEL}"
WORKLOAD_NAME="${WORKLOAD_NAME}"
SHORT_DESCRIPTION="${SHORT_DESCRIPTION}"
WIPE_DISKS="${WIPE_DISKS}"
EOF
    echo "DEBUG: File exists after write: $([ -f "${VARS_DIR}/config.env" ] && echo 'YES' || echo 'NO')"
    echo "DEBUG: File size: $(wc -l < "${VARS_DIR}/config.env") lines"

    if [ "$USE_TOKEN" = "true" ] && [ -n "$QUADS_API_TOKEN" ]; then
        echo "QUADS_API_TOKEN=\"${QUADS_API_TOKEN}\"" >> "${VARS_DIR}/config.env"
    elif [ -n "$QUADS_PASSWORD" ]; then
        echo "QUADS_PASSWORD=\"${QUADS_PASSWORD}\"" >> "${VARS_DIR}/config.env"
    fi

    # If import mode, add CLOUD_NAME
    if [ -n "$QUADS_MODE" ] && [ "$QUADS_MODE" = "import" ] && [ -n "$IMPORT_CLOUD_NAME" ]; then
        echo "CLOUD_NAME=\"${IMPORT_CLOUD_NAME}\"" >> "${VARS_DIR}/config.env"
    fi

    echo -e "${GREEN}✓ Configuration written to ${VARS_DIR}/config.env${NC}"
fi

# Also write to JSON format
export REG_AGENT_ROOT
source "${REG_AGENT_ROOT}/modules/lib/json-config.sh" 2>/dev/null || true
if [ -f "${REG_AGENT_ROOT}/modules/lib/json-config.sh" ]; then
    json_set_multi ".quads" \
        "api_server=$QUADS_API_SERVER" \
        "username=$QUADS_USERNAME" \
        "user_domain=redhat.com" \
        "lab=$LAB" \
        "num_hosts=$NUM_HOSTS" \
        "preferred_model=$PREFERRED_MODEL" \
        "workload_name=$WORKLOAD_NAME" \
        "short_description=$SHORT_DESCRIPTION" \
        "wipe_disks=$WIPE_DISKS"

    if [ "$USE_TOKEN" = "true" ] && [ -n "$QUADS_API_TOKEN" ]; then
        json_set ".quads.api_token" "$QUADS_API_TOKEN"
    elif [ -n "$QUADS_PASSWORD" ]; then
        json_set ".quads.password" "$QUADS_PASSWORD"
    fi

    if [ -n "$QUADS_MODE" ] && [ "$QUADS_MODE" = "import" ] && [ -n "$IMPORT_CLOUD_NAME" ]; then
        json_set ".quads.cloud_name" "$IMPORT_CLOUD_NAME"
        json_set ".quads.mode" "import"
    else
        json_set ".quads.mode" "allocate"
    fi

    echo -e "${GREEN}✓ Configuration also written to ${VARS_DIR}/config.json${NC}"
fi

echo ""
echo -e "${BLUE}Configuration Summary:${NC}"
echo "  Lab: $LAB"
echo "  API Server: $QUADS_API_SERVER"
echo "  Username: $QUADS_USERNAME"
if [ "$USE_TOKEN" = "true" ] && [ -n "$QUADS_API_TOKEN" ]; then
    echo "  Auth: API Token (${QUADS_API_TOKEN:0:10}...)"
else
    echo "  Auth: Password"
fi

if [ -n "$QUADS_MODE" ] && [ "$QUADS_MODE" = "import" ]; then
    echo "  Mode: Import existing allocation"
    echo "  Cloud Name: $IMPORT_CLOUD_NAME"
else
    echo "  Mode: Allocate new hosts"
    echo "  Hosts: $NUM_HOSTS"
    echo "  Models: $PREFERRED_MODEL"
    echo "  Wipe Disks: $WIPE_DISKS"
fi

echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "  1. Review: cat ${VARS_DIR}/config.env"
if [ -n "$QUADS_MODE" ] && [ "$QUADS_MODE" = "import" ]; then
    echo "  2. Import: make -C modules/quads import"
    echo "  3. Continue: Use orchestrator or run phases manually"
else
    echo "  2. Allocate: make -C modules/quads allocate"
    echo "  3. Continue: Use orchestrator or run phases manually"
fi
echo ""
