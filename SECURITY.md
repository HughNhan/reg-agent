# Security and Privacy Guidelines

This document outlines security and privacy practices for the reg-agent repository.

## Private/Confidential Information - DO NOT COMMIT

The following types of information should **NEVER** be committed to the repository:

### Credentials and Secrets
- ❌ Passwords (QUADS, SSH, BMC, any service)
- ❌ API tokens or keys
- ❌ SSH private keys
- ❌ OpenShift pull secrets
- ❌ Service account credentials

### Infrastructure Details
- ❌ Specific hostnames (e.g., `my-r740xd.my.com`)
- ❌ Internal IP addresses (non-RFC example ranges)
- ❌ MAC addresses
- ❌ BMC/IPMI addresses
- ❌ Specific cloud names with identifiable info (e.g., `cloud04-yourteam`)
- ❌ Assignment IDs from actual allocations

### Personal Information
- ❌ Usernames or email addresses
- ❌ Team names or project codes
- ❌ Internal URLs or endpoints

## Acceptable Generic Examples

The following are acceptable for documentation and examples:

### Generic Placeholders
- ✅ `quads.lab.example.com` - Generic QUADS server
- ✅ `bastion.example.com` - Generic bastion host
- ✅ `cloudNN` - Generic cloud identifier
- ✅ `youruser` - Generic username
- ✅ `<your-password>` - Password placeholder

### Public Information
- ✅ `scalelab`, `performancelab` - Public my company lab names
- ✅ `198.18.0.x` - RFC 2544 reserved test range
- ✅ `example.com`, `example.net` - RFC 2606 reserved domains
- ✅ Tool names and commands
- ✅ Public documentation links

## Before Committing

### 1. Run the Scrubbing Script

```bash
./scrub-private-info.sh
```

This will automatically replace private information with generic placeholders.

### 2. Manual Review

Check for any remaining private information:

```bash
# Search for common private patterns
git grep -i "REDACTED\|rdu[0-9]\|w37-h15\|f11-h"

# Search for specific hostnames
git grep -E "[a-z0-9-]+\.(scalelab|performancelab)\.redhat\.com"

# Search for IP addresses (review manually)
git grep -E "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"

# Search for cloud names with numbers
git grep -E "cloud[0-9]{2}"
```

### 3. Review Configuration Files

Ensure no generated files with private data are committed:

```bash
# Check vars/ directory
ls -la vars/

# Should show only .gitkeep or README files
# config.env and state.env should NOT appear
```

## Configuration Best Practices

### Use Environment Variables

Never hardcode secrets in scripts. Always use environment variables or configuration files:

```bash
# ❌ Bad
PASSWORD="secret123"

# ✅ Good
PASSWORD="${LAB_SSH_PASSWORD}"  # From config.env (gitignored)
```

### Prompt for Sensitive Input

```bash
# ✅ Good - prompt with no echo
read -sp "Lab SSH password: " LAB_SSH_PASSWORD
```

### Use Configuration Files (Gitignored)

```bash
# vars/config.env - automatically gitignored
QUADS_PASSWORD=your-password-here
LAB_SSH_PASSWORD=your-lab-password
```

## Automated Protection

### .gitignore

The repository `.gitignore` automatically excludes:

- `vars/config.env` - User configuration with secrets
- `vars/state.env` - Deployment state with hostnames
- `modules/*/generated/` - Module-generated files
- `pull-secret.txt` - OpenShift pull secret
- `*.key`, `*.pem` - SSH/TLS keys

### Pre-commit Hooks (Optional)

Consider adding a pre-commit hook to scan for private data:

```bash
#!/bin/bash
# .git/hooks/pre-commit

# Check for common private patterns
if git diff --cached | grep -E "REDACTED|w37-h15|f11-h|rdu[0-9]@"; then
    echo "ERROR: Possible private information detected!"
    echo "Please review your changes before committing."
    exit 1
fi
```

## Incident Response

If private information is accidentally committed:

1. **DO NOT** simply delete the file in a new commit
2. **Rewrite history** to remove it completely:

```bash
# Remove file from all commits
git filter-branch --force --index-filter \
  'git rm --cached --ignore-unmatch path/to/private/file' \
  --prune-empty --tag-name-filter cat -- --all

# Force push (coordinate with team first!)
git push --force --all
```

3. **Rotate credentials** that were exposed
4. **Notify security team** if required

## Public Release Checklist

Before making the repository public:

- [ ] Run `./scrub-private-info.sh`
- [ ] Manual review of all `.sh`, `.md`, `Makefile` files
- [ ] Verify `.gitignore` is comprehensive
- [ ] Check `git log` for historical commits with private data
- [ ] Test configuration prompts don't reveal defaults
- [ ] Review all example commands and outputs
- [ ] Ensure documentation uses generic examples only
- [ ] Check for embedded credentials in scripts
- [ ] Verify no actual assignment IDs or cloud names in docs
- [ ] Remove any internal-only comments or notes

## Contact

For security concerns or questions, contact the repository maintainers.
