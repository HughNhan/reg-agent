#!/bin/bash
# Jetlag Module Interface Definition
# Declares what this module requires and provides

# Module metadata
MODULE_NAME="jetlag"
MODULE_DESCRIPTION="OpenShift cluster deployment"
MODULE_PHASE="2"

# What this module requires (inputs from previous modules)
MODULE_REQUIRES=(
    "CLOUD_NAME"           # From QUADS module
    "LAB"                  # From QUADS module
)

# What this module provides (outputs)
MODULE_PROVIDES=(
    "BASTION_HOST"         # Bastion hostname/IP
    "KUBECONFIG_PATH"      # Path to kubeconfig on bastion
    "CLUSTER_TYPE"         # mno or sno
    "WORKER_NODE_COUNT"    # Number of worker nodes (for mno)
)

# Configuration variables this module needs
MODULE_CONFIG_VARS=(
    "CLUSTER_TYPE"         # mno or sno
    "OCP_BUILD"            # ga, dev, or ci
    "OCP_VERSION"          # e.g., latest-4.20
    "NETWORK_STACK"        # ipv4, ipv6, or dual
    "PULL_SECRET_PATH"     # Path to OpenShift pull secret
)

# Optional configuration variables
MODULE_OPTIONAL_VARS=(
    "WORKER_NODE_COUNT"    # For MNO clusters
    "IPV6_MODE"            # proxy or disconnected (when NETWORK_STACK=ipv6)
    "BMC_PASSWORD"         # Custom BMC password
    "LAB_SSH_PASSWORD"     # For SSH key setup
)

# Module modes
MODULE_MODES=(
    "deploy"               # Deploy new cluster
)
