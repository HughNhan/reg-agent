# reg-agent

**CI/CD Orchestrator for Regulus Performance Testing on OpenShift**

Automates the complete pipeline from bare metal allocation to cluster deployment, performance test execution, and result validation.

## Overview

reg-agent orchestrates a 4-module pipeline that executes in 6 phases:

**Modules** (organizational units):
1. **QUADS** - Allocate bare metal from Red Hat performance labs (scalelab/performancelab)
2. **Jetlag** - Deploy OpenShift cluster (MNO/SNO) on allocated hardware
3. **Crucible** - Install performance benchmark framework on bastion host
4. **Regulus** - Execute performance tests and collect results

**Phases** (execution steps):
- Phase 1: QUADS allocation
- Phase 2: Jetlag cluster deployment
- Phase 3: Crucible installation
- Phase 4: Regulus setup
- Phase 5: Regulus test execution
- Phase 6: Results validation

Note: The Regulus module spans phases 4-6 (setup, run, validate)

## How to Use

### Quick Start

**Option 1: Complete pipeline (one command)**
```bash
# 1. Clone and bootstrap
git clone https://github.com/HughNhan/reg-agent.git
cd reg-agent
./bootstrap.sh

# 2. Configure QUADS (minimum requirement)
make -C modules/quads configure

# 3. Run complete pipeline: deploy + run + validate
make all
```

**Option 2: Step-by-step (for debugging/control)**
```bash
# 1. Clone and bootstrap
git clone https://github.com/HughNhan/reg-agent.git
cd reg-agent
./bootstrap.sh

# 2. Configure - Build vars/config.json using interactive helpers
make -C modules/quads configure      # Configure QUADS allocation (required)
make -C modules/jetlag configure     # Configure cluster deployment (optional)
make -C modules/crucible configure   # Configure Crucible setup (optional)
make -C modules/regulus configure    # Configure test execution (optional)

# 3. Run the pipeline step-by-step
make deploy          # Deploy infrastructure
make run             # Execute tests
make validate        # Validate results
```

**What `make all` does**: Runs `deploy`, `run`, and `validate` targets sequentially in a single command. Does NOT include configuration - you must configure first.

### Configuration Methods

**Method 1: Interactive helpers (Recommended)**
```bash
# Each module has an interactive configure script that builds config.json
make -C modules/quads configure      # Required - sets up QUADS allocation
make -C modules/jetlag configure     # Optional - uses smart defaults
make -C modules/crucible configure   # Optional - uses smart defaults
make -C modules/regulus configure    # Optional - uses smart defaults
```

**Method 2: Manual JSON editing**
```bash
# Copy template and edit
cp vars/config.json.template vars/config.json
vim vars/config.json

# Validate before deploying
./config/validate-config.sh vars/config.json
```

The interactive helpers create a combined `vars/config.json` that all modules read from.

## Key Features

### JSON Configuration Architecture
- **Schema-validated** configuration using JSON Schema Draft-07
- **Type safety** - Numeric values, enums, required fields enforced
- **Modular organization** - Settings grouped by module (`.quads`, `.jetlag`, `.regulus`)
- **Interactive helpers** - Per-module `configure` targets generate valid config
- **Modular validation** - Each module validates its own section, orchestrator provides comprehensive reporting

### Intelligent Retry Logic
- **Foreman timing gap handling** - Auto-retry when QUADS validates before Foreman completes provisioning
- **Bastion power management** - Automatic power-on via badfish (Redfish) or ipmitool (IPMI)
- **Smart detection** - Ping → SSH verification before proceeding
- **Fast failure** - Distinguishes timing issues from configuration errors

### Resumable Deployments
- **State tracking** - Each module saves completion state
- **Auto-skip** - Re-running `make deploy` skips completed phases
- **Error recovery** - Fix configuration and resume without restarting from scratch

### Deployment Modes
- **Full** - Complete pipeline: QUADS → Jetlag → Crucible → Regulus
- **Cluster-ready** - Skip infrastructure, use existing cluster

### Modular Architecture
- Each module has independent Makefile and configuration
- Can run phases individually for debugging
- Module-specific documentation in `modules/*/CLAUDE.md`

## Advanced Usage

### Using Existing Cluster (Import Mode)

Set `quads.mode` to `import` in `vars/config.json` and provide existing cluster details.

**For scalelab/performancelab clusters:**
```json
{
  "quads": {
    "mode": "import",
    "api_server": "quads.example.com",
    "username": "your-username",
    "password": "your-password",
    "lab": "scalelab",
    "cloud_name": "cloud04"
  },
  "jetlag": {
    "bastion_host": "cloud04-h01-000-r750.example.com",
    "kubeconfig_path": "/root/mno/kubeconfig"
  }
}
```

