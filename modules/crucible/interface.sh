#!/bin/bash
# Crucible Module Interface Definition
# Declares what this module requires and provides

# Module metadata
MODULE_NAME="crucible"
MODULE_DESCRIPTION="Crucible performance framework installation"
MODULE_PHASE="3"

# What this module requires (inputs from previous modules)
MODULE_REQUIRES=(
    "BASTION_HOST"         # From Jetlag module
)

# What this module provides (outputs)
MODULE_PROVIDES=(
    "CRUCIBLE_PATH"        # Installation path on bastion (/root/crucible)
)

# Configuration variables this module needs
MODULE_CONFIG_VARS=(
    "CRUCIBLE_GIT_REPO"    # Git repository URL
    "CRUCIBLE_GIT_BRANCH"  # Branch to clone
)

# Optional configuration variables
MODULE_OPTIONAL_VARS=(
    "CRUCIBLE_INSTALL_DIR" # Custom installation directory
)

# Module modes
MODULE_MODES=(
    "install"              # Install Crucible on bastion
)
