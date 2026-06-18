# CLAUDE.md - reg-agent

This file provides guidance to Claude Code when working with the reg-agent codebase.

## Overview

**reg-agent** is an AI-driven CI/CD orchestration system for Regulus performance testing. It automates the complete pipeline from bare metal allocation to test execution and validation.

**Architecture**: 4 modules, 6 execution phases
- Modules 1-3 each correspond to one phase (QUADS, Jetlag, Crucible)
- Module 4 (Regulus) spans 3 phases: setup (Phase 4), execution (Phase 5), validation (Phase 6)

## Project Structure

```
reg-agent/
├── CLAUDE.md                    # This file - main project guide
├── bootstrap.sh                 # One-time setup script
├── Makefile                     # Main orchestration interface
├── config/
│   ├── config.schema.json           # JSON Schema Draft-07
│   ├── validate-config.sh           # Validation orchestrator (sources lib, calls module validators)
│   ├── test-validator-consistency.sh # Validator test suite
│   ├── VALIDATOR-ARCHITECTURE.md    # Validator architecture documentation
│   ├── CONFIG-SCHEMA.md             # Schema documentation
│   ├── orchestrate-config.sh        # Legacy configuration orchestrator
│   ├── sample-config.json           # Example configuration
│   ├── README-AUTO-MODE.md          # Auto-mode documentation
│   └── README-DEPRECATION.md        # Deprecation notices
├── modules/
│   ├── lib/
│   │   ├── check-dependencies.sh  # Dependency checking library
│   │   ├── json-config.sh         # JSON configuration functions
│   │   ├── logging.sh             # Logging utilities
│   │   ├── module-interface.sh    # Module interface functions
│   │   └── validate-config.sh     # Module validators (SINGLE SOURCE OF TRUTH)
│   ├── quads/                   # Module 1 (Phase 1: QUADS)
│   │   └── phase-1-quads-reserve.sh  # Phase 1 orchestration (inside module)
│   ├── jetlag/                  # Module 2 (Phase 2: Jetlag)
│   ├── crucible/                # Module 3 (Phase 3: Crucible)
│   ├── regulus/                 # Module 4 (Phases 4-6: Regulus)
│   # Phase orchestration scripts (called by main Makefile)
│   # Note: Phases 2-6 live at modules/ root for historical reasons
│   # Phase 1 lives inside quads/ module directory (inconsistent but preserved)
│   ├── phase-2-jetlag-deploy.sh   # Phase 2: Jetlag deployment orchestration
│   ├── phase-3-crucible-setup.sh  # Phase 3: Crucible setup orchestration
│   ├── phase-4-regulus-setup.sh   # Phase 4: Regulus setup orchestration
│   ├── phase-5-regulus-run.sh     # Phase 5: Regulus test execution orchestration
│   └── phase-6-validate-results.sh # Phase 6: Results validation orchestration
├── repos/                       # External dependencies (cloned by bootstrap)
│   ├── ansible-quads-ssm/       # QUADS self-service allocation
│   └── jetlag/                  # OpenShift deployment automation
│   # Note: Crucible and Regulus are cloned on bastion, not here
└── vars/
    ├── config.json              # User configuration (JSON format)
    ├── config.json.template     # Template for config.json
    └── state.env                # Pipeline state tracking

```

## Module-Specific Documentation

For focused work on specific modules/phases, refer to these module-specific CLAUDE.md files:

- **Module 1 / Phase 1 (QUADS)**: `modules/quads/CLAUDE.md` - Resource broker for lab infrastructure (allocate, import, validate, deallocate)
- **Module 2 / Phase 2 (Jetlag)**: `modules/jetlag/CLAUDE.md` - OpenShift cluster deployment
- **Module 3 / Phase 3 (Crucible)**: `modules/crucible/CLAUDE.md` - Crucible installation on bastion
- **Module 4 / Phases 4-6 (Regulus)**: `modules/regulus/CLAUDE.md` - Regulus setup (Phase 4), test execution (Phase 5), and result validation (Phase 6)

