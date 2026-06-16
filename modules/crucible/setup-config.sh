#!/bin/bash
# Crucible Module Configuration
# Collects Crucible-specific configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VARS_DIR="${ROOT_DIR}/vars"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Crucible Configuration${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Check if in AUTO_MODE (non-interactive, from JSON)
if [ -n "$AUTO_MODE" ]; then
    # AUTO_MODE: Use environment variables from JSON parsing
    echo -e "${GREEN}Using Crucible configuration from environment${NC}"

    # Set defaults for Crucible
    CRUCIBLE_GIT_REPO=${CRUCIBLE_GIT_REPO:-https://github.com/perftool-incubator/crucible.git}
    CRUCIBLE_GIT_BRANCH=${CRUCIBLE_GIT_BRANCH:-master}

    # CRUCIBLE_CONTROLLER_TARGET will be set during deployment when BASTION_HOST is available
    # For now, just note that it will use the bastion
    if [ -n "$BASTION_HOST" ]; then
        CRUCIBLE_CONTROLLER_TARGET=${BASTION_HOST}
        echo "  Installation target: ${CRUCIBLE_CONTROLLER_TARGET}"
    else
        echo "  Installation target: bastion (will be determined during deployment)"
    fi

    echo "  Git repository: ${CRUCIBLE_GIT_REPO}"
    echo "  Git branch: ${CRUCIBLE_GIT_BRANCH}"
    echo ""
else
    # Interactive mode
    echo "Crucible will be installed on the bastion host."
    echo ""

    if [ -n "$BASTION_HOST" ]; then
        # Bastion already known (cluster-ready mode)
        echo "Detected bastion from cluster configuration: $BASTION_HOST"
        echo ""
        read -p "Install Crucible on this host? (Y/n): " use_bastion
        if [[ ! "$use_bastion" =~ ^[Nn]$ ]]; then
            CRUCIBLE_CONTROLLER_TARGET="$BASTION_HOST"
        else
            read -p "Enter target host for Crucible: " CRUCIBLE_CONTROLLER_TARGET
        fi
    else
        # Bastion not known yet (full mode - will come from Jetlag)
        echo -e "${YELLOW}Bastion host will be determined after cluster deployment${NC}"
        echo ""
        echo "Crucible will automatically be installed on the bastion after Jetlag completes."
        echo ""
        read -p "Press Enter to continue with default settings..."
        # Don't set CRUCIBLE_CONTROLLER_TARGET yet - it will be set during deployment
    fi

    echo ""
    echo "Crucible Git Configuration:"
    read -p "Git repository [https://github.com/perftool-incubator/crucible.git]: " CRUCIBLE_GIT_REPO_INPUT
    CRUCIBLE_GIT_REPO=${CRUCIBLE_GIT_REPO_INPUT:-https://github.com/perftool-incubator/crucible.git}

    read -p "Git branch [master]: " CRUCIBLE_GIT_BRANCH_INPUT
    CRUCIBLE_GIT_BRANCH=${CRUCIBLE_GIT_BRANCH_INPUT:-master}

    echo ""
    echo "Controller SSH Access:"
    read -p "Controller SSH username [default: root]: " CRUCIBLE_CONTROLLER_USER
    CRUCIBLE_CONTROLLER_USER=${CRUCIBLE_CONTROLLER_USER:-root}
    read -s -p "Controller SSH password (optional, press Enter to skip): " CRUCIBLE_CONTROLLER_PASSWORD
    echo ""
    if [ -n "$CRUCIBLE_CONTROLLER_PASSWORD" ]; then
        echo -e "${GREEN}✓ Controller SSH credentials: user=${CRUCIBLE_CONTROLLER_USER}, password=configured${NC}"
    else
        echo -e "${YELLOW}⚠  No controller SSH password (may require manual SSH key setup)${NC}"
    fi

    echo ""
fi

# Write to config.env
# Set defaults in AUTO_MODE
CRUCIBLE_CONTROLLER_USER=${CRUCIBLE_CONTROLLER_USER:-root}

# DISABLED: config.env write (passive mode - JSON only)
if false; then
    echo "Writing Crucible configuration..."

    # Remove existing Crucible config if present
    if [ -f "${VARS_DIR}/config.env" ]; then
        sed -i '/^CRUCIBLE_GIT_REPO=/d' "${VARS_DIR}/config.env" 2>/dev/null || true
        sed -i '/^CRUCIBLE_GIT_BRANCH=/d' "${VARS_DIR}/config.env" 2>/dev/null || true
        sed -i '/^CRUCIBLE_CONTROLLER_TARGET=/d' "${VARS_DIR}/config.env" 2>/dev/null || true
        sed -i '/^CRUCIBLE_CONTROLLER_USER=/d' "${VARS_DIR}/config.env" 2>/dev/null || true
        sed -i '/^CRUCIBLE_CONTROLLER_PASSWORD=/d' "${VARS_DIR}/config.env" 2>/dev/null || true
    fi

    # Ensure config.env exists
    mkdir -p "${VARS_DIR}"
    touch "${VARS_DIR}/config.env"

    # Append Crucible configuration
    cat >> "${VARS_DIR}/config.env" <<CRUCIBLE_CONFIG

# ========================================
# Crucible Configuration
# ========================================
CRUCIBLE_GIT_REPO="${CRUCIBLE_GIT_REPO}"
CRUCIBLE_GIT_BRANCH="${CRUCIBLE_GIT_BRANCH}"
CRUCIBLE_CONTROLLER_TARGET="${CRUCIBLE_CONTROLLER_TARGET}"
CRUCIBLE_CONTROLLER_USER="${CRUCIBLE_CONTROLLER_USER}"
${CRUCIBLE_CONTROLLER_PASSWORD:+CRUCIBLE_CONTROLLER_PASSWORD="${CRUCIBLE_CONTROLLER_PASSWORD}"}
CRUCIBLE_CONFIG

    echo -e "${GREEN}✓ Crucible configuration written to vars/config.env${NC}"
fi

# Also write to JSON format
export REG_AGENT_ROOT="${ROOT_DIR}"
source "${ROOT_DIR}/modules/lib/json-config.sh" 2>/dev/null || true
if [ -f "${ROOT_DIR}/modules/lib/json-config.sh" ]; then
    json_set_multi ".crucible" \
        "git_repo=${CRUCIBLE_GIT_REPO}" \
        "git_branch=${CRUCIBLE_GIT_BRANCH}"

    json_set_multi ".crucible_controller" \
        "target=${CRUCIBLE_CONTROLLER_TARGET}" \
        "user=${CRUCIBLE_CONTROLLER_USER}" \
        "password=${CRUCIBLE_CONTROLLER_PASSWORD:-}"

    echo -e "${GREEN}✓ Crucible configuration also written to vars/config.json${NC}"
fi

echo ""
