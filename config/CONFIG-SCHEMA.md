# reg-agent Configuration Schema

## Overview

This document describes the JSON configuration schema for non-interactive deployment.

## Usage

### Interactive Mode (User Present)
```bash
make configure
# Prompts for missing values interactively
```

### Non-Interactive Mode (Automation)
```bash
make configure CONFIG_FILE=my-config.json
# Reads all values from JSON, errors if missing
```

## JSON Schema

### Top Level
```json
{
  "version": "1.0",
  "quads": { ... },
  "lab": { ... },
  "jetlag": { ... },
  "crucible": { ... },
  "regulus": { ... }
}
```

### QUADS Configuration (`quads`)

Controls Phase 1: Bare metal allocation via QUADS.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `api_server` | string | Yes | QUADS API hostname (e.g., "quads2.rdu2.scalelab.redhat.com") |
| `username` | string | Yes | QUADS username (without @redhat.com) |
| `password` | string | One of password/api_token | QUADS password |
| `api_token` | string | One of password/api_token | QUADS API token (preferred) |
| `lab` | string | Yes | Lab name: "scalelab" or "performancelab" |
| `num_hosts` | integer | Yes | Number of hosts to allocate (2 for SNO, 6+ for MNO) |
| `preferred_model` | string | No | Comma-separated model preferences (e.g., "r650,r750") |
| `workload_name` | string | No | Workload identifier (default: "reg-agent-YYYYMMDD-HHMM") |
| `short_description` | string | No | Short description (default: "reg-agent") |
| `wipe_disks` | string | No | "yes" or "no" (default: "no") |

### Lab SSH Configuration (`lab`)

Controls SSH access to lab machines (bastion, etc.).

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `ssh_password` | string | Yes | Lab SSH password for root user |
| `ssh_username` | string | No | SSH username (default: "root") |

### Jetlag Configuration (`jetlag`)

Controls Phase 2: OpenShift cluster deployment.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `cluster_type` | string | No | "mno" or "sno" (auto-detected from num_hosts if not specified) |
| `ocp_version` | string | No | OpenShift version (default: "latest-4.20") |
| `ocp_build` | string | No | Build type: "ga", "dev", "ci" (default: "ga") |
| `network_stack` | string | No | "ipv4", "ipv6", "dual" (default: "ipv4") |
| `worker_node_count` | integer | No | Number of workers for MNO (auto-calculated if not specified) |
| `pull_secret_path` | string | No | Path to OpenShift pull secret (default: "/root/pull-secret.txt") |

### Crucible Configuration (`crucible`)

Controls Phase 3: Crucible installation.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `install_path` | string | No | Installation directory (default: "/opt/crucible") |
| `git_branch` | string | No | Git branch to use (default: "master") |

### Regulus Configuration (`regulus`)

Controls Phase 4+: Regulus test execution.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `test_suite` | string | No | Test suite to run (default: "standard") |
| `duration` | string | No | Test duration (default: "1h") |

## Examples

### Minimal Configuration (MNO)
```json
{
  "version": "1.0",
  "quads": {
    "api_server": "quads2.rdu2.scalelab.redhat.com",
    "username": "myuser",
    "password": "mypass",
    "lab": "scalelab",
    "num_hosts": 6
  },
  "lab": {
    "ssh_password": "your-lab-password"
  }
}
```

### Full Configuration (SNO)
```json
{
  "version": "1.0",
  "quads": {
    "api_server": "quads2.rdu2.scalelab.redhat.com",
    "username": "myuser",
    "api_token": "qat_xxxxxxxxxxxxx",
    "lab": "scalelab",
    "num_hosts": 2,
    "preferred_model": "r650",
    "workload_name": "sno-perf-test",
    "wipe_disks": "yes"
  },
  "lab": {
    "ssh_password": "your-lab-password"
  },
  "jetlag": {
    "cluster_type": "sno",
    "ocp_version": "latest-4.18",
    "ocp_build": "ga",
    "network_stack": "ipv4"
  },
  "crucible": {
    "install_path": "/opt/crucible"
  },
  "regulus": {
    "test_suite": "performance",
    "duration": "2h"
  }
}
```

## Auto-Detection

When not specified in JSON, the following are auto-detected:

- **cluster_type**: Based on `num_hosts` (2 = SNO, 6+ = MNO)
- **worker_node_count**: Calculated as `num_hosts - 4` for MNO
- **workload_name**: Generated as `reg-agent-YYYYMMDD-HHMM`

## Security Notes

⚠️ **NEVER commit JSON config files with real credentials to git!**

Add to `.gitignore`:
```
config/*.json
!config/sample-config.json
```

Use environment-specific config files:
```
config/dev-config.json      # Development lab
config/prod-config.json     # Production lab
config/ci-config.json       # CI/CD pipeline
```
