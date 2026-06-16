#!/bin/bash
# Phase 1: QUADS Allocation (Router)
# Calls appropriate QUADS method based on QUADS_METHOD config

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG_AGENT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source configuration
if [ ! -f "${REG_AGENT_ROOT}/vars/config.json" ]; then
    echo "Error: Configuration not found at ${REG_AGENT_ROOT}/vars/config.json"
    echo "Run: make configure"
    exit 1
fi

# Load JSON configuration
source "${REG_AGENT_ROOT}/modules/lib/json-config.sh"
json_export_env ".quads" "QUADS"

# Default to quads-ssm if not set
QUADS_METHOD=${QUADS_METHOD:-quads-ssm}

echo "============================================="
echo "Phase 1: QUADS Allocation"
echo "Method: $QUADS_METHOD"
echo "============================================="
echo ""

case "$QUADS_METHOD" in
    quads-ssm)
        echo "Using QUADS SSM (ansible-quads-ssm) - Default method"
        "${SCRIPT_DIR}/quads/quads-ssm-reserve.sh"
        ;;

    jetlag-ssd)
        echo "Using Jetlag self-sched-deploy"
        "${SCRIPT_DIR}/quads/jetlag-ssd-reserve.sh"
        ;;

    existing)
        echo "Using existing allocation: $CLOUD_NAME"
        "${SCRIPT_DIR}/quads/validate-existing.sh"
        ;;

    *)
        echo "Error: Unknown QUADS_METHOD: $QUADS_METHOD"
        echo "Valid options: quads-ssm, jetlag-ssd, existing"
        exit 1
        ;;
esac

echo ""
echo "✅ Phase 1: QUADS Allocation complete"
exit 0
