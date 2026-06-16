#!/bin/bash
# Regulus module configuration script
# Configures Regulus-specific settings

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
echo -e "${BLUE}Regulus Configuration${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Check if in AUTO_MODE (non-interactive, from JSON)
if [ -n "$AUTO_MODE" ]; then
    # AUTO_MODE: Use environment variables from JSON parsing
    echo -e "${GREEN}Using Regulus configuration from environment${NC}"

    REGULUS_INSTALL_SUBDIR=${REGULUS_INSTALL_SUBDIR:-}
    # REG_KNI_USER already set by orchestrate-config.sh from bastion_ssh_user

    if [ -n "$REGULUS_INSTALL_SUBDIR" ]; then
        echo "  Installation path: /root/${REGULUS_INSTALL_SUBDIR}/cpt-regulus-<datetime>"
    else
        echo "  Installation path: /root/cpt-regulus-<datetime>"
    fi
    echo "  Bastion SSH user: ${REG_KNI_USER}"
    echo ""
else
    # Interactive mode
    echo "Regulus Installation Path:"
    echo "  Base: /root/"
    read -p "Optional subdirectory under /root/ [press Enter to skip]: " REGULUS_INSTALL_SUBDIR

    if [ -n "$REGULUS_INSTALL_SUBDIR" ]; then
        echo -e "${GREEN}Regulus will be installed to: /root/${REGULUS_INSTALL_SUBDIR}/cpt-regulus-<datetime>${NC}"
    else
        echo -e "${GREEN}Regulus will be installed to: /root/cpt-regulus-<datetime>${NC}"
    fi

    echo ""
    echo "Bastion Access Configuration:"
    echo "SSH username to access bastion for Regulus operations"
    read -p "Bastion SSH user [default: root]: " REG_KNI_USER
    REG_KNI_USER=${REG_KNI_USER:-root}
    echo ""
fi

# DISABLED: config.env write (passive mode - JSON only)
if false; then
    echo "Writing Regulus configuration..."

    # Remove existing Regulus config if present
    if [ -f "${VARS_DIR}/config.env" ]; then
        sed -i '/^REGULUS_INSTALL_SUBDIR=/d' "${VARS_DIR}/config.env" 2>/dev/null || true
        sed -i '/^REG_KNI_USER=/d' "${VARS_DIR}/config.env" 2>/dev/null || true
    fi

    # Ensure config.env exists
    mkdir -p "${VARS_DIR}"
    touch "${VARS_DIR}/config.env"

    # Append Regulus configuration
    cat >> "${VARS_DIR}/config.env" <<REGULUS_CONFIG

# ========================================
# Regulus Configuration
# ========================================
REGULUS_INSTALL_SUBDIR="${REGULUS_INSTALL_SUBDIR}"
REG_KNI_USER="${REG_KNI_USER}"
REGULUS_JOBS="${REGULUS_JOBS}"
REGULUS_DURATION="${REGULUS_DURATION}"
REGULUS_TAG="${REGULUS_TAG:-REG-AGENT}"
NUM_SAMPLES="${NUM_SAMPLES:-3}"

# Legacy (deprecated in favor of REGULUS_JOBS)
REGULUS_TEST_SUITE="${REGULUS_TEST_SUITE}"
REGULUS_CONFIG

    echo -e "${GREEN}✓ Regulus configuration written to vars/config.env${NC}"
fi

# Also write to JSON format
export REG_AGENT_ROOT="${ROOT_DIR}"
source "${ROOT_DIR}/modules/lib/json-config.sh" 2>/dev/null || true
if [ -f "${ROOT_DIR}/modules/lib/json-config.sh" ]; then
    json_set_multi ".regulus" \
        "install_subdir=${REGULUS_INSTALL_SUBDIR:-}" \
        "bastion_ssh_user=${REG_KNI_USER}" \
        "jobs=${REGULUS_JOBS:-}" \
        "duration=${REGULUS_DURATION:-}" \
        "tag=${REGULUS_TAG:-REG-AGENT}" \
        "num_samples=${NUM_SAMPLES:-3}" \
        "test_suite=${REGULUS_TEST_SUITE:-}"

    echo -e "${GREEN}✓ Regulus configuration also written to vars/config.json${NC}"
fi

echo ""