**For BYOL (bring your own lab) clusters:**
```json
{
  "quads": {
    "mode": "import",
    "lab": "byol"
  },
  "jetlag": {
    "bastion_host": "your-bastion.example.com",  // REQUIRED
    "kubeconfig_path": "/root/kubeconfig"        // REQUIRED
  }
}
```

**Important**: BYOL mode skips QUADS API calls (no api_server/username/password needed), but the `jetlag` section with `bastion_host` and `kubeconfig_path` is **required** to specify your existing cluster location.

Then run:
```bash
make deploy  # QUADS imports state, Jetlag validates cluster, Crucible + Regulus deploy
make run validate
```

### Module-Level Operations

Each module can be operated independently:

```bash
# QUADS operations
cd modules/quads
make help
make allocate          # Allocate new hardware
make import            # Import existing cloud
make validate          # Check allocation status
make deallocate        # Release hardware

# Jetlag operations
cd modules/jetlag
make help
make deploy            # Deploy cluster
make validate          # Verify cluster access

# Crucible operations
cd modules/crucible
make help
make install           # Install on bastion
make validate          # Verify installation

# Regulus operations
cd modules/regulus
make help
make install           # Install and configure
make run               # Execute tests
make validate          # Check results
```

## Configuration

### vars/config.json Structure

```json
{
  "quads": {
    "mode": "allocate",
    "api_server": "quads.example.com",
    "username": "your-username",
    "password": "your-password",
    "num_hosts": 6,
    "lab": "scalelab",
    "preferred_model": "r750",
    "workload_name": "regulus-testing"
  },

  "lab": {
    "ssh_username": "root",
    "ssh_password": "optional"
  },

  "jetlag": {
    "cluster_type": "mno",
    "worker_node_count": 3,
    "ocp_version": "latest-4.20",
    "ocp_build": "ga",
    "network_stack": "ipv4"
  },

  "crucible": {
    "git_repo": "https://github.com/perftool-incubator/crucible.git",
    "git_branch": "master"
  },

  "crucible_controller": {
    "target": "bastion",
    "user": "root"
  },

  "regulus": {
    "jobs": "./1_GROUP/NO-PAO/4IP/INTER-NODE/TCP/2-POD",
    "duration": 60,
    "num_samples": 3,
    "tag": "REG-AGENT"
  }
}
```

**Note**: Lab name is specified in `quads.lab` (e.g., "scalelab", "performancelab", "byol"). The separate `lab` section only contains SSH credentials that apply to all lab machines.

**Crucible Controller Options**:
- `target: "bastion"` - Install Crucible on the Jetlag bastion host (default, recommended)
- `target: "other"` - Install Crucible on a different host (requires `other_host` field)

Example using a custom controller host:
```json
{
  "crucible_controller": {
    "target": "other",
    "other_host": "my-controller.example.com",
    "user": "root",
    "password": "optional-if-using-ssh-keys"
  }
}
```

### Interactive Configuration

Each module provides an interactive configuration helper:

```bash
# Configure QUADS settings
make -C modules/quads configure

# Configure Jetlag settings
make -C modules/jetlag configure

# Configure Crucible settings
make -C modules/crucible configure

# Configure Regulus test settings
make -C modules/regulus configure
```

These helpers update `vars/config.json` with validated values.

## Components

### External Dependencies

**On reg-agent machine (under `repos/`):**
- `repos/ansible-quads-ssm/` - QUADS self-service allocation
- `repos/jetlag/` - OpenShift deployment automation

**On crucible controller host (bastion):**
- `crucible/` - Performance benchmark framework (cloned directly on bastion)
- `regulus/` - Performance test suite (cloned directly on bastion)

### Module Structure

Each module follows a consistent pattern:

```
modules/<module-name>/
├── Makefile              # Module operations (init, deploy, validate, clean)
├── CLAUDE.md             # Module-specific documentation
├── configure-json.sh     # Interactive JSON configuration helper
├── <module>-*.sh         # Implementation scripts
└── generated/            # Module state and logs (gitignored)
    ├── state/
    ├── logs/
    └── output/
```

## Requirements

- Bash 4.0+
- Python 3.9+ (for Jetlag/Crucible)
- Ansible 2.9+ (for Jetlag)
- jq (for JSON manipulation)
- SSH access to lab infrastructure
- QUADS account (for lab allocation)
- OpenShift pull secret

## Directory Structure

