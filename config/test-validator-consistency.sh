#!/bin/bash
# Test that validation logic produces consistent results
# This ensures the library validator correctly uses the standalone validator's rules

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Testing validator consistency..."
echo ""

# Test 1: BYOL mode (import)
cat > /tmp/test-byol.json <<EOF
{
  "quads": {
    "mode": "import",
    "lab": "byol"
  },
  "jetlag": {
    "bastion_host": "test.example.com",
    "kubeconfig_path": "/root/kubeconfig"
  },
  "crucible": {
    "git_repo": "https://github.com/perftool-incubator/crucible.git",
    "git_branch": "master"
  },
  "crucible_controller": {
    "target": "bastion"
  },
  "regulus": {
    "jobs": "./1_GROUP/NO-PAO/4IP/INTER-NODE/TCP/2-POD",
    "duration": 10,
    "num_samples": 3
  },
  "lab": {
    "ssh_password": "testpassword"
  }
}
EOF

echo "Test 1: BYOL mode"
if "${SCRIPT_DIR}/validate-config.sh" /tmp/test-byol.json >/dev/null 2>&1; then
    echo "  ✓ Standalone validator: PASS"
else
    echo "  ✗ Standalone validator: FAIL"
    exit 1
fi

# Test using library function
source "${ROOT_DIR}/modules/lib/validate-config.sh"
if validate_quads_config /tmp/test-byol.json >/dev/null 2>&1; then
    echo "  ✓ Library validator: PASS"
else
    echo "  ✗ Library validator: FAIL"
    exit 1
fi
echo ""

# Test 2: scalelab allocate mode
cat > /tmp/test-allocate.json <<EOF
{
  "quads": {
    "mode": "allocate",
    "lab": "scalelab",
    "api_server": "quads.example.com",
    "username": "testuser",
    "password": "testpass",
    "num_hosts": 7,
    "preferred_model": "r750",
    "workload_name": "test"
  },
  "jetlag": {
    "cluster_type": "mno",
    "worker_node_count": 3,
    "ocp_build": "ga",
    "ocp_version": "latest-4.20",
    "network_stack": "ipv4"
  },
  "crucible": {
    "git_repo": "https://github.com/perftool-incubator/crucible.git",
    "git_branch": "master"
  },
  "crucible_controller": {
    "target": "bastion"
  },
  "regulus": {
    "jobs": "./1_GROUP/NO-PAO/4IP/INTER-NODE/TCP/2-POD",
    "duration": 10,
    "num_samples": 3
  },
  "lab": {
    "ssh_password": "testpassword"
  }
}
EOF

echo "Test 2: scalelab allocate mode"
if "${SCRIPT_DIR}/validate-config.sh" /tmp/test-allocate.json >/dev/null 2>&1; then
    echo "  ✓ Standalone validator: PASS"
else
    echo "  ✗ Standalone validator: FAIL"
    exit 1
fi

if validate_quads_config /tmp/test-allocate.json >/dev/null 2>&1; then
    echo "  ✓ Library validator: PASS"
else
    echo "  ✗ Library validator: FAIL"
    exit 1
fi
echo ""

# Test 3: performancelab import mode
cat > /tmp/test-import.json <<EOF
{
  "quads": {
    "mode": "import",
    "lab": "performancelab",
    "api_server": "quads.example.com",
    "username": "testuser",
    "password": "testpass",
    "cloud_name": "cloud23"
  },
  "jetlag": {
    "bastion_host": "bastion.example.com",
    "kubeconfig_path": "/root/kubeconfig"
  },
  "crucible": {
    "git_repo": "https://github.com/perftool-incubator/crucible.git",
    "git_branch": "master"
  },
  "crucible_controller": {
    "target": "bastion"
  },
  "regulus": {
    "jobs": "./1_GROUP/NO-PAO/4IP/INTER-NODE/TCP/2-POD",
    "duration": 10,
    "num_samples": 3
  },
  "lab": {
    "ssh_password": "testpassword"
  }
}
EOF

echo "Test 3: performancelab import mode"
if "${SCRIPT_DIR}/validate-config.sh" /tmp/test-import.json >/dev/null 2>&1; then
    echo "  ✓ Standalone validator: PASS"
else
    echo "  ✗ Standalone validator: FAIL"
    exit 1
fi

if validate_quads_config /tmp/test-import.json >/dev/null 2>&1; then
    echo "  ✓ Library validator: PASS"
else
    echo "  ✗ Library validator: FAIL"
    exit 1
fi
echo ""

# Cleanup
rm -f /tmp/test-*.json

echo "✓ All validator consistency tests passed"
echo ""
echo "NOTE: Library validator uses shared validation logic."
echo "Run this test after modifying validation rules."
