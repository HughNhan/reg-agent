# QUADS SSM Generated Files

This directory contains all generated files, logs, and state from QUADS SSM operations.

## Directory Structure

```
generated/
├── state/              # Assignment state files
│   └── current.env     # Current active assignment (CLOUD_NAME, ASSIGNMENT_ID, etc.)
├── logs/               # Operation logs
│   ├── allocate_YYYYMMDD_HHMMSS.log
│   ├── validate_YYYYMMDD_HHMMSS.log
│   └── deallocate_YYYYMMDD_HHMMSS.log
└── output/             # API responses and artifacts
    ├── quads_response_YYYYMMDD_HHMMSS.json
    └── assignment_details_YYYYMMDD_HHMMSS.json
```

## State File

**Location**: `generated/state/current.env`

Contains the current QUADS assignment information:
```bash
CLOUD_NAME=cloud04
ASSIGNMENT_ID=12345
QUADS_METHOD=quads-ssm
LAB=scalelab
ALLOCATED_AT=2026-06-10T01:30:00Z
```

This file is:
- Created by `make test-quads` (allocation)
- Read by `make validate-quads` and `make deallocate-quads`
- Deleted by `make deallocate-quads` (after successful termination)

## Log Files

All operations create timestamped log files in `logs/`:

- **allocate_*.log** - Full output from allocation operation
- **validate_*.log** - Full output from validation checks
- **deallocate_*.log** - Full output from deallocation operation

Logs include:
- Timestamps
- API requests/responses
- Dependency checks
- Success/error messages

## Output Files

API responses and detailed information in `output/`:

- **quads_response_*.json** - Raw QUADS API responses
- **assignment_details_*.json** - Parsed assignment information
- **hosts_*.json** - List of allocated hosts

## Cleanup

To clear all generated files:

```bash
# Remove all generated files
rm -rf modules/quads/generated/logs/*
rm -rf modules/quads/generated/output/*
rm -rf modules/quads/generated/state/*

# Or use make target (if available)
make clean-quads
```

## Viewing Logs

```bash
# View latest allocation log
ls -t modules/quads/generated/logs/allocate_* | head -1 | xargs cat

# View current state
cat modules/quads/generated/state/current.env

# View all logs from today
ls -lh modules/quads/generated/logs/*$(date +%Y%m%d)*
```

## State Management

The state file is the source of truth for QUADS operations:

```bash
# Check if assignment exists
[ -f modules/quads/generated/state/current.env ] && echo "Active assignment" || echo "No assignment"

# View assignment details
cat modules/quads/generated/state/current.env

# Manually clear state (use with caution)
rm modules/quads/generated/state/current.env
```

## Integration with vars/state.env

For backward compatibility, the main `vars/state.env` may still be created.
However, the SSM module now uses `modules/quads/generated/state/current.env` as primary state.
