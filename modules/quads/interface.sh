#!/bin/bash
# QUADS Module Interface Definition
# Declares what this module requires and provides

# Module metadata
MODULE_NAME="quads"
MODULE_DESCRIPTION="QUADS resource allocation"
MODULE_PHASE="1"

# What this module requires (inputs)
# Empty array = no dependencies on other modules
MODULE_REQUIRES=()

# What this module provides (outputs)
# These variables will be available to downstream modules
MODULE_PROVIDES=(
    "CLOUD_NAME"           # Allocated cloud identifier (e.g., cloud42)
    "ASSIGNMENT_ID"        # QUADS assignment ID
    "LAB"                  # Lab location (scalelab or performancelab)
    "NUM_HOSTS"            # Number of allocated hosts
    "QUADS_METHOD"         # Allocation method (quads-ssm)
)

# Configuration variables this module needs
# These come from user input via setup-config.sh
MODULE_CONFIG_VARS=(
    "QUADS_API_SERVER"     # QUADS API endpoint
    "QUADS_USERNAME"       # Username for QUADS
    "QUADS_PASSWORD"       # Password (or QUADS_API_TOKEN)
    "LAB"                  # Lab to allocate from
    "NUM_HOSTS"            # Number of hosts to request
    "PREFERRED_MODEL"      # Hardware model preference
    "WORKLOAD_NAME"        # Identifier for reservation
)

# Optional configuration variables
MODULE_OPTIONAL_VARS=(
    "QUADS_API_TOKEN"      # Alternative to password
    "WIPE_DISKS"           # Whether to wipe disks
    "SHORT_DESCRIPTION"    # Assignment description
)

# Module modes
MODULE_MODES=(
    "allocate"             # Allocate new resources
    "import"               # Import existing allocation
)