```
reg-agent/
├── README.md                    # This file
├── CLAUDE.md                    # Developer documentation
├── SECURITY.md                  # Security policy
├── bootstrap.sh                 # One-time setup script
├── Makefile                     # Main orchestration
│
├── modules/
│   ├── lib/                     # Shared libraries
│   │   ├── check-dependencies.sh # Dependency checking library
│   │   ├── json-config.sh        # JSON configuration functions
│   │   ├── logging.sh            # Logging utilities
│   │   ├── module-interface.sh   # Module interface functions
│   │   └── validate-config.sh    # Module validators (single source of truth)
│   │
│   ├── quads/                   # Phase 1: Bare metal allocation
│   │   ├── Makefile
│   │   ├── CLAUDE.md
│   │   ├── configure-json.sh
│   │   ├── phase-1-quads-reserve.sh  # Phase 1 orchestration (inside module)
│   │   ├── quads-ssm-reserve.sh
│   │   └── quads-ssm-import.sh
│   │
│   ├── jetlag/                  # Phase 2: Cluster deployment
│   │   ├── Makefile
│   │   ├── CLAUDE.md
│   │   ├── configure-json.sh
│   │   └── setup-config.sh
│   │
│   ├── crucible/                # Phase 3: Benchmark framework
│   │   ├── Makefile
│   │   ├── CLAUDE.md
│   │   └── configure-json.sh
│   │
│   ├── regulus/                 # Phase 4-6: Test execution
│   │   ├── Makefile
│   │   ├── CLAUDE.md
│   │   ├── configure-json.sh
│   │   └── configure-tests.sh
│   │
│   # Phase orchestration scripts (called by main Makefile)
│   # Note: Phases 2-6 live at modules/ root for historical reasons
│   # Phase 1 lives inside quads/ module (see above)
│   ├── phase-2-jetlag-deploy.sh   # Phase 2: Jetlag deployment orchestration
│   ├── phase-3-crucible-setup.sh  # Phase 3: Crucible setup orchestration
│   ├── phase-4-regulus-setup.sh   # Phase 4: Regulus setup orchestration
│   ├── phase-5-regulus-run.sh     # Phase 5: Regulus test execution orchestration
│   └── phase-6-validate-results.sh # Phase 6: Results validation orchestration
│
├── config/
│   ├── config.schema.json           # JSON Schema Draft-07
│   ├── validate-config.sh           # Validation orchestrator (calls module validators)
│   ├── test-validator-consistency.sh # Validator test suite
│   ├── VALIDATOR-ARCHITECTURE.md    # Validator architecture documentation
│   ├── CONFIG-SCHEMA.md             # Schema documentation
│   ├── orchestrate-config.sh        # Legacy configuration orchestrator
│   ├── sample-config.json           # Example configuration
│   ├── README-AUTO-MODE.md          # Auto-mode documentation
│   └── README-DEPRECATION.md        # Deprecation notices
│
├── vars/                        # Configuration and state
│   ├── config.json.template     # Configuration template (tracked in git)
│   ├── config.json              # User configuration (gitignored)
│   └── state.env                # Pipeline state (gitignored)
│
├── repos/                       # Dependencies (gitignored)
│   ├── ansible-quads-ssm/      # QUADS allocation (runs on reg-agent)
│   └── jetlag/                 # Cluster deployment (runs on reg-agent)
│
└── artifacts/                   # Test results (gitignored)
    └── regulus-results/

Note: Crucible and Regulus are cloned directly on the bastion host,
not under reg-agent/repos/
```

## Results and Artifacts

Test results are stored in `artifacts/`:

```bash
# View test summary from latest run
cat artifacts/latest/regulus-results/result-summary.txt

# View full validation report
cat artifacts/latest/validation-report.txt

# Check validation status
make validate

# List all runs
ls -lt artifacts/
```

## Troubleshooting

### Check Module Status

```bash
# Overall status
make info

# View configuration
make status

# Module-specific status
make -C modules/quads status
make -C modules/jetlag status
```

### Common Issues

**QUADS allocation fails:**
```bash
# Import existing cloud instead
make -C modules/quads import CLOUD_NAME=cloud23 LAB=scalelab
```

**Jetlag deployment fails:**
```bash
# Check logs
cat modules/jetlag/generated/logs/*.log

# Validate bastion access
ssh root@<bastion-host>
```

**Phase failures:**
```bash
# Fix configuration in vars/config.json
vim vars/config.json

# Resume deployment (skips completed phases)
make deploy
```

## Documentation

- **Main guide**: [README.md](README.md) (this file)
- **Developer guide**: [CLAUDE.md](CLAUDE.md)
- **Security policy**: [SECURITY.md](SECURITY.md)
- **Module docs**: `modules/*/CLAUDE.md`
- **Config schema**: [config/CONFIG-SCHEMA.md](config/CONFIG-SCHEMA.md)

## Contributing

See [CLAUDE.md](CLAUDE.md) for development guidelines and architecture details.

## License

Apache 2.0

## Related Projects

- **Jetlag**: https://github.com/redhat-performance/jetlag
- **Regulus**: https://github.com/HughNhan/regulus
- **Crucible**: https://github.com/perftool-incubator/crucible
- **QUADS**: https://github.com/quadsproject/quads

---

**reg-agent** - Automated performance testing pipeline for OpenShift