Note: Modules 1-3 map 1:1 to phases. Module 4 (Regulus) contains 3 phases because testing involves setup, execution, and validation as distinct steps.

## Lab Types and Deployment Modes

reg-agent supports 3 lab types and 2 QUADS modes:

### Lab Types (quads.lab)

1. **scalelab**: Red Hat Scale Lab (requires QUADS API access)
2. **performancelab**: Red Hat Performance Lab (requires QUADS API access)
3. **byol**: Bring Your Own Lab (no QUADS API needed, user provides cluster)

### QUADS Modes (quads.mode)

1. **allocate**: Request new bare metal → Jetlag deploys new cluster → Crucible → Regulus
2. **import**: Import existing resources → Use existing cluster → Crucible → Regulus

### Deployment Flow by Configuration

| Lab Type | Mode | QUADS Phase | Jetlag Phase | Flow |
|----------|------|-------------|--------------|------|
| scalelab/performancelab | allocate | Allocate machines | Deploy cluster | Full deployment |
| scalelab/performancelab | import | Import allocation | Use existing cluster | Reuse cluster |
| byol | import | Skipped (no QUADS API) | Use cluster from config | User-provided cluster |

**Note**: All import modes (including BYOL) require `jetlag.bastion_host` and `jetlag.kubeconfig_path` to be specified in config. BYOL only skips QUADS API fields (api_server, username, password, cloud_name).

**Configuration**: Set in `vars/config.json` (quads.lab and quads.mode)

**Module-level control**: Use `cd modules/<name> && make <target>` for granular operations

## Key Architectural Decisions

### 1. Dependency Checking Framework
**File**: `modules/lib/check-dependencies.sh`

All phases use a common dependency checking library that validates:
- Repositories exist
- Configuration variables are set
- SSH access is available
- Required commands are present
- Remote files/directories exist

### 2. State Management
**File**: `vars/state.env`

Pipeline state is tracked in `vars/state.env`:
- CLOUD_NAME (from Phase 1)
- BASTION_HOST (from Phase 2)
- KUBECONFIG_PATH (from Phase 2)
- CRUCIBLE_PATH (from Phase 3)
- REGULUS_PATH (from Phase 4)
- RUN_ID (from Phase 5)

### 3. Configuration Strategy
**Files**: `vars/config.json`, `config/config.schema.json`, `config/validate-config.sh`

User configuration is separate from state:
- JSON format with schema validation (JSON Schema Draft-07)
- Generated by module-level `configure-json.sh` scripts (interactive) or manual editing
- Contains deployment mode, test selection, credentials
- Never modified by pipeline (only by user)
- Organized by module: `.quads`, `.jetlag`, `.lab`, `.regulus`, etc.

**Validation Architecture (Bottom-Up)**:
- **Single source of truth**: `modules/lib/validate-config.sh` contains all validation logic
  - Module validators: `validate_quads_config()`, `validate_jetlag_config()`, etc.
  - Each module validates its own configuration section
  - Accepts optional callback functions for flexible error/warning reporting
  - Used directly by configure scripts for quick validation
- **Orchestrator**: `config/validate-config.sh` coordinates comprehensive validation
  - Sources `modules/lib/validate-config.sh`
  - Calls each module validator with enhanced reporting (line numbers)
  - Adds cross-module validation (e.g., QUADS hosts vs Jetlag cluster requirements)
  - Adds security checks and final summary
- **Testing**: `config/test-validator-consistency.sh` ensures validators work correctly
- **Documentation**: `config/VALIDATOR-ARCHITECTURE.md` explains architecture

### 4. Phase Independence
Each phase:
- Validates its own dependencies
- Can be run independently using module-level commands
- Clearly outputs what it accomplished
- Updates state.env for next phase

### 5. Intelligent Retry and Timing Handling

