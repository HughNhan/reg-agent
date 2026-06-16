# Configuration Directory

## Quick Start

### First Time Setup - Interactive Helper (Recommended)

```bash
cd /root/reg-agent/modules/quads

# Initialize the module (run once)
make init

# This will:
# - Clone ansible-quads-ssm (if not present)
# - Ask which lab (scalelab/performancelab)
# - Prompt for credentials
# - Create vars/config.env automatically

# Test allocation
make test
```

### Alternative - Manual Setup

#### For Scalelab Users

```bash
cd /root/reg-agent/vars

# Copy the scalelab example
cp config.env.scalelab-example config.env

# Edit and add your credentials
vi config.env
# Replace: your-username, qat_your_token_here (or QUADS_PASSWORD)

# Test allocation
cd ..
make test-quads
```

### For Performancelab Users

```bash
cd /root/reg-agent/vars

# Copy the performancelab example
cp config.env.performancelab-example config.env

# Edit and add your credentials
vi config.env
# Replace: your-username, qat_your_token_here (or QUADS_PASSWORD)

# Test allocation
cd ..
make test-quads
```

## QUADS Server URLs

| Lab | QUADS Server URL | LAB Value |
|-----|------------------|-----------|
| Scalelab | `quads2.rdu2.scalelab.redhat.com` | `scalelab` |
| Performancelab | `quads2.rdu3.labs.perfscale.redhat.com` | `performancelab` |

## Configuration Files

- `config.env` - Your active configuration (you create this, gitignored)
- `config.env.scalelab-example` - Example for scalelab
- `config.env.performancelab-example` - Example for performancelab
- `config.env.quads-template` - Generic template
- `state.env` - Auto-generated pipeline state (don't edit)

## Required QUADS Variables

```bash
# Server (must match your lab)
QUADS_API_SERVER="quads2.rdu2.scalelab.redhat.com"

# Authentication (use ONE of these methods)
QUADS_API_TOKEN="qat_xxxxx"    # Preferred
# OR
QUADS_PASSWORD="yourpassword"   # Alternative

# User info
QUADS_USERNAME="your-username"
QUADS_USER_DOMAIN="redhat.com"

# Cluster config
LAB="scalelab"                  # Must match QUADS_API_SERVER
NUM_HOSTS="3"
PREFERRED_MODEL="r750,r740xd"
WORKLOAD_NAME="unique-identifier"
SHORT_DESCRIPTION="Human readable description"
WIPE_DISKS="no"                 # "yes" or "no"
```

## Getting API Token

### Scalelab
1. Visit: http://quads2.rdu2.scalelab.redhat.com/login
2. Login with your credentials
3. Go to: Profile → API Tokens
4. Generate new token (starts with `qat_`)
5. Copy to `QUADS_API_TOKEN` in config.env

### Performancelab
1. Visit: http://quads2.rdu3.labs.perfscale.redhat.com/login
2. Login with your credentials
3. Go to: Profile → API Tokens
4. Generate new token (starts with `qat_`)
5. Copy to `QUADS_API_TOKEN` in config.env

## Testing Your Configuration

```bash
# Check syntax
source vars/config.env && echo "Config OK"

# Test QUADS allocation
make test-quads

# If successful, you'll see:
# ✅ QUADS Allocation Complete
# Cloud: cloud04
# Assignment ID: 12345
```

## Common Issues

### "Variable not set: QUADS API server"
- You need to create `config.env` from one of the examples
- Make sure QUADS_API_SERVER is uncommented and has the correct URL

### "Authentication failed"
- Check your QUADS_API_TOKEN or QUADS_PASSWORD is correct
- Verify you can login to the QUADS web portal
- Make sure QUADS_USERNAME matches your login (without @redhat.com)

### "Could not reach QUADS server"
- Verify you're on the correct network (VPN or lab network)
- Check QUADS_API_SERVER matches your LAB setting:
  - scalelab → quads2.rdu2.scalelab.redhat.com
  - performancelab → quads2.rdu3.labs.perfscale.redhat.com
