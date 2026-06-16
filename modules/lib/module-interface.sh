#!/bin/bash
# Module Interface Library
# Functions for loading and validating module interfaces

# Load a module's interface definition
# Usage: load_module_interface <module_name>
load_module_interface() {
    local module="$1"
    local interface_file="${REG_AGENT_ROOT}/modules/${module}/interface.sh"

    if [ ! -f "$interface_file" ]; then
        echo "ERROR: Module interface not found: $interface_file" >&2
        return 1
    fi

    # Clear any previous module variables
    unset MODULE_NAME MODULE_DESCRIPTION MODULE_PHASE
    unset MODULE_REQUIRES MODULE_PROVIDES
    unset MODULE_CONFIG_VARS MODULE_OPTIONAL_VARS
    unset MODULE_MODES

    # Source the interface
    source "$interface_file"

    return 0
}

# Check if a module's required inputs are available
# Usage: check_module_requirements <module_name>
check_module_requirements() {
    local module="$1"

    if ! load_module_interface "$module"; then
        return 1
    fi

    local missing=()

    # Check each required variable
    for var in "${MODULE_REQUIRES[@]}"; do
        if [ -z "${!var}" ]; then
            missing+=("$var")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "ERROR: Module '$module' missing required inputs:" >&2
        for var in "${missing[@]}"; do
            echo "  - $var" >&2
        done
        return 1
    fi

    return 0
}

# Check if a module's configuration is complete
# Usage: check_module_config <module_name>
check_module_config() {
    local module="$1"

    if ! load_module_interface "$module"; then
        return 1
    fi

    local missing=()

    # Check each required config variable
    for var in "${MODULE_CONFIG_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            missing+=("$var")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "ERROR: Module '$module' missing required configuration:" >&2
        for var in "${missing[@]}"; do
            echo "  - $var" >&2
        done
        return 1
    fi

    return 0
}

# Show module interface information
# Usage: show_module_interface <module_name>
show_module_interface() {
    local module="$1"

    if ! load_module_interface "$module"; then
        return 1
    fi

    echo "Module: $MODULE_NAME (Phase $MODULE_PHASE)"
    echo "Description: $MODULE_DESCRIPTION"
    echo ""

    if [ ${#MODULE_REQUIRES[@]} -gt 0 ]; then
        echo "Requires (inputs):"
        for var in "${MODULE_REQUIRES[@]}"; do
            if [ -n "${!var}" ]; then
                echo "  ✓ $var = ${!var}"
            else
                echo "  ✗ $var (not set)"
            fi
        done
        echo ""
    fi

    if [ ${#MODULE_PROVIDES[@]} -gt 0 ]; then
        echo "Provides (outputs):"
        for var in "${MODULE_PROVIDES[@]}"; do
            if [ -n "${!var}" ]; then
                echo "  ✓ $var = ${!var}"
            else
                echo "  - $var (will be set)"
            fi
        done
        echo ""
    fi

    if [ ${#MODULE_CONFIG_VARS[@]} -gt 0 ]; then
        echo "Required configuration:"
        for var in "${MODULE_CONFIG_VARS[@]}"; do
            if [ -n "${!var}" ]; then
                # Don't show passwords
                if [[ "$var" == *PASSWORD* ]] || [[ "$var" == *TOKEN* ]]; then
                    echo "  ✓ $var = ***"
                else
                    echo "  ✓ $var = ${!var}"
                fi
            else
                echo "  ✗ $var (not set)"
            fi
        done
        echo ""
    fi

    if [ ${#MODULE_OPTIONAL_VARS[@]} -gt 0 ]; then
        echo "Optional configuration:"
        for var in "${MODULE_OPTIONAL_VARS[@]}"; do
            if [ -n "${!var}" ]; then
                if [[ "$var" == *PASSWORD* ]] || [[ "$var" == *TOKEN* ]]; then
                    echo "  ✓ $var = ***"
                else
                    echo "  ✓ $var = ${!var}"
                fi
            else
                echo "  - $var (optional)"
            fi
        done
        echo ""
    fi

    if [ ${#MODULE_MODES[@]} -gt 0 ]; then
        echo "Supported modes:"
        for mode in "${MODULE_MODES[@]}"; do
            echo "  - $mode"
        done
        echo ""
    fi
}

# Get list of all modules in dependency order
# Usage: get_module_order
get_module_order() {
    echo "quads jetlag crucible regulus"
}

# Get list of modules for a specific deployment mode
# Usage: get_modules_for_mode <deploy_mode>
get_modules_for_mode() {
    local mode="$1"

    case "$mode" in
        full)
            echo "quads jetlag crucible regulus"
            ;;
        cluster-ready)
            echo "crucible regulus"
            ;;
        *)
            echo "ERROR: Unknown deployment mode: $mode" >&2
            return 1
            ;;
    esac
}
