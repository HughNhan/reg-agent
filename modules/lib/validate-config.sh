#!/bin/bash
# Configuration validation library
# Provides validation functions for user input and final configuration

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
#------------------------------------------------------------------------------

# Validate QUADS configuration
validate_quads_config() {
    local config_file="$1"
    local errors=0

    echo -e "${YELLOW}Validating QUADS configuration...${NC}"

    # Required fields
    local mode=$(jq -r '.quads.mode // ""' "$config_file")
    local api_server=$(jq -r '.quads.api_server // ""' "$config_file")
    local username=$(jq -r '.quads.username // ""' "$config_file")
    local lab=$(jq -r '.quads.lab // ""' "$config_file")
    local password=$(jq -r '.quads.password // ""' "$config_file")
    local api_token=$(jq -r '.quads.api_token // ""' "$config_file")

    # Validate mode
    if ! validate_choice "$mode" "QUADS mode" "allocate" "import"; then
        ((errors++))
    fi

    # Validate required fields
    if ! validate_required "$api_server" "QUADS API server"; then
        ((errors++))
    fi
    if ! validate_required "$username" "QUADS username"; then
        ((errors++))
    fi
    if ! validate_required "$lab" "QUADS lab"; then
        ((errors++))
    fi

    # Either password or token required
    if [[ -z "$password" ]] && [[ -z "$api_token" ]]; then
        echo -e "${RED}✗ Either QUADS password or API token is required${NC}"
        ((errors++))
    fi

    # Mode-specific validation
    if [[ "$mode" == "import" ]]; then
        local cloud_name=$(jq -r '.quads.cloud_name // ""' "$config_file")
        if ! validate_required "$cloud_name" "Cloud name (required for import)"; then
            ((errors++))
        elif ! validate_cloud_name "$cloud_name" "Cloud name"; then
            ((errors++))
        fi
    elif [[ "$mode" == "allocate" ]]; then
        local num_hosts=$(jq -r '.quads.num_hosts // ""' "$config_file")
        if ! validate_required "$num_hosts" "Number of hosts (required for allocate)"; then
            ((errors++))
        elif ! validate_positive_int "$num_hosts" "Number of hosts"; then
            ((errors++))
        fi
    fi

    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}✓ QUADS configuration valid${NC}"
        return 0
    else
        echo -e "${RED}✗ QUADS configuration has $errors error(s)${NC}"
        return 1
    fi
}

# Validate Jetlag configuration
validate_jetlag_config() {
    local config_file="$1"
    local errors=0

    echo -e "${YELLOW}Validating Jetlag configuration...${NC}"

    # Check if QUADS is in import mode
    local quads_mode=$(jq -r '.quads.mode // ""' "$config_file")

    if [[ "$quads_mode" == "import" ]]; then
        # Import mode: Only bastion and kubeconfig required
        local bastion_host=$(jq -r '.jetlag.bastion_host // ""' "$config_file")
        local kubeconfig_path=$(jq -r '.jetlag.kubeconfig_path // ""' "$config_file")

        if ! validate_required "$bastion_host" "Bastion host"; then
            ((errors++))
        elif ! validate_hostname "$bastion_host" "Bastion host"; then
            ((errors++))
        fi

        if ! validate_required "$kubeconfig_path" "Kubeconfig path"; then
            ((errors++))
        fi
    else
        # Allocate mode: Deployment parameters required
        local cluster_type=$(jq -r '.jetlag.cluster_type // ""' "$config_file")
        local worker_count=$(jq -r '.jetlag.worker_node_count // ""' "$config_file")
        local ocp_build=$(jq -r '.jetlag.ocp_build // ""' "$config_file")
        local ocp_version=$(jq -r '.jetlag.ocp_version // ""' "$config_file")

        if ! validate_choice "$cluster_type" "Cluster type" "sno" "mno" "bm"; then
            ((errors++))
        fi

        if ! validate_non_negative_int "$worker_count" "Worker node count"; then
            ((errors++))
        fi

        if ! validate_choice "$ocp_build" "OCP build" "ga" "nightly" "rc"; then
            ((errors++))
        fi

        if ! validate_required "$ocp_version" "OCP version"; then
            ((errors++))
        fi
    fi

    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}✓ Jetlag configuration valid${NC}"
        return 0
    else
        echo -e "${RED}✗ Jetlag configuration has $errors error(s)${NC}"
        return 1
    fi
}

# Validate Crucible configuration
validate_crucible_config() {
    local config_file="$1"
    local errors=0

    echo -e "${YELLOW}Validating Crucible configuration...${NC}"

    local git_repo=$(jq -r '.crucible.git_repo // ""' "$config_file")
    local git_branch=$(jq -r '.crucible.git_branch // ""' "$config_file")

    if ! validate_required "$git_repo" "Crucible git repo"; then
        ((errors++))
    elif ! validate_url "$git_repo" "Crucible git repo"; then
        ((errors++))
    fi

    if ! validate_required "$git_branch" "Crucible git branch"; then
        ((errors++))
    fi

    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}✓ Crucible configuration valid${NC}"
        return 0
    else
        echo -e "${RED}✗ Crucible configuration has $errors error(s)${NC}"
        return 1
    fi
}

# Validate Regulus configuration
validate_regulus_config() {
    local config_file="$1"
    local errors=0

    echo -e "${YELLOW}Validating Regulus configuration...${NC}"

    local jobs=$(jq -r '.regulus.jobs // ""' "$config_file")
    local duration=$(jq -r '.regulus.duration // ""' "$config_file")
    local num_samples=$(jq -r '.regulus.num_samples // ""' "$config_file")

    if ! validate_required "$jobs" "Regulus jobs"; then
        ((errors++))
    fi

    if ! validate_positive_int "$duration" "Test duration"; then
        ((errors++))
    fi

    if ! validate_positive_int "$num_samples" "Number of samples"; then
        ((errors++))
    fi

    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}✓ Regulus configuration valid${NC}"
        return 0
    else
        echo -e "${RED}✗ Regulus configuration has $errors error(s)${NC}"
        return 1
    fi
}

# Validate entire configuration file
validate_all_config() {
    local config_file="$1"
    local errors=0

    echo ""
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "${YELLOW}Configuration Validation${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    echo ""

    if ! validate_quads_config "$config_file"; then
        ((errors++))
    fi
    echo ""

    if ! validate_jetlag_config "$config_file"; then
        ((errors++))
    fi
    echo ""

    if ! validate_crucible_config "$config_file"; then
        ((errors++))
    fi
    echo ""

    if ! validate_regulus_config "$config_file"; then
        ((errors++))
    fi
    echo ""

    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}=========================================${NC}"
        echo -e "${GREEN}All validations passed!${NC}"
        echo -e "${GREEN}=========================================${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}=========================================${NC}"
        echo -e "${RED}Validation failed with $errors error(s)${NC}"
        echo -e "${RED}=========================================${NC}"
        echo ""
        echo "Please fix the errors above and try again."
        echo ""
        return 1
    fi
}
