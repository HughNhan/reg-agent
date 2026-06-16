# reg-agent LLM Server

Location-independent HTTP API for AI features in reg-agent.

## Overview

The LLM server provides a simple HTTP API for AI-powered features like natural language test request parsing. It supports multiple LLM backends (Ollama, Vertex AI Claude, Anthropic API) and can be deployed anywhere - users just need to point to it via URL.

## Quick Start

### 1. Install Dependencies

```bash
cd /home/hnhan/reg-agent
source .venv/bin/activate
pip install -r requirements.txt
```

### 2. Configure Backend

Edit `config.yaml` and set your backend type:

```yaml
backend:
  type: ollama  # or vertex-ai, anthropic-api
```

#### Ollama (Default - Free, Local)

1. Install Ollama: https://ollama.ai
2. Pull a model: `ollama pull llama3.1:8b`
3. Ollama runs on `http://localhost:11434` by default

#### Vertex AI Claude

1. Enable Claude in Google Cloud Model Garden
2. Set GCP project in `config.yaml`:
   ```yaml
   backend:
     type: vertex-ai
     vertex_ai:
       project_id: your-gcp-project
       location: us-east5
       model: claude-3-5-sonnet-v2@20241022
   ```
3. Authenticate: `gcloud auth application-default login`

#### Anthropic API

1. Get API key from https://console.anthropic.com
2. Set environment variable: `export ANTHROPIC_API_KEY=sk-ant-...`
3. Configure in `config.yaml`:
   ```yaml
   backend:
     type: anthropic-api
     anthropic_api:
       model: claude-3-5-sonnet-20241022
   ```

### 3. Start Server

```bash
./llm-ctl.sh start
```

### 4. Test Server

```bash
# Health check
curl http://localhost:8000/health

# Backend info
curl http://localhost:8000/backend/info

# Text completion
curl -X POST http://localhost:8000/complete \
  -H "Content-Type: application/json" \
  -d '{"prompt": "What is Kubernetes?"}'

# Parse use case (AI feature)
curl -X POST http://localhost:8000/parse-use-case \
  -H "Content-Type: application/json" \
  -d '{"query": "I want to test OVN host network performance with iperf"}'
```

## Management Commands

```bash
./llm-ctl.sh start    # Start server
./llm-ctl.sh stop     # Stop server
./llm-ctl.sh restart  # Restart server
./llm-ctl.sh status   # Show status
./llm-ctl.sh logs     # Tail logs
```

## Using from reg-agent

Set the LLM server URL in your reg-agent configuration:

```bash
# In vars/config.env
ENABLE_LLM=true
REG_AGENT_LLM_URL=http://localhost:8000
```

Or if the LLM server is on another machine:

```bash
REG_AGENT_LLM_URL=http://llm-server.example.com:8000
```

## API Endpoints

### GET /health

Health check endpoint.

**Response:**
```json
{
  "status": "healthy",
  "backend": "ollama",
  "version": "1.0.0"
}
```

### GET /backend/info

Get backend information.

**Response:**
```json
{
  "type": "ollama",
  "model": "ollama:llama3.1:8b",
  "available": true
}
```

### POST /complete

General text completion.

**Request:**
```json
{
  "prompt": "User query",
  "system": "Optional system prompt",
  "max_tokens": 4096,
  "temperature": 0.7
}
```

**Response:**
```json
{
  "completion": "LLM response text",
  "model": "ollama:llama3.1:8b",
  "backend": "ollama"
}
```

### POST /parse-use-case

Parse natural language test request into structured format.

**Request:**
```json
{
  "query": "I want to test OVN host network performance with iperf"
}
```

**Response:**
```json
{
  "intent": "performance_test",
  "test_type": "network",
  "test_suite": "ovn-k:hostnet:iperf-tcp-1200",
  "parameters": {
    "num_samples": 3,
    "duration": 60
  },
  "confidence": 0.95
}
```

## Deployment Scenarios

### Single User (Local)

Run on localhost, default configuration:

```bash
./llm-ctl.sh start
# Use: REG_AGENT_LLM_URL=http://localhost:8000
```

### Team Server (Shared)

1. Deploy on shared infrastructure
2. Configure backend with team credentials
3. Update firewall to allow port 8000
4. Team members use: `REG_AGENT_LLM_URL=http://llm-server.corp.com:8000`

### Multi-location

1. Start server on any accessible machine
2. Server can be moved between machines
3. Just update `REG_AGENT_LLM_URL` to point to current location

## Troubleshooting

### Server won't start

Check logs:
```bash
cat llm-server.log
```

Common issues:
- Port 8000 already in use: Change `port` in `config.yaml`
- Missing dependencies: `pip install -r ../requirements.txt`
- Backend not configured: Edit `config.yaml`

### Backend not available

Check backend status:
```bash
curl http://localhost:8000/backend/info
```

**Ollama:**
- Ensure Ollama is running: `ollama list`
- Model must be pulled: `ollama pull llama3.1:8b`

**Vertex AI:**
- Check GCP auth: `gcloud auth application-default login`
- Verify Claude is enabled in Model Garden
- Check project ID in `config.yaml`

**Anthropic API:**
- Verify `ANTHROPIC_API_KEY` is set
- Check API key is valid

### Connection refused

Ensure server is running:
```bash
./llm-ctl.sh status
```

If firewall issues, check port 8000 is open:
```bash
sudo firewall-cmd --add-port=8000/tcp --permanent
sudo firewall-cmd --reload
```

## Architecture

```
reg-agent CLI
    ↓
    HTTP Request
    ↓
LLM Server (Flask)
    ↓
Backend Adapter (Ollama/Vertex AI/Anthropic)
    ↓
LLM Model
```

The server architecture allows:
- **Location independence**: Deploy anywhere, access via URL
- **Backend flexibility**: Switch between Ollama, Vertex AI, Anthropic without changing client
- **Multi-user access**: One server, many users
- **Credential isolation**: Only server needs LLM credentials
