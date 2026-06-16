# Configuration Refactoring - Modular Architecture

## What Changed

The monolithic `prompt-config.sh` has been replaced with a **modular configuration architecture** where each module manages its own configuration.

### Old Architecture (Deprecated)

```
config/
└── prompt-config.sh          # Monolithic - asks for everything
```

- Single script knew about all modules
- Tightly coupled
- Hard to extend
- Required manual updates when adding modules

### New Architecture (Current)

```
modules/
├── quads/
│   ├── interface.sh          # Declares: requires=[], provides=[CLOUD_NAME, LAB, ...]
│   └── setup-config.sh       # Collects QUADS-specific config
├── jetlag/
│   ├── interface.sh          # Declares: requires=[CLOUD_NAME, LAB], provides=[BASTION_HOST, ...]
│   └── setup-config.sh       # Collects Jetlag-specific config
├── crucible/
│   ├── interface.sh          # Declares: requires=[BASTION_HOST], provides=[CRUCIBLE_PATH]
│   └── setup-config.sh       # Collects Crucible-specific config
├── regulus/
│   ├── interface.sh          # Declares: requires=[BASTION_HOST, CRUCIBLE_PATH], provides=[REGULUS_PATH]
│   └── setup-config.sh       # Collects Regulus-specific config
└── lib/
    └── module-interface.sh   # Helper functions for loading/validating interfaces

config/
└── orchestrate-config.sh     # Orchestrator - calls modules in sequence
```

- Each module is self-contained
- Clear dependency graph (via `interface.sh`)
- Easy to add new modules
- Modules collect only their own configuration
- Orchestrator passes outputs from one module as inputs to the next

## Module Interface Definition

Each module now has an `interface.sh` that declares:

1. **What it requires** (inputs from previous modules)
2. **What it provides** (outputs for next modules)
3. **What configuration it needs** (from user)
4. **What modes it supports** (allocate, import, deploy, etc.)

Example (`modules/jetlag/interface.sh`):

```bash
# What this module requires
MODULE_REQUIRES=(
    "CLOUD_NAME"           # From QUADS module
    "LAB"                  # From QUADS module
)

# What this module provides
MODULE_PROVIDES=(
    "BASTION_HOST"         # For Crucible and Regulus
    "KUBECONFIG_PATH"      # For Regulus
    "CLUSTER_TYPE"         # For Regulus
)

# What configuration it needs from user
MODULE_CONFIG_VARS=(
    "CLUSTER_TYPE"         # mno or sno
    "OCP_BUILD"            # ga, dev, or ci
    "OCP_VERSION"          # e.g., latest-4.20
    "NETWORK_STACK"        # ipv4, ipv6, or dual
)
```

## Orchestration Flow

The new `orchestrate-config.sh`:

1. Determines deployment mode (full or cluster-ready)
2. Gets list of modules needed for that mode
3. For each module in order:
   - Loads module's interface
   - Checks if required inputs are available
   - Calls module's `setup-config.sh`
   - Verifies module provided its outputs
   - Passes outputs to next module

## Benefits

### For Users
- Clearer configuration flow
- Better error messages (knows exactly what's missing)
- Can configure modules independently

### For Developers
- Easy to add new modules
- No need to modify central orchestrator
- Clear contracts between modules
- Better testability

## Migration Guide

### If you were using `prompt-config.sh` directly

**Old way:**
```bash
./config/prompt-config.sh
```

**New way:**
```bash
make configure
# Or directly:
./config/orchestrate-config.sh
```

The new orchestrator works the same way - it just calls modules in sequence instead of doing everything itself.

### If you were extending `prompt-config.sh`

**Old way:**
- Edit `config/prompt-config.sh`
- Add prompts for your new variables
- Handle both interactive and JSON modes
- Update all the conditionals

**New way:**
1. Create your module:
   ```bash
   modules/mymodule/
   ├── interface.sh       # Declare requirements and outputs
   └── setup-config.sh    # Collect configuration
   ```

2. Add to module list in `modules/lib/module-interface.sh`:
   ```bash
   get_module_order() {
       echo "quads jetlag crucible regulus mymodule"
   }
   ```

3. Done! The orchestrator will automatically call your module.

## Deprecated Files

These files are kept for reference but should not be used:

- `config/prompt-config.sh.deprecated` - Old monolithic config script
- `config/orchestrate-config-old.sh.backup` - Backup of previous orchestrator

## Developer Commands

### Show module interface
```bash
# Load interface lib
source modules/lib/module-interface.sh

# Show interface for a module
show_module_interface jetlag
```

### Check module requirements
```bash
# Check if module's inputs are available
check_module_requirements jetlag
```

### Get modules for deployment mode
```bash
# Get modules for full deployment
get_modules_for_mode full
# Output: quads jetlag crucible regulus

# Get modules for cluster-ready
get_modules_for_mode cluster-ready
# Output: crucible regulus
```

## Questions?

See the module-specific CLAUDE.md files:
- `modules/quads/CLAUDE.md`
- `modules/jetlag/CLAUDE.md`
- `modules/crucible/CLAUDE.md`
- `modules/regulus/CLAUDE.md`

Or the main documentation:
- `CLAUDE.md` (root project documentation)
