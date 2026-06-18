# ask-claude - AI Assistant for reg-agent

**Optional AI helper for reg-agent configuration and troubleshooting.**

## Requirements (Optional)

ask-claude is **completely optional**. reg-agent works without it.

To use ask-claude, you need:
- Google Cloud account with Vertex AI access
- `gcloud` CLI installed and authenticated
- Python packages: `anthropic`, `google-cloud-aiplatform`

## Setup

If you have Vertex AI access:

```bash
# 1. Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# 2. Run bootstrap (will auto-install dependencies and add shell function)
./bootstrap.sh
```

If bootstrap successfully installs AI dependencies, you'll see:
```
✓ Python dependencies installed
✓ Added 'ask-claude' command to ~/.bashrc
  Run 'source ~/.bashrc' or restart your shell to use it
```

Then activate the function:
```bash
source ~/.bashrc
# or just open a new terminal
```

If it fails (no Vertex AI access), you'll see:
```
⚠  Failed to install AI dependencies (optional)
   AI features (ask-claude) will not be available
```

**This is fine!** reg-agent works perfectly without AI features.

## Usage

After `source ~/.bashrc`, you can use the simple command:

```bash
# Automatic file reading - just mention the file in your question!
ask-claude "review my vars/config.json and tell me if anything looks wrong"
ask-claude "what caused the error in artifacts/logs/installer.log?"
ask-claude "compare vars/config.json and vars/config.json.template"

# QUADS recommendations
ask-claude recommend-quads "I need uperf with 100G NICs"

# General questions
ask-claude "how do I configure cluster-ready mode?"
ask-claude "what's the difference between SNO and MNO?"

# Traditional explicit file analysis
ask-claude analyze-failure artifacts/logs/error.log
ask-claude explain-results artifacts/results/summary.json
```

### Automatic File Detection

ask-claude automatically detects and reads files mentioned in your questions:
- Supports: `.json`, `.yaml`, `.yml`, `.txt`, `.log`, `.md`, `.sh`, `.py`, `.conf`, `.env`
- Handles `.template` files correctly (e.g., `config.json.template`)
- Works with relative paths (`./vars/config.json`) and absolute paths
- Can read multiple files in one question

## What It Does

ask-claude automatically:
- Reads reg-agent documentation (README.md, CLAUDE.md)
- Understands your configuration template
- Calls Claude API via Vertex AI
- Provides context-aware answers about reg-agent

## Troubleshooting

**Error: "AI dependencies not installed"**
- You don't have Vertex AI access or dependencies failed to install
- reg-agent core features still work fine
- Ignore this tool or contact your Google Cloud admin for Vertex AI access

**Error: "Google Cloud authentication required"**
```bash
gcloud auth login
gcloud auth application-default login
```

**Error: "No access to Vertex AI Claude models"**
- Your Google Cloud project doesn't have Claude enabled
- Contact your Google Cloud admin
- Or use a different project with Claude access

## Configuration

Edit `bin/ask-claude.py` if you need to change:
- `PROJECT_ID` - Your Google Cloud project
- `REGION` - Vertex AI region (default: us-east5)
- `MODEL` - Claude model version

## No Vertex AI Access?

If you don't have Vertex AI access, you can:
1. Use reg-agent without AI (recommended)
2. Use Claude Code interface directly (this conversation)
3. Request Vertex AI access from your Google Cloud admin

reg-agent is designed to work completely independently without AI assistance.
