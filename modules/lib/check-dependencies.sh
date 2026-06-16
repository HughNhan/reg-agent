#!/bin/bash
# Dependency checking library for reg-agent phases
# Each phase declares its dependencies and this library validates them

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Track dependency check results
DEPS_PASSED=0
DEPS_FAILED=0
FAILED_DEPS=()

# Reset dependency counters
reset_dep_check() {
    DEPS_PASSED=0
    DEPS_FAILED=0
    FAILED_DEPS=()
}

# Check if a repository exists
check_repo() {
    local repo_name="$1"
    local repo_path="${REG_AGENT_ROOT}/repos/${repo_name}"

    if [ -d "$repo_path" ]; then
        echo -e "${GREEN}✓${NC} Repository: ${repo_name}"
        DEPS_PASSED=$((DEPS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} Repository missing: ${repo_name}"
        echo "   Expected at: ${repo_path}"
        echo "   Fix: Run ./bootstrap.sh to clone repositories"
        FAILED_DEPS+=("repo:${repo_name}")
        DEPS_FAILED=$((DEPS_FAILED + 1))
        return 1
    fi
}

# Check if a file exists
check_file() {
    local file_desc="$1"
    local file_path="$2"

    if [ -f "$file_path" ]; then
        echo -e "${GREEN}✓${NC} File exists: ${file_desc}"
        DEPS_PASSED=$((DEPS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} File missing: ${file_desc}"
        echo "   Expected at: ${file_path}"
        FAILED_DEPS+=("file:${file_desc}")
        DEPS_FAILED=$((DEPS_FAILED + 1))
        return 1
    fi
}

# Check if a directory exists
check_dir() {
    local dir_desc="$1"
    local dir_path="$2"

    if [ -d "$dir_path" ]; then
        echo -e "${GREEN}✓${NC} Directory exists: ${dir_desc}"
        DEPS_PASSED=$((DEPS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} Directory missing: ${dir_desc}"
        echo "   Expected at: ${dir_path}"
        FAILED_DEPS+=("dir:${dir_desc}")
        DEPS_FAILED=$((DEPS_FAILED + 1))
        return 1
    fi
}

# Check if a variable is set in config or state
check_var() {
    local var_desc="$1"
    local var_name="$2"
    local var_value="${!var_name}"

    if [ -n "$var_value" ]; then
        echo -e "${GREEN}✓${NC} Variable set: ${var_desc} (${var_name}=${var_value})"
        DEPS_PASSED=$((DEPS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} Variable not set: ${var_desc} (${var_name})"
        echo "   Expected in: vars/config.json (.quads section) or vars/state.env"
        FAILED_DEPS+=("var:${var_name}")
        DEPS_FAILED=$((DEPS_FAILED + 1))
        return 1
    fi
}

# Check SSH access to a host
check_ssh() {
    local host_desc="$1"
    local host="$2"

    if [ -z "$host" ]; then
        echo -e "${RED}✗${NC} SSH host not specified: ${host_desc}"
        FAILED_DEPS+=("ssh:${host_desc}")
        DEPS_FAILED=$((DEPS_FAILED + 1))
        return 1
    fi

    if ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no "root@${host}" "echo ok" &>/dev/null; then
        echo -e "${GREEN}✓${NC} SSH access: ${host_desc} (${host})"
        DEPS_PASSED=$((DEPS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} SSH access failed: ${host_desc} (${host})"
        echo "   Fix: ssh-copy-id root@${host}"
        FAILED_DEPS+=("ssh:${host}")
        DEPS_FAILED=$((DEPS_FAILED + 1))
        return 1
    fi
}

# Check network connectivity
check_network() {
    local endpoint_desc="$1"
    local endpoint="$2"

    if curl -s --connect-timeout 5 "${endpoint}" &>/dev/null; then
        echo -e "${GREEN}✓${NC} Network access: ${endpoint_desc}"
        DEPS_PASSED=$((DEPS_PASSED + 1))
        return 0
    else
        echo -e "${YELLOW}⚠${NC} Network access: ${endpoint_desc} (${endpoint})"
        echo "   Warning: Cannot reach endpoint, may cause issues"
        # Don't fail on network checks, just warn
        return 0
    fi
}

# Check if a command exists
check_command() {
    local cmd_desc="$1"
    local cmd_name="$2"

    if command -v "${cmd_name}" &>/dev/null; then
        echo -e "${GREEN}✓${NC} Command available: ${cmd_desc} (${cmd_name})"
        DEPS_PASSED=$((DEPS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} Command not found: ${cmd_desc} (${cmd_name})"
        FAILED_DEPS+=("cmd:${cmd_name}")
        DEPS_FAILED=$((DEPS_FAILED + 1))
        return 1
    fi
}

# Check remote file exists via SSH
check_remote_file() {
    local file_desc="$1"
    local host="$2"
    local file_path="$3"

    if ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no "root@${host}" "[ -f ${file_path} ]" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Remote file exists: ${file_desc} on ${host}"
        DEPS_PASSED=$((DEPS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} Remote file missing: ${file_desc}"
        echo "   Expected: ${file_path} on ${host}"
        FAILED_DEPS+=("remote-file:${file_desc}")
        DEPS_FAILED=$((DEPS_FAILED + 1))
        return 1
    fi
}

# Check remote directory exists via SSH
check_remote_dir() {
    local dir_desc="$1"
    local host="$2"
    local dir_path="$3"

    if ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no "root@${host}" "[ -d ${dir_path} ]" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Remote directory exists: ${dir_desc} on ${host}"
        DEPS_PASSED=$((DEPS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} Remote directory missing: ${dir_desc}"
        echo "   Expected: ${dir_path} on ${host}"
        FAILED_DEPS+=("remote-dir:${dir_desc}")
        DEPS_FAILED=$((DEPS_FAILED + 1))
        return 1
    fi
}

# Summarize dependency check results
summarize_deps() {
    local phase_name="$1"

    echo ""
    echo "========================================="
    echo "Dependency Check Summary: ${phase_name}"
    echo "========================================="
    echo -e "Passed: ${GREEN}${DEPS_PASSED}${NC}"
    echo -e "Failed: ${RED}${DEPS_FAILED}${NC}"

    if [ ${DEPS_FAILED} -gt 0 ]; then
        echo ""
        echo -e "${RED}✗ Dependency check failed${NC}"
        echo ""
        echo "Failed dependencies:"
        for dep in "${FAILED_DEPS[@]}"; do
            echo "  - ${dep}"
        done
        echo ""
        echo "Please fix the dependencies above before running this phase."
        echo ""
        return 1
    else
        echo ""
        echo -e "${GREEN}✓ All dependencies satisfied${NC}"
        echo ""
        return 0
    fi
}
