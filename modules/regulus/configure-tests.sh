#!/bin/bash
# Interactive test selection for Regulus
# Allows users to select which test jobs to run

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
echo -e "${BLUE}Regulus Test Selection${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Check if config.json exists
if [ ! -f "${VARS_DIR}/config.json" ]; then
    echo -e "${RED}Error: Configuration file not found${NC}"
    echo "Run 'make configure' first"
    exit 1
fi

# Source current config to show what's currently configured
# Load JSON configuration
source "${ROOT_DIR}/modules/lib/json-config.sh"
json_export_env ".regulus" "REGULUS"

# Show current configuration
if [ -n "$REGULUS_JOBS" ]; then
    echo -e "${GREEN}Current test jobs:${NC}"
    echo "  $REGULUS_JOBS"
else
    echo -e "${YELLOW}No test jobs currently configured${NC}"
    echo "  (Regulus will use default jobs.config)"
fi
echo ""

# Test job categories
echo "Available test categories:"
echo ""
echo -e "${BLUE}Basic Tests (No PAO):${NC}"
echo "  1) 4IP                              - Basic IP networking"
echo "  2) 4IP/INTRA-NODE/TCP/2-POD         - TCP intra-node (2 pods)"
echo "  3) 4IP/INTER-NODE/TCP/2-POD         - TCP inter-node (2 pods)"
echo "  4) 4IP/INTER-NODE/UDP/2-POD         - UDP inter-node (2 pods)"
echo ""
echo -e "${BLUE}Performance Tests (PAO):${NC}"
echo "  5) PAO/6IP                          - IP with Performance Addon Operator"
echo "  6) PAO/6IP/INTER-NODE/TCP/2-POD     - TCP inter-node with PAO"
echo "  7) PAO/6IP/INTER-NODE/UDP/2-POD     - UDP inter-node with PAO"
echo ""
echo -e "${BLUE}Advanced Options:${NC}"
echo "  8) Custom job paths                 - Enter your own space-separated list"
echo "  9) Clear job selection              - Use Regulus defaults (no JOBS override)"
echo ""

read -p "Enter choice [1-9]: " CHOICE

case "$CHOICE" in
    1)
        NEW_JOBS="./1_GROUP/NO-PAO/4IP"
        DESCRIPTION="Basic IP networking tests"
        ;;
    2)
        NEW_JOBS="./1_GROUP/NO-PAO/4IP/INTRA-NODE/TCP/2-POD"
        DESCRIPTION="TCP intra-node test (2 pods)"
        ;;
    3)
        NEW_JOBS="./1_GROUP/NO-PAO/4IP/INTER-NODE/TCP/2-POD"
        DESCRIPTION="TCP inter-node test (2 pods)"
        ;;
    4)
        NEW_JOBS="./1_GROUP/NO-PAO/4IP/INTER-NODE/UDP/2-POD"
        DESCRIPTION="UDP inter-node test (2 pods)"
        ;;
    5)
        NEW_JOBS="./2_GROUP/PAO/6IP"
        DESCRIPTION="IP tests with Performance Addon Operator"
        ;;
    6)
        NEW_JOBS="./2_GROUP/PAO/6IP/INTER-NODE/TCP/2-POD"
        DESCRIPTION="TCP inter-node with PAO"
        ;;
    7)
        NEW_JOBS="./2_GROUP/PAO/6IP/INTER-NODE/UDP/2-POD"
        DESCRIPTION="UDP inter-node with PAO"
        ;;
    8)
        echo ""
        echo "Enter custom job paths (space-separated):"
        echo "Example: ./1_GROUP/NO-PAO/4IP ./2_GROUP/PAO/6IP"
        echo ""
        read -p "Job paths: " CUSTOM_JOBS

        if [ -z "$CUSTOM_JOBS" ]; then
            echo -e "${RED}No jobs entered. Exiting.${NC}"
            exit 1
        fi

        # Validate each job path
        INVALID_JOBS=""
        for job in $CUSTOM_JOBS; do
            if [[ ! "$job" =~ ^\./.*$ ]]; then
                INVALID_JOBS="$INVALID_JOBS $job"
            fi
        done

        if [ -n "$INVALID_JOBS" ]; then
            echo -e "${RED}Invalid job paths (must start with './')${NC}"
            echo "  Invalid:$INVALID_JOBS"
            exit 1
        fi

        NEW_JOBS="$CUSTOM_JOBS"
        DESCRIPTION="Custom job selection"
        ;;
    9)
        NEW_JOBS=""
        DESCRIPTION="Use Regulus default jobs.config (no override)"
        ;;
    *)
        echo -e "${RED}Invalid choice. Exiting.${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Selected: $DESCRIPTION${NC}"
if [ -n "$NEW_JOBS" ]; then
    echo "  Jobs: $NEW_JOBS"
else
    echo "  Jobs: (using Regulus defaults)"
fi
echo ""

# Update config.json
echo "Updating configuration..."

# Remove existing REGULUS_JOBS line
sed -i '/^REGULUS_JOBS=/d' "${VARS_DIR}/config.json" 2>/dev/null || true

# Add new REGULUS_JOBS line in the Regulus section
# Find the Regulus section and add REGULUS_JOBS after REG_KNI_USER
if grep -q "^# Regulus Configuration" "${VARS_DIR}/config.json"; then
    # Insert after REG_KNI_USER line
    sed -i "/^REG_KNI_USER=/a REGULUS_JOBS=\"${NEW_JOBS}\"" "${VARS_DIR}/config.json"
else
    # No Regulus section yet - add it
    echo "" >> "${VARS_DIR}/config.json"
    echo "# ========================================" >> "${VARS_DIR}/config.json"
    echo "# Regulus Configuration" >> "${VARS_DIR}/config.json"
    echo "# ========================================" >> "${VARS_DIR}/config.json"
    echo "REGULUS_JOBS=\"${NEW_JOBS}\"" >> "${VARS_DIR}/config.json"
fi

echo -e "${GREEN}✓ Test selection saved to ${VARS_DIR}/config.json${NC}"
echo ""
echo -e "${YELLOW}Note: jobs.config on bastion will be updated when you run Phase 4 (Regulus install)${NC}"
echo ""
echo "Next steps:"
echo "  - Review selection: cat ${VARS_DIR}/config.json | grep REGULUS_JOBS"
echo ""
echo "To apply the test selection:"
echo "  1. Install/Update Regulus: make -C modules/regulus install"
echo "     (This updates jobs.config on bastion with your selection)"
echo "  2. Run tests: make -C modules/regulus test"
echo ""
echo "Or use full pipeline from project root:"
echo "  make deploy run"
echo ""
