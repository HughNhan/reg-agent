#!/bin/bash
# Phase 2: Jetlag Cluster Deployment
# Wrapper script that delegates to the Jetlag module deployment script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Delegate to the Jetlag module script
exec "${SCRIPT_DIR}/jetlag/jetlag-deploy.sh" "$@"
