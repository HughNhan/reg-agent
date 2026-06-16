#!/bin/bash
# JSON Configuration Helper Library
# Provides safe read-modify-write operations for vars/config.json

# Default config path
CONFIG_JSON="${REG_AGENT_ROOT}/vars/config.json"

#------------------------------------------------------------------------------
# Initialize JSON config file if it doesn't exist
#------------------------------------------------------------------------------
init_json_config() {
    local config_file="${1:-$CONFIG_JSON}"

    if [ ! -f "$config_file" ]; then
        mkdir -p "$(dirname "$config_file")"
        cat > "$config_file" <<'EOF'
{
  "comment": "reg-agent configuration - auto-generated",
  "version": "1.0",
  "deployment_mode": "full",
  "quads": {},
  "lab": {},
  "jetlag": {},
  "crucible_controller": {},
  "crucible": {},
  "regulus": {}
}
EOF
        echo "✓ Initialized $config_file"
    fi
}

#------------------------------------------------------------------------------
# Read value from JSON config
# Usage: json_get ".quads.api_server" "default_value"
#------------------------------------------------------------------------------
json_get() {
    local path="$1"
    local default="${2:-}"
    local config_file="${3:-$CONFIG_JSON}"

    if [ ! -f "$config_file" ]; then
        echo "$default"
        return
    fi

    local value
    value=$(jq -r "${path} // empty" "$config_file" 2>/dev/null)

    if [ -z "$value" ] || [ "$value" = "null" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

#------------------------------------------------------------------------------
# Set value in JSON config (atomic operation)
# Usage: json_set ".quads.api_server" "quads.example.com"
#------------------------------------------------------------------------------
json_set() {
    local path="$1"
    local value="$2"
    local config_file="${3:-$CONFIG_JSON}"

    init_json_config "$config_file"

    local temp_file="${config_file}.tmp.$$"

    # Use jq to set the value
    if jq --arg val "$value" "${path} = \$val" "$config_file" > "$temp_file" 2>/dev/null; then
        mv -f "$temp_file" "$config_file"
        return 0
    else
        rm -f "$temp_file"
        echo "ERROR: Failed to set ${path} in JSON config" >&2
        return 1
    fi
}

#------------------------------------------------------------------------------
# Set multiple values in JSON config (atomic operation)
# Usage: json_set_multi ".quads" api_server="quads.example.com" username="user"
#------------------------------------------------------------------------------
json_set_multi() {
    local section="$1"
    shift
    local config_file="${CONFIG_JSON}"

    # Check if last arg is a file path
    if [[ "${!#}" == /* ]] && [ -f "${!#}" ]; then
        config_file="${!#}"
        set -- "${@:1:$(($#-1))}"
    fi

    init_json_config "$config_file"

    local temp_file="${config_file}.tmp.$$"

    # Build jq expression
    local jq_expr="."
    local jq_args=()

    for arg in "$@"; do
        local key="${arg%%=*}"
        local val="${arg#*=}"
        jq_expr="${jq_expr} | ${section}.${key} = \$${key}"
        jq_args+=(--arg "$key" "$val")
    done

    # Apply update
    if jq "${jq_args[@]}" "$jq_expr" "$config_file" > "$temp_file" 2>/dev/null; then
        mv -f "$temp_file" "$config_file"
        return 0
    else
        rm -f "$temp_file"
        echo "ERROR: Failed to update ${section} in JSON config" >&2
        return 1
    fi
}

#------------------------------------------------------------------------------
# Update entire section (merge object)
# Usage: json_update_section ".quads" '{"api_server":"quads.example.com"}'
#------------------------------------------------------------------------------
json_update_section() {
    local section="$1"
    local json_object="$2"
    local config_file="${3:-$CONFIG_JSON}"

    init_json_config "$config_file"

    local temp_file="${config_file}.tmp.$$"

    # Merge the object into the section
    if jq --argjson obj "$json_object" "${section} = ${section} + \$obj" "$config_file" > "$temp_file" 2>/dev/null; then
        mv "$temp_file" "$config_file"
        return 0
    else
        rm -f "$temp_file"
        echo "ERROR: Failed to update section ${section}" >&2
        return 1
    fi
}

#------------------------------------------------------------------------------
# Validate JSON config
# Usage: json_validate
#------------------------------------------------------------------------------
json_validate() {
    local config_file="${1:-$CONFIG_JSON}"

    if [ ! -f "$config_file" ]; then
        echo "ERROR: Config file not found: $config_file" >&2
        return 1
    fi

    # Check JSON syntax
    if ! jq empty "$config_file" 2>/dev/null; then
        echo "ERROR: Invalid JSON syntax in $config_file" >&2
        return 1
    fi

    # Run full validator if available
    local validator="${REG_AGENT_ROOT}/config/validate-config.sh"
    if [ -f "$validator" ]; then
        "$validator" "$config_file"
        return $?
    fi

    return 0
}

#------------------------------------------------------------------------------
# Pretty-print section of config
# Usage: json_show ".quads"
#------------------------------------------------------------------------------
json_show() {
    local section="${1:-.}"
    local config_file="${2:-$CONFIG_JSON}"

    if [ ! -f "$config_file" ]; then
        echo "{}"
        return
    fi

    jq "$section" "$config_file" 2>/dev/null || echo "{}"
}

#------------------------------------------------------------------------------
# Export config section as environment variables
# Usage: json_export_env ".quads"
# Exports: QUADS_API_SERVER, QUADS_USERNAME, etc.
#------------------------------------------------------------------------------
json_export_env() {
    local section="$1"
    local prefix="${2:-}"
    local config_file="${3:-$CONFIG_JSON}"

    if [ ! -f "$config_file" ]; then
        return 1
    fi

    # Get all keys and values from the section
    local keys
    keys=$(jq -r "${section} | keys[]" "$config_file" 2>/dev/null)

    for key in $keys; do
        # Skip comment keys
        [[ "$key" == _comment* ]] && continue

        local value
        value=$(jq -r "${section}.${key}" "$config_file" 2>/dev/null)

        # Convert key to uppercase and add prefix
        local env_key
        if [ -n "$prefix" ]; then
            env_key="${prefix}_${key}"
        else
            env_key="$key"
        fi
        env_key=$(echo "$env_key" | tr '[:lower:]' '[:upper:]')

        # Export variable
        export "$env_key=$value"
    done
}
