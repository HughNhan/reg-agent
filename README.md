# reg-agent

**CI/CD Orchestrator for Regulus Performance Testing on OpenShift**

Automates the complete pipeline from bare metal allocation to cluster deployment, performance test execution, and result validation.

## Overview

reg-agent orchestrates a 4-module pipeline:

1. **QUADS** - Allocate bare metal from Red Hat performance labs (scalelab/performancelab)
2. **Jetlag** - Deploy OpenShift cluster (MNO/SNO) on allocated hardware
3. **Crucible** - Install performance benchmark framework on bastion host
4. **Regulus** - Execute performance tests and collect results

## How to Use

### Quick Start (3 steps)

```bash
# 1. Clone and bootstrap
git clone https://github.com/HughNhan/reg-agent.git
cd reg-agent
./bootstrap.sh

# 2. Configure - Build vars/config.json using interactive helpers
make -C modules/quads configure      # Configure QUADS allocation
make -C modules/jetlag configure     # Configure cluster deployment (optional)
make -C modules/crucible configure   # Configure Crucible setup (optional)
make -C modules/regulus configure    # Configure test execution (optional)

# 3. Run the pipeline
make deploy          # Deploy infrastructure
make run validate    # Run tests and validate results
```

**Or use `make all`** to deploy + run + validate in one command:
```bash
./bootstrap.sh
make -C modules/quads configure
make all
```

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

### Using Existing Cluster (Skip QUADS and Jetlag)

Set deployment mode to `cluster-ready` in `vars/config.json`:

```json
{
  "deployment_mode": "cluster-ready",
  "lab": {
    "bastion_host": "cloud04.example.com",
    "bastion_ssh_user": "root"
  },
  "jetlag": {
    "kubeconfig_path": "/root/mno/kubeconfig",
    "cluster_type": "mno"
  },
  "regulus": {
    "tests": ["ovn-k:hostnet:iperf-tcp-1200"]
  }
}
```

Then run:
```bash
make deploy  # Skips QUADS and Jetlag, goes directly to Crucible + Regulus
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
  "deployment_mode": "full",

  "quads": {
    "api_server": "https://quads.example.com",
    "username": "your-username",
    "password": "your-password",
    "num_hosts": 6,
    "lab": "scalelab",
    "duration_hours": 168
  },

  "lab": {
    "name": "scalelab",
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
    "controller_host": "auto",
    "controller_user": "root",
    "git_repo": "https://github.com/perftool-incubator/crucible.git"
  },

  "regulus": {
    "tests": [
      "ovn-k:hostnet:iperf-tcp-1200"
    ],
    "git_repo": "https://github.com/HughNhan/regulus.git",
    "num_samples": 3,
    "test_duration": 60
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
│   │   ├── json-config.sh       # JSON configuration functions
│   │   └── check-dependencies.sh
│   │
│   ├── quads/                   # Phase 1: Bare metal allocation
│   │   ├── Makefile
│   │   ├── CLAUDE.md
│   │   ├── configure-json.sh
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
│   └── regulus/                 # Phase 4: Test execution
│       ├── Makefile
│       ├── CLAUDE.md
│       ├── configure-json.sh
│       └── configure-tests.sh
│
├── config/
│   ├── config.schema.json       # JSON Schema validation
│   └── validate-config.sh       # Configuration validator
│
├── vars/                        # Generated configs (gitignored)
│   ├── config.json              # Main configuration
│   └── state.env                # Pipeline state
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

Test results are stored in `artifacts/regulus-results/`:

```bash
# View test summary
make -C modules/regulus show-results

# Check validation status
make validate
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
