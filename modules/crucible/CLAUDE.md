# Phase 3: Crucible Installation Module

## Purpose

Install Crucible performance benchmark framework on bastion host.

## Module Scope

**Focus**: Crucible installation only
**Input**: BASTION_HOST from Phase 2; repo from bootstrap
**Output**: CRUCIBLE_PATH in `vars/state.env`
**Next Phase**: Regulus configuration (Phase 4)

## Files in This Module

```
modules/
└── phase-3-crucible-setup.sh      # Main installation script

repos/crucible/                     # External dependency
├── bin/                           # Crucible executables
└── ...                            # Crucible framework
```

## Key Script: `phase-3-crucible-setup.sh`

**Location**: `modules/phase-3-crucible-setup.sh`
**Purpose**: Copy Crucible to bastion and install dependencies
**Called by**: `Makefile` target `test-crucible` or `deploy-full/deploy-existing`

### Dependencies Checked

The script uses `../lib/check-dependencies.sh` to validate:

1. **Repository**: crucible exists at `repos/crucible/`
2. **State variables** (from Phase 2):
   - BASTION_HOST
3. **SSH access**: Passwordless SSH to bastion
4. **Commands**: ssh, scp, tar (or rsync if available)

### What It Does

1. **Dependency Check**: Validates all prerequisites
2. **Check Existing Installation**:
   - If Crucible exists at `/root/crucible` on bastion:
     - Updates via `git pull`
   - If not:
     - Copies Crucible to bastion
3. **Copy Method**:
   - Prefers `rsync` if available (faster, excludes .git automatically)
   - Falls back to `tar` + `scp` if rsync unavailable
4. **Install Dependencies**: Runs Crucible's install script on bastion
5. **Save State**: Writes CRUCIBLE_PATH to `vars/state.env`

### Script Flow

```bash
# 1. Check if Crucible already on bastion
if ssh root@$BASTION_HOST "[ -d /root/crucible ]"; then
    # Update existing
    ssh root@$BASTION_HOST "cd /root/crucible && git pull"
else
    # Copy fresh installation
    if rsync available:
        rsync -az repos/crucible/ root@$BASTION_HOST:/root/crucible/
    else:
        tar -czf /tmp/crucible.tar.gz -C repos/crucible .
        scp /tmp/crucible.tar.gz root@$BASTION_HOST:/tmp/
        ssh root@$BASTION_HOST "mkdir -p /root/crucible && tar -xzf /tmp/crucible.tar.gz"
fi

# 2. Run Crucible install script
ssh root@$BASTION_HOST "cd /root/crucible && ./install"

# 3. Save state
echo "CRUCIBLE_PATH=/root/crucible" >> vars/state.env
```

## Configuration Variables

### Required (from `vars/config.env`):
- `CRUCIBLE_GIT_REPO`: Git repository URL for Crucible (confidential)
- `INSTALLATION_TARGET`: Where to install (bastion or other)

### Required (from `vars/state.env`):
- `BASTION_HOST`: Bastion hostname/IP (set by Phase 2, used when INSTALLATION_TARGET=bastion)

### Optional (from `vars/config.env`):
- `CRUCIBLE_GIT_BRANCH`: Git branch to clone (default: master)
- `CRUCIBLE_INSTALL_SCRIPT`: Installation script name (default: rh-install-crucible.sh)
- `INSTALLATION_OTHER_HOST`: Custom server (used when INSTALLATION_TARGET=other)
- `INSTALLATION_OTHER_USER`: SSH username (default: root)

## Output State

Written to `vars/state.env`:
```bash
CRUCIBLE_PATH=/root/crucible
```

## Testing This Module

### Test Independently (requires Phase 1+2 completed):

```bash
# Prerequisites: Bastion host must be available
cat vars/state.env
# Should show: BASTION_HOST

# Run Phase 3
make test-crucible

# Verify output
cat vars/state.env
# Should now also show: CRUCIBLE_PATH

# Manual verification
ssh root@$(grep BASTION_HOST vars/state.env | cut -d= -f2)
cd /root/crucible
ls -la
```

### Test with Existing Crucible:

```bash
# First run: Fresh install
make test-crucible
# Output: "Copying Crucible to bastion..."

# Second run: Update
make test-crucible
# Output: "✓ Crucible already at /root/crucible"
# Output: "Updating Crucible..."
```

## Common Issues

### Issue 1: "Repository missing: crucible"
**Cause**: Bootstrap didn't clone crucible
**Fix**: Run `./bootstrap.sh`

### Issue 2: "Cannot SSH to bastion"
**Cause**: SSH keys not copied to bastion
**Fix**:
```bash
# Get bastion host from state
BASTION=$(grep BASTION_HOST vars/state.env | cut -d= -f2)

# Copy SSH key manually
ssh-copy-id root@$BASTION
```