**QUADS → Foreman Timing Gap**:
- QUADS marks allocation as "validated" before Foreman completes provisioning
- Foreman needs 1-5 minutes after QUADS validation to create user accounts and configure hosts
- **Solution**: Jetlag create-inventory has intelligent retry logic:
  - Detects Foreman 401 auth errors vs actual failures
  - Retries every 60 seconds for up to 10 minutes
  - Only retries on Foreman timing issues, fails fast on configuration errors

**Bastion Power Management (Stage 1.5)**:
- After QUADS allocation, bastion may be powered off (especially with `wipe_disks="no"`)
- **Two-phase connectivity check**:
  - Phase 1: Ping (wait for network/host up)
  - Phase 2: SSH (wait for OS booted)
- **Power-on methods**:
  - Badfish (Redfish via podman) - modern, no install needed
  - Fallback to ipmitool (IPMI) - legacy compatibility
- **Total timeout**: 10 minutes for full boot cycle

### 6. Resumable Deployment

The `make deploy` command is resumable:
- Checks state files before executing each phase
- Skips completed phases automatically
- Allows fixing configuration errors and re-running without starting over
- Example: QUADS allocated → fix Jetlag config → re-run `make deploy` → skips Phase 1

## Common Commands

```bash
# Initial setup (run once)
./bootstrap.sh

# Configure deployment (per-module interactive helpers)
make -C modules/quads configure      # Configure QUADS (required)
make -C modules/jetlag configure     # Configure Jetlag (optional)
make -C modules/crucible configure   # Configure Crucible (optional)
make -C modules/regulus configure    # Configure Regulus (optional)

# Or use legacy interactive wizard (deprecated)
./config/orchestrate-config.sh

# Deploy based on configuration
make deploy

# Run tests
make run

# Validate results
make validate

# Utilities
make info                # Show detailed status of all modules (recommended)
make status              # Show raw config and state files
make clean               # Remove generated configs and state

# Module-level commands (for granular control)
cd modules/quads && make help          # QUADS module
cd modules/jetlag && make help         # Jetlag module
cd modules/crucible && make help       # Crucible module
cd modules/regulus && make help        # Regulus module
```

## Working on Specific Modules

Each module has its own Makefile and CLAUDE.md documentation.

### When working on Phase 1 (QUADS):
1. Open `modules/quads/CLAUDE.md`
2. Commands: `cd modules/quads && make help`
3. Main targets: `allocate`, `import`, `validate`, `deallocate`

### When working on Phase 2 (Jetlag):
1. Open `modules/jetlag/CLAUDE.md`
2. Commands: `cd modules/jetlag && make help`
3. Main targets: `init`, `deploy`, `validate`

### When working on Phase 3 (Crucible):
1. Open `modules/crucible/CLAUDE.md`
2. Commands: `cd modules/crucible && make help`
3. Main targets: `install`, `validate`

### When working on Phases 4-6 (Regulus module):
1. Open `modules/regulus/CLAUDE.md`
2. Commands: `cd modules/regulus && make help`
3. Main targets: `install` (Phase 4), `run` (Phase 5), `validate` (Phase 6)
4. Note: All three phases operate on the same module directory

## Development Guidelines

### Adding New Dependencies to a Phase
1. Update the phase script's dependency check section
2. Use functions from `modules/lib/check-dependencies.sh`
3. Add clear error messages with fix suggestions

### Modifying State Management
- Only append to `vars/state.env`, never overwrite
- Use format: `VARIABLE_NAME=value`
- Document in phase script what state it creates

### Error Handling
- Use `set -e` at top of all scripts
- Provide color-coded output (RED for errors, GREEN for success)
- Always suggest next steps on failure

## Target Machine

Target machine: Configure via vars/config.json

## Important Notes

- **Never commit secrets**: QUADS passwords, pull secrets go in `vars/config.json` (gitignored)
- **Bootstrap once**: Only run `./bootstrap.sh` once per reg-agent installation
- **Modular testing**: Use module-level commands to test individual phases
- **State persistence**: `vars/state.env` allows resuming from any phase
