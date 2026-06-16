# Auto Mode Configuration Guide

This directory contains JSON configuration files for **fully automated** deployment workflows.

## TL;DR - Quick Start

```bash
# For fresh QUADS allocation
CONFIG_FILE=config/config_quads_alloc.json make all

# For existing QUADS allocation
CONFIG_FILE=config/config_quads_import.json make all
```

That's it! The entire pipeline runs automatically with real API calls.

## Available Configurations

### 1. `config_quads_alloc.json` - Allocate + Deploy
**Use when**: You need new QUADS allocation and fresh cluster

**Workflow**:
```
Phase 1: Allocate new QUADS hosts
         ↓
Phase 2: Deploy OpenShift cluster with Jetlag
         ↓
Phase 3+: Continue with Crucible/Regulus
```

**Usage**:
```bash
# One command - does everything!
CONFIG_FILE=config/config_quads_alloc.json make all
```

This will:
1. Parse JSON config → generate `vars/config.env`
2. Call **real QUADS API** to allocate hosts
3. Call **real Jetlag** to deploy OpenShift
4. Install Crucible
5. Install & run Regulus tests
6. Validate results

### 2. `config_quads_import.json` - Import + Deploy
**Use when**: You have existing QUADS allocation, need fresh cluster

**Workflow**:
```
Phase 1: Import existing QUADS allocation (cloud23)
         ↓
Phase 2: Deploy OpenShift cluster with Jetlag
         ↓
Phase 3+: Continue with Crucible/Regulus
```

**Usage**:
```bash
# One command - does everything!
CONFIG_FILE=config/config_quads_import.json make all
```

This will:
1. Parse JSON config → generate `vars/config.env`
2. Call **real QUADS API** to import allocation (cloud23)
3. Call **real Jetlag** to deploy OpenShift
4. Install Crucible
5. Install & run Regulus tests
6. Validate results

## Configuration File Structure

```json
{
  "quads": {
    "mode": "allocate" | "import",

    // Common fields
    "api_server": "quads2.rdu2.scalelab.redhat.com",
    "username": "your-username",
    "password": "your-password",
    "lab": "scalelab",

    // For allocate mode
    "num_hosts": 2,
    "preferred_model": "any",
    "workload_name": "my-workload",

    // For import mode
    "cloud_name": "cloud23"
  },

  "jetlag": {
    "mode": "deploy",
    "cluster_type": "sno" | "mno",
    "ocp_version": "latest-4.20",
    "worker_node_count": 0
  }
}
```

## How It Works

```
CONFIG_FILE=config/config_quads_alloc.json make all
         ↓
    configure (parse JSON → vars/config.env)
         ↓
    deploy (runs actual APIs based on QUADS_MODE)
         ↓
    Phase 1: QUADS allocate/import (real API call)
         ↓
    Phase 2: Jetlag deploy (real cluster deployment)
         ↓
    Phase 3-6: Crucible + Regulus + Tests
```

## Examples

### Example 1: Fresh Allocation (Full Pipeline)
```bash
# 1. Edit credentials in JSON
vi config/config_quads_alloc.json

# 2. Run everything!
CONFIG_FILE=config/config_quads_alloc.json make all

# That's it - wait for completion
```

### Example 2: Import Existing (Full Pipeline)
```bash
# 1. Edit cloud name in JSON
vi config/config_quads_import.json
# Set: "cloud_name": "cloud42"

# 2. Run everything!
CONFIG_FILE=config/config_quads_import.json make all

# That's it - wait for completion
```

### Example 3: Just Initialize Config (No Execution)
```bash
# Only parse JSON and generate config (no API calls)
CONFIG_FILE=config/config_quads_alloc.json make configure

# Check what was generated
cat vars/config.env

# Then run manually if desired
make deploy
```

## Environment Variables Set

After running orchestrator, these variables are set in `vars/config.env`:

**QUADS allocate mode**:
- `QUADS_MODE=allocate`
- `QUADS_API_SERVER`
- `QUADS_USERNAME`, `QUADS_PASSWORD`
- `LAB`
- `NUM_HOSTS`, `PREFERRED_MODEL`
- `WORKLOAD_NAME`, `SHORT_DESCRIPTION`

**QUADS import mode**:
- `QUADS_MODE=import`
- `QUADS_API_SERVER`
- `QUADS_USERNAME`, `QUADS_PASSWORD`
- `LAB`
- `CLOUD_NAME`

**Jetlag (both modes)**:
- `CLUSTER_TYPE` (sno/mno)
- `OCP_VERSION`, `OCP_BUILD`
- `WORKER_NODE_COUNT`
- `PULL_SECRET_PATH`

## Customization

Edit the JSON files to customize:
- Credentials (username, password)
- Cluster size (num_hosts, worker_node_count)
- OpenShift version
- Hardware preferences
- Cloud name (for import)

## Troubleshooting

**Issue**: "Invalid JSON in config file"
- **Fix**: Validate JSON syntax: `jq empty config/config_quads_alloc.json`

**Issue**: "CLOUD_NAME not set" during import
- **Fix**: Ensure `cloud_name` field is set in JSON

**Issue**: "Could not authenticate to QUADS"
- **Fix**: Verify username/password in JSON are correct

## See Also

- `sample-config.json` - Complete example with all phases
- `prompt-config.sh` - Interactive configuration wizard
- Main README.md - Full reg-agent documentation
