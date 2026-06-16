#!/bin/bash
# Validate existing QUADS allocation
# Use when you already have a cloud assigned

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG_AGENT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Load JSON configuration
source "${REG_AGENT_ROOT}/modules/lib/json-config.sh"
json_export_env ".quads" "QUADS"

echo "Validating Existing Allocation"
echo "==============================="
echo ""

if [ -z "$CLOUD_NAME" ]; then
    echo "Error: CLOUD_NAME not set"
    echo "Set CLOUD_NAME in vars/config.json or via environment"
    exit 1
fi

if [ -z "$QUADS_LAB" ]; then
    echo "Error: LAB not set"
    echo "Set LAB in vars/config.json (e.g., scalelab, performancelab)"
    exit 1
fi

echo "Cloud: $CLOUD_NAME"
echo "Lab: $QUADS_LAB"
echo ""

# Optional: Validate cloud exists in QUADS
if [ -n "$QUADS_API_SERVER" ]; then
    echo "Checking QUADS API..."

    STATUS=$(curl -sk "https://${QUADS_API_SERVER}/api/v3/clouds/${CLOUD_NAME}" 2>/dev/null | jq -r '.name' 2>/dev/null || echo "")

    if [ "$STATUS" = "$CLOUD_NAME" ]; then
        echo "✓ Cloud $CLOUD_NAME found in QUADS"
    else
        echo "⚠️  Could not verify cloud in QUADS (proceeding anyway)"
    fi
else
    echo "⚠️  QUADS_API_SERVER not set, skipping validation"
fi

# Save state
echo "CLOUD_NAME=${CLOUD_NAME}" > "${REG_AGENT_ROOT}/vars/state.env"
echo "QUADS_METHOD=existing" >> "${REG_AGENT_ROOT}/vars/state.env"
echo "LAB=${LAB}" >> "${REG_AGENT_ROOT}/vars/state.env"

echo ""
echo "✅ Using existing allocation: $CLOUD_NAME"
exit 0
