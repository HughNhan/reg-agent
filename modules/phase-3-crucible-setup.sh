#!/bin/bash
# Phase 3: Crucible Setup
# Installs Crucible on the bastion host

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG_AGENT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Source configuration
if [ ! -f "${REG_AGENT_ROOT}/vars/config.json" ]; then
    echo -e "${RED}Error: Configuration not found${NC}"
    echo "Run: make configure"
    exit 1
fi
# Load JSON configuration
source "${REG_AGENT_ROOT}/modules/lib/json-config.sh"
json_export_env ".crucible" "CRUCIBLE"
json_export_env ".crucible_controller" "CRUCIBLE_CONTROLLER"
json_export_env ".lab" "LAB"

# Source state if exists (may not exist on first run)
if [ -f "${REG_AGENT_ROOT}/vars/state.env" ]; then
    source "${REG_AGENT_ROOT}/vars/state.env"
fi

# Load dependency checking library
source "${REG_AGENT_ROOT}/modules/lib/check-dependencies.sh"

# Load logging library
source "${REG_AGENT_ROOT}/modules/lib/logging.sh"
init_logging "crucible" "phase-3-crucible-setup"

CRUCIBLE_REPO="${REG_AGENT_ROOT}/repos/crucible"

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Phase 3: Crucible Setup${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
log "========================================"
log "Phase 3: Crucible Setup"
log "========================================"

#------------------------------------------------------------------------------
# Determine Installation Host
#------------------------------------------------------------------------------
CRUCIBLE_CONTROLLER_TARGET=${CRUCIBLE_CONTROLLER_TARGET:-bastion}

if [ "$CRUCIBLE_CONTROLLER_TARGET" = "bastion" ]; then
    # Use bastion from Jetlag deployment
    CRUCIBLE_CONTROLLER_HOST="$BASTION_HOST"
    CRUCIBLE_CONTROLLER_USER="root"
    echo "Controller target: Cluster bastion"
elif [ "$CRUCIBLE_CONTROLLER_TARGET" = "other" ]; then
    # Use user-specified host
    CRUCIBLE_CONTROLLER_HOST="$CRUCIBLE_CONTROLLER_OTHER_HOST"
    CRUCIBLE_CONTROLLER_USER="${CRUCIBLE_CONTROLLER_USER:-root}"
    echo "Controller target: Other server"
else
    echo -e "${RED}Error: Invalid CRUCIBLE_CONTROLLER_TARGET: $CRUCIBLE_CONTROLLER_TARGET${NC}"
    exit 1
fi

#------------------------------------------------------------------------------
# Setup SSH Access to Controller Host (if needed)
#------------------------------------------------------------------------------
echo ""
echo "Checking SSH access to controller host..."

# Try SSH with key-based auth first
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no "${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST}" "echo ok" &>/dev/null; then
    echo -e "${YELLOW}⚠ SSH key-based access not working${NC}"

    # Try to setup SSH key if LAB_SSH_PASSWORD is available
    if [ -n "$LAB_SSH_PASSWORD" ]; then
        echo "Setting up passwordless SSH access..."

        if command -v sshpass &> /dev/null; then
            # First verify we can connect with password
            if sshpass -p "$LAB_SSH_PASSWORD" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST}" "echo ok" &>/dev/null; then
                echo -e "${GREEN}✓ Password authentication works${NC}"
                # Copy SSH key now that we can connect
                sshpass -p "$LAB_SSH_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no "${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST}" &>/dev/null || true
                echo -e "${GREEN}✓ SSH key copied - passwordless access enabled${NC}"
            else
                echo -e "${YELLOW}⚠ Could not connect with LAB_SSH_PASSWORD${NC}"
                echo "  Please verify the password is correct in vars/config.json"
            fi
        else
            echo -e "${YELLOW}⚠ sshpass not found${NC}"
            echo "  Install: yum install -y sshpass"
            echo "  Or manually copy SSH key: ssh-copy-id ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST}"
        fi
    else
        echo -e "${YELLOW}⚠ LAB_SSH_PASSWORD not configured${NC}"
        echo ""
        echo "To enable automatic SSH key setup, add to vars/config.json:"
        echo '  "lab": {'
        echo '    "ssh_password": "your-lab-password"'
        echo '  }'
        echo ""
        echo "Or manually copy SSH key:"
        echo "  ssh-copy-id ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST}"
    fi
