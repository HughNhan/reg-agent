#!/bin/bash
# Configuration validation library
# Provides validation helper functions for interactive configuration scripts
#
# ARCHITECTURE:
# - Basic field validators (validate_required, validate_choice, etc.) - used directly by configure scripts
# - Section validators (validate_quads_config, etc.) - lightweight wrappers for quick feedback
# - Comprehensive validation (validate_all_config) - delegates to config/validate-config.sh
#
# SINGLE SOURCE OF TRUTH: The comprehensive standalone validator at config/validate-config.sh
# contains the authoritative validation logic. This library provides convenience wrappers
# and basic field validators to support interactive configuration workflows.

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

#------------------------------------------------------------------------------
# Per-Field Validation Functions
#------------------------------------------------------------------------------

# Validate non-empty string
validate_required() {
    local value="$1"
    local field_name="$2"

    if [[ -z "$value" ]]; then
        echo -e "${RED}✗ $field_name is required${NC}" >&2
        return 1
    fi
    return 0
}

# Validate positive integer
validate_positive_int() {
    local value="$1"
    local field_name="$2"

    if [[ ! "$value" =~ ^[0-9]+$ ]] || [[ "$value" -le 0 ]]; then
        echo -e "${RED}✗ $field_name must be a positive integer${NC}" >&2
        return 1
    fi
    return 0
}

# Validate non-negative integer (allows 0)
validate_non_negative_int() {
    local value="$1"
    local field_name="$2"

    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}✗ $field_name must be a non-negative integer${NC}" >&2
        return 1
    fi
    return 0
}

# Validate choice from list
validate_choice() {
    local value="$1"
    local field_name="$2"
    shift 2
    local choices=("$@")

    for choice in "${choices[@]}"; do
        if [[ "$value" == "$choice" ]]; then
            return 0
        fi
    done

    echo -e "${RED}✗ $field_name must be one of: ${choices[*]}${NC}" >&2
    return 1
}

