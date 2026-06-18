#!/bin/bash
# reg-agent bootstrap script
# Sets up environment and clones dependencies

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}reg-agent Bootstrap${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Install system dependencies
echo "Installing system dependencies..."
echo ""

# Detect package manager
if command -v dnf &> /dev/null; then
    PKG_MGR="dnf"
elif command -v yum &> /dev/null; then
    PKG_MGR="yum"
elif command -v apt-get &> /dev/null; then
    PKG_MGR="apt-get"
else
    echo -e "${YELLOW}⚠ Unknown package manager. Please install manually:${NC}"
    echo "  - ansible-core (or ansible)"
    echo "  - jq"
    echo "  - curl"
    echo "  - git"
    echo "  - rsync"
    PKG_MGR=""
fi

# Install packages based on package manager
if [ -n "$PKG_MGR" ]; then
    PACKAGES="jq curl git rsync"

    # Check for ansible
    if ! command -v ansible-playbook &> /dev/null; then
        if [ "$PKG_MGR" = "dnf" ] || [ "$PKG_MGR" = "yum" ]; then
            PACKAGES="$PACKAGES ansible-core"
        else
            PACKAGES="$PACKAGES ansible"
        fi
    else
        echo -e "${GREEN}✓ Ansible already installed${NC}"
    fi

    # Install packages
    echo "Installing: $PACKAGES"
    if [ "$PKG_MGR" = "apt-get" ]; then
        sudo $PKG_MGR update -y > /dev/null 2>&1
        sudo $PKG_MGR install -y $PACKAGES > /dev/null 2>&1
    else
        sudo $PKG_MGR install -y $PACKAGES > /dev/null 2>&1
    fi

    # Verify critical commands
    MISSING=""
    for cmd in ansible-playbook jq curl git rsync; do
        if ! command -v $cmd &> /dev/null; then
            MISSING="$MISSING $cmd"
        fi
    done

    if [ -n "$MISSING" ]; then
        echo -e "${RED}✗ Failed to install:$MISSING${NC}"
        echo "Please install manually and re-run bootstrap.sh"
        exit 1
    fi

    echo -e "${GREEN}✓ System dependencies installed${NC}"
fi

# Install required Ansible collections
if command -v ansible-galaxy &> /dev/null; then
    echo ""
    echo "Installing Ansible collections..."
    ansible-galaxy collection install community.general > /dev/null 2>&1 || true
    echo -e "${GREEN}✓ Ansible collections installed${NC}"
fi

echo ""

# Check Python version - need 3.10+ for LLM features
echo "Checking Python version..."
PYTHON=""
PYTHON_VERSION=""

# Check for Python 3.10+
for py_bin in python3.12 python3.11 python3.10; do
    if command -v $py_bin &> /dev/null; then
        PYTHON=$py_bin
        PYTHON_VERSION=$($PYTHON --version 2>&1 | awk '{print $2}')
        break
    fi
done

# If no Python 3.10+ found, download pre-built Python 3.11
if [ -z "$PYTHON" ]; then
    echo -e "${YELLOW}⚠ Python 3.10+ not found (required for LLM features)${NC}"
    echo "Downloading pre-built Python 3.11..."

    # Use pre-built Python from python-build-standalone
    PYTHON_VERSION_TARGET="3.11.10"
    PYTHON_URL="https://github.com/indygreg/python-build-standalone/releases/download/20241016/cpython-${PYTHON_VERSION_TARGET}+20241016-x86_64-unknown-linux-gnu-install_only.tar.gz"
    PYTHON_DIR="$HOME/.local/python-${PYTHON_VERSION_TARGET}"

    if [ ! -d "$PYTHON_DIR" ]; then
        echo "Downloading Python ${PYTHON_VERSION_TARGET} (~30 seconds)..."
        mkdir -p "$HOME/.local"

        # Download and extract in one go
        if curl -L "$PYTHON_URL" 2>/dev/null | tar xz -C "$HOME/.local"; then
            mv "$HOME/.local/python" "$PYTHON_DIR"
            echo -e "${GREEN}✓ Python ${PYTHON_VERSION_TARGET} installed to $PYTHON_DIR${NC}"
        else
            echo -e "${RED}Error: Failed to download Python ${PYTHON_VERSION_TARGET}${NC}"
            echo "URL: $PYTHON_URL"
            exit 1
        fi
    else
        echo -e "${GREEN}✓ Python ${PYTHON_VERSION_TARGET} already installed${NC}"
    fi

    PYTHON="$PYTHON_DIR/bin/python3"
    PYTHON_VERSION=$($PYTHON --version 2>&1 | awk '{print $2}')
fi

echo -e "${GREEN}✓ Python: $PYTHON_VERSION${NC}"

# Create virtual environment for LLM features
if [ ! -d ".venv" ]; then
    echo ""
    echo "Creating Python virtual environment..."
    $PYTHON -m venv .venv
    source .venv/bin/activate
    pip install --upgrade pip > /dev/null 2>&1
    echo -e "${GREEN}✓ Virtual environment created${NC}"
else
    echo -e "${GREEN}✓ Virtual environment exists${NC}"
    source .venv/bin/activate
fi

# Install Python dependencies (for AI features - optional)
if [ -f "requirements.txt" ]; then
    echo ""
    echo "Installing Python dependencies (for AI features)..."
    if pip install -r requirements.txt > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Python dependencies installed${NC}"
        AI_AVAILABLE=true
    else
        echo -e "${YELLOW}⚠  Failed to install AI dependencies (optional)${NC}"
        echo "   AI features (ask-claude) will not be available"
        AI_AVAILABLE=false
    fi
else
    AI_AVAILABLE=false
fi

# Create directories
echo ""
echo "Creating directories..."
mkdir -p repos
mkdir -p vars
mkdir -p artifacts
mkdir -p logs
echo -e "${GREEN}✓ Directories created${NC}"

# Clone dependencies
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Cloning Dependencies${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# ansible-quads-ssm
if [ ! -d "repos/ansible-quads-ssm" ]; then
    echo "Cloning ansible-quads-ssm..."
    git clone https://github.com/quadsproject/ansible-quads-ssm.git repos/ansible-quads-ssm
    echo -e "${GREEN}✓ ansible-quads-ssm cloned${NC}"
else
    echo -e "${GREEN}✓ ansible-quads-ssm exists${NC}"
    echo "  (run 'cd repos/ansible-quads-ssm && git pull' to update)"
fi

# jetlag
if [ ! -d "repos/jetlag" ]; then
    echo ""
    echo "Cloning jetlag..."
    git clone https://github.com/redhat-performance/jetlag.git repos/jetlag
    echo -e "${GREEN}✓ jetlag cloned${NC}"
else
    echo -e "${GREEN}✓ jetlag exists${NC}"
    echo "  (run 'cd repos/jetlag && git pull' to update)"
fi

echo ""
echo -e "${YELLOW}Note: Crucible and Regulus will be cloned on the controller host during Phase 3 & 4${NC}"

# Bootstrap jetlag environment
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Bootstrapping Jetlag${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

if [ -f "repos/jetlag/bootstrap.sh" ]; then
    echo "Running jetlag bootstrap..."
    cd repos/jetlag
    if [ ! -d ".ansible" ]; then
        ./bootstrap.sh
        echo -e "${GREEN}✓ Jetlag bootstrapped${NC}"
    else
        echo -e "${GREEN}✓ Jetlag already bootstrapped${NC}"
    fi
    cd "$SCRIPT_DIR"
else
    echo -e "${YELLOW}Warning: jetlag/bootstrap.sh not found${NC}"
fi

# Check for pull secret
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Checking Prerequisites${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

if [ ! -f "pull-secret.txt" ] && [ ! -f "repos/jetlag/pull-secret.txt" ]; then
    echo -e "${YELLOW}⚠  Pull secret not found${NC}"
    echo "   Download from: https://console.redhat.com/openshift/install/pull-secret"
    echo "   Save to: $SCRIPT_DIR/pull-secret.txt"
else
    echo -e "${GREEN}✓ Pull secret found${NC}"
fi

# Check for SSH keys
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    echo -e "${YELLOW}⚠  SSH key not found at $HOME/.ssh/id_rsa${NC}"
    echo "   Generate with: ssh-keygen -t rsa -b 4096"
else
    echo -e "${GREEN}✓ SSH key found${NC}"
fi

# Check for gcloud (for Vertex AI)
if command -v gcloud &> /dev/null; then
    echo -e "${GREEN}✓ gcloud CLI installed${NC}"
    GCLOUD_ACCOUNT=$(gcloud config get-value account 2>/dev/null || echo "")
    if [ -n "$GCLOUD_ACCOUNT" ]; then
        echo "  Account: $GCLOUD_ACCOUNT"
    fi
else
    echo -e "${YELLOW}⚠  gcloud CLI not installed (optional, for Vertex AI)${NC}"
fi

# Check for Ollama (for local LLM)
if command -v ollama &> /dev/null; then
    echo -e "${GREEN}✓ Ollama installed${NC}"
    OLLAMA_VERSION=$(ollama --version 2>&1 | head -1)
    echo "  Version: $OLLAMA_VERSION"
else
    echo -e "${YELLOW}⚠  Ollama not installed (optional, for local LLM)${NC}"
    echo "  Install with: curl -fsSL https://ollama.com/install.sh | sh"
fi

# Summary
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Bootstrap Complete!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. Configure reg-agent:"
echo "   make configure"
echo ""
echo "2. Run full pipeline:"
echo "   make"
echo ""
echo "3. Or run interactively:"
echo "   make configure"
echo "   make deploy"
echo ""
if [ "$AI_AVAILABLE" = "true" ]; then
    # Create function wrapper for ask-claude (works better than alias)
    SHELL_RC=""
    if [ -n "$BASH_VERSION" ]; then
        SHELL_RC="$HOME/.bashrc"
    elif [ -n "$ZSH_VERSION" ]; then
        SHELL_RC="$HOME/.zshrc"
    fi

    if [ -n "$SHELL_RC" ]; then
        # Add function if not already present
        if ! grep -q "function ask-claude" "$SHELL_RC" 2>/dev/null && ! grep -q "ask-claude()" "$SHELL_RC" 2>/dev/null; then
            cat >> "$SHELL_RC" << EOF

# reg-agent AI assistant
ask-claude() {
    $SCRIPT_DIR/bin/ask-claude "\$@"
}
EOF
            echo -e "${GREEN}✓ Added 'ask-claude' command to $SHELL_RC${NC}"
            echo -e "${YELLOW}  Run 'source $SHELL_RC' or restart your shell to use it${NC}"
        fi
    fi

    echo "AI Assistant (ask-claude):"
    echo "   ask-claude 'your question here'"
    echo "   ask-claude analyze-failure path/to/error.log"
    echo "   ask-claude recommend-quads 'test requirements'"
    echo ""
fi
echo "For help:"
echo "   make help"
echo ""