else
    echo -e "${GREEN}✓ SSH key-based access working${NC}"
fi

# Check dependencies
echo "Checking Phase 3 dependencies..."
echo ""
reset_dep_check

# NOTE: We do NOT check for local crucible repo - it will be cloned on the target host
# Only check that we can access the target host and have git available there

# Required configuration variables
if [ "$CRUCIBLE_CONTROLLER_TARGET" = "bastion" ]; then
    check_var "Bastion host (from Jetlag)" "BASTION_HOST"
else
    check_var "Controller host" "CRUCIBLE_CONTROLLER_OTHER_HOST"
fi

# SSH access to installation host
check_ssh "Controller host" "$CRUCIBLE_CONTROLLER_HOST"

# Required commands (local)
check_command "SSH" "ssh"

# Summarize and fail if dependencies not met
if ! summarize_deps "Phase 3: Crucible Setup"; then
    exit 1
fi

echo ""
echo "Controller host: ${CRUCIBLE_CONTROLLER_HOST}"
echo "Installation user: ${CRUCIBLE_CONTROLLER_USER}"
echo ""

# Check if Crucible already installed
echo ""
echo "Checking if Crucible is already installed..."
if ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} "command -v crucible &>/dev/null"; then
    echo -e "${GREEN}✓ Crucible command found${NC}"

    # Ask if user wants to reinstall
    if [ -z "$AUTO_MODE" ] && [ -t 0 ]; then
        echo ""
        echo -e "${YELLOW}Crucible is already installed.${NC}"
        read -p "Do you want to reinstall/update Crucible? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Skipping Crucible installation"

            # Save state
            if ! grep -q "CRUCIBLE_PATH" "${REG_AGENT_ROOT}/vars/state.env" 2>/dev/null; then
                echo "CRUCIBLE_PATH=/root/crucible" >> "${REG_AGENT_ROOT}/vars/state.env"
                echo "CRUCIBLE_INSTALLED=true" >> "${REG_AGENT_ROOT}/vars/state.env"
                echo "CRUCIBLE_INSTALL_TIME=$(date -Iseconds)" >> "${REG_AGENT_ROOT}/vars/state.env"
            fi

            echo ""
            echo -e "${GREEN}=========================================${NC}"
            echo -e "${GREEN}✅ Phase 3: Crucible Ready (Existing)${NC}"
            echo -e "${GREEN}=========================================${NC}"
            exit 0
        fi
        echo "Proceeding with reinstall..."
    else
        # In AUTO_MODE, skip reinstall
        echo "Auto mode: Skipping reinstall of existing Crucible"

        # Save state
        if ! grep -q "CRUCIBLE_PATH" "${REG_AGENT_ROOT}/vars/state.env" 2>/dev/null; then
            echo "CRUCIBLE_PATH=/root/crucible" >> "${REG_AGENT_ROOT}/vars/state.env"
            echo "CRUCIBLE_INSTALLED=true" >> "${REG_AGENT_ROOT}/vars/state.env"
            echo "CRUCIBLE_INSTALL_TIME=$(date -Iseconds)" >> "${REG_AGENT_ROOT}/vars/state.env"
        fi

        echo ""
        echo -e "${GREEN}=========================================${NC}"
        echo -e "${GREEN}✅ Phase 3: Crucible Ready (Existing)${NC}"
        echo -e "${GREEN}=========================================${NC}"
        exit 0
    fi
fi

echo -e "${YELLOW}Crucible not found - will install${NC}"