### Issue 3: "rsync: command not found"
**Impact**: Non-fatal, script falls back to tar+scp
**Note**: Rsync is optional but faster for large transfers
**Optional fix**: Install rsync on local machine:
```bash
# RHEL/CentOS/Fedora
sudo dnf install rsync

# Ubuntu/Debian
sudo apt install rsync
```

### Issue 4: "Crucible install script failed"
**Common causes**:
- Missing dependencies on bastion (Python, git, etc.)
- Insufficient disk space
- Network connectivity issues

**Debug**:
```bash
# SSH to bastion
ssh root@$BASTION_HOST

# Check Crucible install log
cd /root/crucible
cat install.log  # If install script creates logs

# Try manual install
./install -v  # Verbose mode
```

### Issue 5: "Permission denied" during copy
**Cause**: SSH access issues or bastion disk full
**Fix**:
```bash
# Check SSH access
ssh root@$BASTION_HOST "echo ok"

# Check bastion disk space
ssh root@$BASTION_HOST "df -h /root"

# Verify /root is writable
ssh root@$BASTION_HOST "touch /root/test && rm /root/test"
```

## Integration with Other Phases

### Input from Phase 2:
- `BASTION_HOST`: Where to install Crucible

### Output for Phase 4:
- `CRUCIBLE_PATH`: Regulus depends on Crucible being installed
- Phase 4 validates Crucible exists before proceeding

### State File After Phase 3:
```bash
# From Phase 1
CLOUD_NAME=cloud42
ASSIGNMENT_ID=12345
LAB=scalelab

# From Phase 2
BASTION_HOST=cloud42-h01-000-r750.scalelab.example.com
KUBECONFIG_PATH=/root/mno/kubeconfig
CLUSTER_TYPE=mno

# From Phase 3
CRUCIBLE_PATH=/root/crucible
```

## Crucible-Specific Details

### What is Crucible?

Crucible is a performance benchmark execution framework that:
- Manages test workload execution
- Handles result collection and analysis
- Provides standardized testing environment
- Required dependency for Regulus performance testing

### Installation Location

- **Always installed at**: `/root/crucible` on bastion
- **Why bastion**: Crucible orchestrates tests from bastion to cluster
- **Dependencies**: Crucible installs its own Python venv and dependencies

### Update Strategy

The script uses smart update logic:
- **First run**: Full copy + install
- **Subsequent runs**: Git pull to update
- **Rationale**: Faster updates, preserves local changes if needed

### Excluded Files

When copying, the script excludes:
- `.git/` directory (reduces copy size)
- Large temporary files
- Previous run artifacts

## Development Tips

### Testing Copy Methods

Force tar method even if rsync available:
```bash
# Edit phase-3-crucible-setup.sh temporarily
if false && command -v rsync &>/dev/null; then  # Add 'false &&'
    # rsync path
else
    # tar path (will be used)
fi
```

### Debugging Installation

Add verbose logging to installation:
```bash
# SSH to bastion and run manually
ssh root@$BASTION_HOST
cd /root/crucible
./install -vv  # Very verbose
```

### Verifying Crucible Works

After installation:
```bash
ssh root@$BASTION_HOST
cd /root/crucible
./bin/crucible --version
./bin/crucible --help
```

### Modifying Install Path

If you need a different installation path:

1. Edit `phase-3-crucible-setup.sh`:
```bash
CRUCIBLE_BASTION_PATH="/opt/crucible"  # Change from /root/crucible
```

2. Update copy commands to use new path
3. Update state.env write to use new path
4. Ensure Phase 4 uses same path

### Adding Pre-Install Checks

Add checks before installation:
```bash
# Check bastion has enough space
AVAILABLE_SPACE=$(ssh root@$BASTION_HOST "df -BG /root | tail -1 | awk '{print \$4}' | sed 's/G//'")
if [ "$AVAILABLE_SPACE" -lt 10 ]; then
    echo "Error: Insufficient space on bastion (need 10GB, have ${AVAILABLE_SPACE}GB)"
    exit 1
fi
```

## Relationship with Regulus

Regulus **requires** Crucible to run performance tests:
- Crucible provides test execution framework
- Regulus uses Crucible to orchestrate OCP performance tests
- Phase 4 will validate Crucible exists before setting up Regulus

## Related Documentation

- Main project CLAUDE.md: `../../CLAUDE.md`
- Dependency library: `../lib/check-dependencies.sh`
- Previous phase: `../jetlag/CLAUDE.md`
- Next phase: `../regulus/CLAUDE.md`
- Crucible docs: `../../repos/crucible/README.md`
