#!/bin/bash
# Regulus Module Interface Definition
# Declares what this module requires and provides

# Module metadata
MODULE_NAME="regulus"
MODULE_DESCRIPTION="Regulus performance testing"
MODULE_PHASE="4"

# What this module requires (inputs from previous modules)
MODULE_REQUIRES=(
    "BASTION_HOST"         # From Jetlag module
    "KUBECONFIG_PATH"      # From Jetlag module
    "CLUSTER_TYPE"         # From Jetlag module
    "CRUCIBLE_PATH"        # From Crucible module
)

# What this module provides (outputs)
MODULE_PROVIDES=(
    "REGULUS_PATH"         # Installation path on bastion
    "RUN_ID"               # Test run identifier (after test execution)
)

# Configuration variables this module needs
MODULE_CONFIG_VARS=(
    "REGULUS_JOBS"         # Test job paths (e.g., "./SANDBOX")
    "REGULUS_TAG"          # Test identifier tag
    "NUM_SAMPLES"          # Number of test samples
    "TEST_DURATION"        # Test duration in seconds
)

# Optional configuration variables
MODULE_OPTIONAL_VARS=(
    "REG_KNI_USER"         # SSH user for bastion (default: root)
    "REG_DP"               # Deployment identifier
    "REGULUS_INSTALL_SUBDIR" # Subdirectory under /root/
)

# Module modes
MODULE_MODES=(
    "install"              # Install and configure Regulus
    "run"                  # Execute tests
    "validate"             # Validate results
)