# Validate hostname format
validate_hostname() {
    local value="$1"
    local field_name="$2"

    # Allow empty for optional hostnames
    if [[ -z "$value" ]]; then
        return 0
    fi

    # Basic hostname validation: alphanumeric, dots, hyphens
    if [[ ! "$value" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        echo -e "${RED}✗ $field_name must be a valid hostname${NC}" >&2
        return 1
    fi
    return 0
}

# Validate file path exists
validate_file_exists() {
    local value="$1"
    local field_name="$2"

    # Allow empty for optional files
    if [[ -z "$value" ]]; then
        return 0
    fi

    if [[ ! -f "$value" ]]; then
        echo -e "${RED}✗ $field_name: file not found: $value${NC}" >&2
        return 1
    fi
    return 0
}

# Validate URL format
validate_url() {
    local value="$1"
    local field_name="$2"

    # Allow empty for optional URLs
    if [[ -z "$value" ]]; then
        return 0
    fi

    if [[ ! "$value" =~ ^https?:// ]]; then
        echo -e "${RED}✗ $field_name must start with http:// or https://${NC}" >&2
        return 1
    fi
    return 0
}

# Validate cloud name format (cloudXX)
validate_cloud_name() {
    local value="$1"
    local field_name="$2"

    if [[ ! "$value" =~ ^cloud[0-9]+$ ]]; then
        echo -e "${RED}✗ $field_name must be in format 'cloudXX' (e.g., cloud23)${NC}" >&2
        return 1
    fi
    return 0
}

#------------------------------------------------------------------------------
# JSON Configuration Validation
# These functions are wrappers that provide a simplified interface for
# configure scripts. They delegate to the comprehensive standalone validator
# at config/validate-config.sh which contains the single source of truth
# for all validation logic.
#------------------------------------------------------------------------------

# Validate entire configuration file using standalone validator
validate_all_config() {
    local config_file="$1"

    # Find the standalone validator
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local root_dir="$(cd "${script_dir}/../.." && pwd)"
    local standalone_validator="${root_dir}/config/validate-config.sh"

    if [[ ! -f "$standalone_validator" ]]; then
        echo -e "${RED}ERROR: Standalone validator not found at ${standalone_validator}${NC}" >&2
        return 1
    fi

    # Call the comprehensive validator (single source of truth)
    "$standalone_validator" "$config_file"
    return $?
}

# Validate QUADS configuration
# Parameters:
#   $1 - config file path
#   $2 - error reporter function name (optional, default: simple error echo)
#   $3 - warning reporter function name (optional, default: simple warning echo)
validate_quads_config() {
    local config_file="$1"
    local error_fn="${2:-_default_error}"
    local warn_fn="${3:-_default_warning}"

    echo -e "${BLUE}Checking QUADS configuration...${NC}"

    # Read configuration values
    local mode=$(jq -r '.quads.mode // "allocate"' "$config_file")
    local lab=$(jq -r '.quads.lab // empty' "$config_file")
    local api_server=$(jq -r '.quads.api_server // empty' "$config_file")
    local username=$(jq -r '.quads.username // empty' "$config_file")
    local password=$(jq -r '.quads.password // empty' "$config_file")
    local api_token=$(jq -r '.quads.api_token // empty' "$config_file")

    # Mode validation
    if [[ "$mode" != "allocate" ]] && [[ "$mode" != "import" ]]; then
        $error_fn "Invalid quads.mode: ${mode} (valid: allocate, import)" ".quads.mode"
    else
        echo -e "${GREEN}✓ QUADS mode: ${mode}${NC}"
    fi

    # Lab validation
    if [[ -z "$lab" ]]; then
        $error_fn "Missing quads.lab" ".quads.lab"
    elif [[ "$lab" != "scalelab" ]] && [[ "$lab" != "performancelab" ]] && [[ "$lab" != "byol" ]]; then
        $error_fn "Invalid quads.lab: ${lab} (valid: scalelab, performancelab, byol)" ".quads.lab"
    fi

    # BYOL mode MUST use import mode
    if [[ "$lab" == "byol" ]] && [[ "$mode" != "import" ]]; then
        $error_fn "BYOL mode requires mode=import (cannot use mode=allocate)" ".quads.mode"
    fi

    # For scalelab/performancelab, QUADS API credentials required
    if [[ "$lab" == "scalelab" ]] || [[ "$lab" == "performancelab" ]]; then
        if [[ -z "$api_server" ]]; then
            $error_fn "Missing quads.api_server (required for ${lab})" ".quads.api_server"
        fi

        if [[ -z "$username" ]]; then
            $error_fn "Missing quads.username (required for ${lab})" ".quads.username"
        fi

        # Authentication - either password or token
        if [[ -z "$password" ]] && [[ -z "$api_token" ]]; then
            $warn_fn "No password or api_token configured (at least one required for ${lab})" ".quads.password"
        fi

        # URL format check - should NOT include scheme
        if [[ -n "$api_server" ]] && [[ "$api_server" =~ ^https?:// ]]; then
            $error_fn "QUADS API server should NOT include scheme (https://). Use hostname:port only. Ansible will add https:// automatically." ".quads.api_server"
        fi
    else
        # BYOL mode
        echo -e "${GREEN}✓ Lab: ${lab} (BYOL - bring your own lab, no QUADS API needed)${NC}"
    fi

    # Mode-specific validation
    if [[ "$mode" == "allocate" ]]; then
        local num_hosts=$(jq -r '.quads.num_hosts // empty' "$config_file")
        local preferred_model=$(jq -r '.quads.preferred_model // empty' "$config_file")
        local workload_name=$(jq -r '.quads.workload_name // empty' "$config_file")

        if [[ -z "$num_hosts" ]]; then
            $error_fn "Missing quads.num_hosts (required for allocate mode)" ".quads.num_hosts"
        fi

        if [[ -z "$preferred_model" ]]; then
            $warn_fn "Missing quads.preferred_model" ".quads.preferred_model"
        fi

        if [[ -z "$workload_name" ]]; then
            $warn_fn "Missing quads.workload_name" ".quads.workload_name"
        fi
    elif [[ "$mode" == "import" ]]; then
        # cloud_name only required for scalelab/performancelab
        if [[ "$lab" != "byol" ]]; then
            local cloud_name=$(jq -r '.quads.cloud_name // empty' "$config_file")
            if [[ -z "$cloud_name" ]]; then
                $error_fn "Missing quads.cloud_name (required for import mode with ${lab})" ".quads.cloud_name"
            fi
        fi
    fi

    return 0
}

# Default error reporter (used by configure scripts)
_default_error() {
    echo -e "${RED}✗ $1${NC}" >&2
    return 1
}

# Default warning reporter (used by configure scripts)
_default_warning() {
    echo -e "${YELLOW}⚠ $1${NC}" >&2
    return 0
}

# Validate Jetlag configuration
# Parameters:
#   $1 - config file path
#   $2 - error reporter function name (optional)
#   $3 - warning reporter function name (optional)
validate_jetlag_config() {
    local config_file="$1"
    local error_fn="${2:-_default_error}"
    local warn_fn="${3:-_default_warning}"

    echo -e "${BLUE}Checking Jetlag configuration...${NC}"

    local quads_mode=$(jq -r '.quads.mode // "allocate"' "$config_file")

    # Allocate mode validation
    if [[ "$quads_mode" == "allocate" ]]; then
        local cluster_type=$(jq -r '.jetlag.cluster_type // empty' "$config_file")
        if [[ -z "$cluster_type" ]]; then
            $error_fn "Missing jetlag.cluster_type (required for allocate mode)" ".jetlag.cluster_type"
        elif [[ "$cluster_type" != "mno" ]] && [[ "$cluster_type" != "sno" ]]; then
            $error_fn "Invalid jetlag.cluster_type: ${cluster_type} (valid: mno, sno)" ".jetlag.cluster_type"
        else
            echo -e "${GREEN}✓ Cluster type: ${cluster_type}${NC}"
        fi

        local ocp_build=$(jq -r '.jetlag.ocp_build // empty' "$config_file")
        local ocp_version=$(jq -r '.jetlag.ocp_version // empty' "$config_file")
        local network_stack=$(jq -r '.jetlag.network_stack // empty' "$config_file")

        [[ -z "$ocp_build" ]] && $error_fn "Missing jetlag.ocp_build (required for allocate mode)" ".jetlag.ocp_build"
        [[ -z "$ocp_version" ]] && $error_fn "Missing jetlag.ocp_version (required for allocate mode)" ".jetlag.ocp_version"
        [[ -z "$network_stack" ]] && $error_fn "Missing jetlag.network_stack (required for allocate mode)" ".jetlag.network_stack"

        # Pull secret validation
        local pull_secret=$(jq -r '.jetlag.pull_secret_path // empty' "$config_file")
        if [[ -n "$pull_secret" ]]; then
            local pull_secret_expanded="${pull_secret/#\~/$HOME}"
            if [[ ! -f "$pull_secret_expanded" ]]; then
                $warn_fn "Pull secret file not found: ${pull_secret}" ".jetlag.pull_secret_path"
            fi
        else
            $warn_fn "Missing jetlag.pull_secret_path (required for allocate mode)" ".jetlag.pull_secret_path"
        fi

        # BMC password check
        local bmc_password=$(jq -r '.jetlag.bmc_password // empty' "$config_file")
        if [[ -z "$bmc_password" ]]; then
            $warn_fn "Missing jetlag.bmc_password (required for bare metal provisioning)" ".jetlag.bmc_password"
        fi
    fi

    # Import mode validation
    if [[ "$quads_mode" == "import" ]]; then
        local bastion_host=$(jq -r '.jetlag.bastion_host // empty' "$config_file")
        local kubeconfig_path=$(jq -r '.jetlag.kubeconfig_path // empty' "$config_file")

        if [[ -z "$bastion_host" ]]; then
            $error_fn "Missing jetlag.bastion_host (required for import mode)" ".jetlag.bastion_host"
        else
            echo -e "${GREEN}✓ Bastion host: ${bastion_host}${NC}"
        fi

        if [[ -z "$kubeconfig_path" ]]; then
            $error_fn "Missing jetlag.kubeconfig_path (required for import mode)" ".jetlag.kubeconfig_path"
        else
            echo -e "${GREEN}✓ Kubeconfig path: ${kubeconfig_path}${NC}"
        fi
    fi

    return 0
}

# Validate Crucible configuration
# Parameters:
#   $1 - config file path
#   $2 - error reporter function name (optional)
#   $3 - warning reporter function name (optional)
validate_crucible_config() {
    local config_file="$1"
    local error_fn="${2:-_default_error}"
    local warn_fn="${3:-_default_warning}"

    echo -e "${BLUE}Checking Crucible configuration...${NC}"

    local controller_target=$(jq -r '.crucible_controller.target // empty' "$config_file")
    if [[ -z "$controller_target" ]]; then
        $error_fn "Missing crucible_controller.target (valid: bastion, other)" ".crucible_controller.target"
    elif [[ "$controller_target" != "bastion" ]] && [[ "$controller_target" != "other" ]]; then
        $error_fn "Invalid crucible_controller.target: ${controller_target} (valid: bastion, other)" ".crucible_controller.target"
    else
        echo -e "${GREEN}✓ Controller target: ${controller_target}${NC}"
    fi

    if [[ "$controller_target" == "other" ]]; then
        local other_host=$(jq -r '.crucible_controller.other_host // empty' "$config_file")
        if [[ -z "$other_host" ]]; then
            $error_fn "Missing crucible_controller.other_host (required when target=other)" ".crucible_controller.other_host"
        fi
    fi

    local crucible_repo=$(jq -r '.crucible.git_repo // empty' "$config_file")
    if [[ -z "$crucible_repo" ]]; then
        $warn_fn "Missing crucible.git_repo" ".crucible.git_repo"
    fi

    return 0
}

# Validate Regulus configuration
# Parameters:
#   $1 - config file path
#   $2 - error reporter function name (optional)
#   $3 - warning reporter function name (optional)
validate_regulus_config() {
    local config_file="$1"
    local error_fn="${2:-_default_error}"
    local warn_fn="${3:-_default_warning}"

    echo -e "${BLUE}Checking Regulus configuration...${NC}"

    local regulus_jobs=$(jq -r '.regulus.jobs // empty' "$config_file")
    if [[ -n "$regulus_jobs" ]]; then
        # Validate jobs syntax - should be space-separated paths starting with ./
        local valid_jobs=true
        for job in $regulus_jobs; do
            if [[ ! "$job" =~ ^\./.*$ ]]; then
                $warn_fn "Invalid job path format: ${job} (must start with './')" ".regulus.jobs"
                echo "  Example: './1_GROUP/NO-PAO/4IP/INTER-NODE/TCP/2-POD'"
                valid_jobs=false
                break
            fi
        done
        [[ "$valid_jobs" == true ]] && echo -e "${GREEN}✓ Jobs: ${regulus_jobs}${NC}"
    else
        echo -e "${YELLOW}ℹ No Regulus jobs configured (will use defaults)${NC}"
    fi

    return 0
}