# Install Crucible using the proper procedure
echo ""
echo "Installing Crucible on ${CRUCIBLE_CONTROLLER_HOST}..."

# Validate configuration variables
if [ -z "$CRUCIBLE_GIT_REPO" ]; then
    echo -e "${RED}Error: CRUCIBLE_GIT_REPO not configured${NC}"
    echo "Run: make configure"
    exit 1
fi

CRUCIBLE_GIT_BRANCH=${CRUCIBLE_GIT_BRANCH:-master}
CRUCIBLE_INSTALL_SCRIPT=${CRUCIBLE_INSTALL_SCRIPT:-rh-install-crucible.sh}

# Extract repo name from URL (last component before .git)
REPO_NAME=$(basename "$CRUCIBLE_GIT_REPO" .git)

ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} bash <<CRUCIBLE_INSTALL
set -e

# Pre-configure git to avoid interactive prompts
if ! git config --global user.name &>/dev/null; then
    git config --global user.name "reg-agent"
    git config --global user.email "reg-agent@redhat.com"
    echo "✓ Git configured"
fi

# Disable SSL verification for internal Red Hat GitLab (gitlab.cee.redhat.com)
if echo "${CRUCIBLE_GIT_REPO}" | grep -q "gitlab.cee.redhat.com"; then
    export GIT_SSL_NO_VERIFY=1
    echo "✓ Disabled SSL verification for internal GitLab"
fi

# Navigate to /root and clone repository
cd /root/
if [ -d ${REPO_NAME} ]; then
    echo "Removing existing ${REPO_NAME} directory..."
    rm -rf ${REPO_NAME}
fi

echo "Cloning ${REPO_NAME} from git repository..."
git clone ${CRUCIBLE_GIT_REPO}

# Run the installation script
cd ${REPO_NAME}
echo "Running ${CRUCIBLE_INSTALL_SCRIPT}..."
bash ${CRUCIBLE_INSTALL_SCRIPT}

echo "✓ Crucible installation script completed"
CRUCIBLE_INSTALL

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Crucible installation failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Crucible installed${NC}"

# Verify Crucible command is available
echo ""
echo "Verifying Crucible installation..."

if ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} "command -v crucible &>/dev/null"; then
    echo -e "${GREEN}✓ Crucible command is available${NC}"

    # Show crucible version/info if available
    CRUCIBLE_INFO=$(ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST} "crucible --version 2>/dev/null || crucible --help 2>&1 | head -3")
    if [ -n "$CRUCIBLE_INFO" ]; then
        echo "  Info: $CRUCIBLE_INFO"
    fi
else
    echo -e "${RED}✗ Crucible command not found${NC}"
    echo "Installation may have failed or crucible is not in PATH"
    exit 1
fi

# Save Crucible path to state
echo ""
echo "Saving state..."
mkdir -p "${REG_AGENT_ROOT}/vars"
if ! grep -q "CRUCIBLE_PATH" "${REG_AGENT_ROOT}/vars/state.env" 2>/dev/null; then
    echo "CRUCIBLE_PATH=/root/crucible" >> "${REG_AGENT_ROOT}/vars/state.env"
fi
echo "CRUCIBLE_INSTALLED=true" >> "${REG_AGENT_ROOT}/vars/state.env"
echo "CRUCIBLE_INSTALL_TIME=$(date -Iseconds)" >> "${REG_AGENT_ROOT}/vars/state.env"

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✅ Phase 3: Crucible Setup Complete${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Crucible installed at: /root/crucible on ${CRUCIBLE_CONTROLLER_HOST}"
echo ""
echo "Next phase: Regulus setup (make test-regulus-install)"
echo ""
echo "Manual verification:"
echo "  ssh ${CRUCIBLE_CONTROLLER_USER}@${CRUCIBLE_CONTROLLER_HOST}"
echo "  ls -la /root/crucible"
echo "  cd /root/crucible && ls bin/"
echo ""

exit 0
