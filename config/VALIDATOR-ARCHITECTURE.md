# Validator Architecture

## Design Philosophy

**Bottom-Up Modular Validation**: Each module validates its own configuration section. The top-level orchestrator coordinates module validators and adds cross-module checks.

There is **ONE source of truth** for validation logic: `modules/lib/validate-config.sh`

## Architecture Overview

```
modules/lib/validate-config.sh (SINGLE SOURCE OF TRUTH)
├─ Basic field validators (validate_required, validate_choice, etc.)
├─ Module validators (each module validates its own section):
│   ├─ validate_quads_config(config_file, error_fn, warn_fn)
│   ├─ validate_jetlag_config(config_file, error_fn, warn_fn)
│   ├─ validate_crucible_config(config_file, error_fn, warn_fn)
│   └─ validate_regulus_config(config_file, error_fn, warn_fn)
└─ Default reporters (_default_error, _default_warning)

config/validate-config.sh (ORCHESTRATOR)
├─ Sources modules/lib/validate-config.sh
├─ Provides enhanced reporting (report_error, report_warning with line numbers)
├─ Calls each module validator with reporting callbacks
├─ Cross-module validation (e.g., QUADS hosts vs Jetlag requirements)
├─ Lab configuration checks
├─ Security checks (placeholder detection)
└─ Summary and exit codes
```

## Two Components, One Logic

### 1. Module Validators (`modules/lib/validate-config.sh`)
- **Purpose**: Single source of truth for all validation logic
- **Features**:
  - Each module validates its own configuration section
  - Accepts callback functions for flexible error/warning reporting
  - Used directly by configure scripts (simple reporting)
  - Used by orchestrator (enhanced reporting with line numbers)
- **Used by**:
  - Configure scripts: `modules/*/configure-json.sh`
  - Top-level orchestrator: `config/validate-config.sh`
- **Characteristics**:
  - Sourced by other scripts
  - Module validators contain complete validation logic
  - Callback pattern allows different reporting modes
  - No code duplication

### 2. Validation Orchestrator (`config/validate-config.sh`)
- **Purpose**: Coordinate comprehensive validation with enhanced reporting
- **Features**:
  - Line number tracking for errors/warnings
  - Formatted output with colors
  - Cross-module validation
  - Security checks
- **Used by**: `make validate-config`, deployment pipeline
- **Characteristics**:
  - Sources `modules/lib/validate-config.sh`
  - Calls module validators with enhanced reporters
  - Does NOT duplicate validation logic
  - Adds orchestration-specific checks

## Callback Pattern for Flexible Reporting

Module validators accept optional callback functions:

```bash
validate_quads_config() {
    local config_file="$1"
    local error_fn="${2:-_default_error}"    # Default: simple echo
    local warn_fn="${3:-_default_warning}"   # Default: simple echo

    # Use callbacks for reporting
    $error_fn "Missing quads.api_server" ".quads.api_server"
    $warn_fn "Missing pull secret" ".jetlag.pull_secret_path"
}
```

### Simple Mode (used by configure scripts)
```bash
source modules/lib/validate-config.sh
validate_quads_config "vars/config.json"
# Uses _default_error and _default_warning (no line numbers)
```

### Enhanced Mode (used by orchestrator)
```bash
source modules/lib/validate-config.sh
validate_quads_config "$CONFIG_FILE" "report_error" "report_warning"
# Uses report_error/report_warning with line number lookup
```

## Validation Rules by Module

### QUADS Module (`validate_quads_config`)
- **Mode validation**: allocate or import
- **Lab validation**: scalelab, performancelab, or byol
- **BYOL mode**: Bypasses QUADS API requirements (no api_server, username, etc.)
- **Scalelab/Performancelab**: Requires api_server, username, password/token
- **Allocate mode**: Requires num_hosts, preferred_model, workload_name
- **Import mode**: Requires cloud_name (except for BYOL)

### Jetlag Module (`validate_jetlag_config`)
- **Allocate mode**: Requires cluster_type, ocp_build, ocp_version, network_stack, pull_secret_path, bmc_password
- **Import mode**: Requires bastion_host, kubeconfig_path
- **Note**: cluster_type NOT required for import (Regulus auto-discovers)

### Crucible Module (`validate_crucible_config`)
- Controller target validation (bastion or other)
- Git repository validation
- Other host required when target=other

### Regulus Module (`validate_regulus_config`)
- Jobs syntax validation (paths must start with './')
- Duration and num_samples validation

### Cross-Module Validation (in orchestrator)
- QUADS hosts vs Jetlag cluster requirements (MNO mode)
- Lab configuration completeness
- Security checks (placeholder detection)

## Testing

Run `config/test-validator-consistency.sh` to verify validators work correctly:

```bash
./config/test-validator-consistency.sh
```

Tests validate:
1. BYOL mode (import with no QUADS API)
2. Scalelab allocate mode (full deployment)
3. Performancelab import mode (existing cluster)

## Modifying Validation Rules

When adding/changing validation rules:

1. **Update module validator** in `modules/lib/validate-config.sh`
   - Add checks to appropriate `validate_*_config()` function
   - Use callback functions for error/warning reporting

2. **Run consistency test**:
   ```bash
   ./config/test-validator-consistency.sh
   ```

3. **Update schema** (`config/config.schema.json`)
   - Keep JSON schema in sync with validators

4. **Test both modes**:
   ```bash
   # Test configure script usage
   cd modules/quads
   ./configure-json.sh

   # Test orchestrator usage
   ./config/validate-config.sh vars/config.json
   ```

## Example: Adding New Field Validation

```bash
# 1. Add to module validator (modules/lib/validate-config.sh)
validate_quads_config() {
    local config_file="$1"
    local error_fn="${2:-_default_error}"
    local warn_fn="${3:-_default_warning}"

    # ... existing validation ...

    # Add new field validation
    local new_field=$(jq -r '.quads.new_field // empty' "$config_file")
    if [[ -z "$new_field" ]]; then
        $error_fn "Missing quads.new_field" ".quads.new_field"
    fi
}

# 2. Update schema (config/config.schema.json)
"new_field": {
  "type": "string",
  "description": "Description of new field"
}

# 3. Test
./config/test-validator-consistency.sh
./config/validate-config.sh vars/config.json
```

## Benefits of This Architecture

1. **Bottom-up design**: Modules validate their own sections ✅
2. **Single source of truth**: All validation logic in `modules/lib/validate-config.sh` ✅
3. **No code duplication**: ~400 lines of duplicate code eliminated ✅
4. **Flexible reporting**: Simple for configure scripts, enhanced for orchestrator ✅
5. **Maintainable**: Changes to validation rules happen in ONE place ✅
6. **Testable**: Module validators can be tested independently ✅
7. **Best of both worlds**:
   - Interactive validation during configure prompts
   - Comprehensive reporting with line numbers
   - Cross-module validation in orchestrator

## Migration Notes

**Previous Architecture** (Top-Down):
- `config/validate-config.sh` contained all validation logic inline
- `modules/lib/validate-config.sh` had duplicate validation logic
- ~400 lines of code duplication

**Current Architecture** (Bottom-Up):
- `modules/lib/validate-config.sh` contains single source of truth
- `config/validate-config.sh` sources library and calls module validators
- Zero code duplication
- Each module validates its own configuration section
