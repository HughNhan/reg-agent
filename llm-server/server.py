#!/usr/bin/env python3
"""
reg-agent LLM Server
Location-independent HTTP API for AI features
"""

import os
import sys
import logging
from typing import Dict, Any, Optional
from flask import Flask, request, jsonify
import yaml

# Add backends directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'backends'))

from ollama_backend import OllamaBackend
from vertex_ai_backend import VertexAIBackend
from anthropic_api_backend import AnthropicAPIBackend

app = Flask(__name__)

# Global backend instance
llm_backend = None
config = None

def load_config(config_path: str = None) -> Dict[str, Any]:
    """Load configuration from YAML file"""
    if config_path is None:
        config_path = os.path.join(os.path.dirname(__file__), 'config.yaml')

    with open(config_path, 'r') as f:
        return yaml.safe_load(f)

def initialize_backend(config: Dict[str, Any]):
    """Initialize the configured LLM backend"""
    backend_type = config['backend']['type']

    if backend_type == 'ollama':
        backend_config = config['backend']['ollama']
        return OllamaBackend(
            url=backend_config['url'],
            model=backend_config['model'],
            timeout=backend_config.get('timeout', 120)
        )
    elif backend_type == 'vertex-ai':
        backend_config = config['backend']['vertex_ai']
        return VertexAIBackend(
            project_id=backend_config['project_id'],
            location=backend_config['location'],
            model=backend_config['model']
        )
    elif backend_type == 'anthropic-api':
        backend_config = config['backend']['anthropic_api']
        api_key = os.getenv('ANTHROPIC_API_KEY', backend_config.get('api_key', ''))
        return AnthropicAPIBackend(
            api_key=api_key,
            model=backend_config['model'],
            max_tokens=backend_config.get('max_tokens', 4096)
        )
    else:
        raise ValueError(f"Unknown backend type: {backend_type}")

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'backend': config['backend']['type'],
        'version': '1.0.0'
    })

@app.route('/complete', methods=['POST'])
def complete():
    """
    Text completion endpoint

    Request body:
    {
        "prompt": "User query text",
        "system": "Optional system prompt",
        "max_tokens": 4096,
        "temperature": 0.7
    }

    Response:
    {
        "completion": "LLM response text",
        "model": "model-name",
        "backend": "backend-type"
    }
    """
    try:
        data = request.get_json()

        if not data or 'prompt' not in data:
            return jsonify({'error': 'Missing required field: prompt'}), 400

        prompt = data['prompt']
        system = data.get('system', None)
        max_tokens = data.get('max_tokens', 4096)
        temperature = data.get('temperature', 0.7)

        # Call backend
        completion = llm_backend.complete(
            prompt=prompt,
            system=system,
            max_tokens=max_tokens,
            temperature=temperature
        )

        return jsonify({
            'completion': completion,
            'model': llm_backend.model_name,
            'backend': config['backend']['type']
        })

    except Exception as e:
        logging.error(f"Completion error: {str(e)}", exc_info=True)
        return jsonify({'error': str(e)}), 500

@app.route('/parse-use-case', methods=['POST'])
def parse_use_case():
    """
    Parse natural language use case into structured test request

    Request body:
    {
        "query": "I want to test OVN host network performance with iperf"
    }

    Response:
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
    """
    try:
        data = request.get_json()

        if not data or 'query' not in data:
            return jsonify({'error': 'Missing required field: query'}), 400

        query = data['query']

        # System prompt for use case parsing
        system_prompt = """You are a Regulus performance testing expert. Parse user queries into structured test requests.

Available test categories:
- Network: ovn-k, sriov, macvlan, hostnet, iperf, uperf
- CPU: pod-densities, cyclictest, oslat
- Storage: fio
- Hardware acceleration: dpdk, sriov

Return JSON with:
- intent: test intent (performance_test, benchmark, etc)
- test_type: category (network, cpu, storage, etc)
- test_suite: specific Regulus test string
- parameters: test parameters (num_samples, duration, etc)
- confidence: 0.0-1.0

Example:
Query: "Test OVN host network with iperf"
Response: {
  "intent": "performance_test",
  "test_type": "network",
  "test_suite": "ovn-k:hostnet:iperf-tcp-1200",
  "parameters": {"num_samples": 3, "duration": 60},
  "confidence": 0.95
}"""

        # Call LLM
        response = llm_backend.complete(
            prompt=f"Parse this test request: {query}",
            system=system_prompt,
            max_tokens=1024,
            temperature=0.3
        )

        # Parse JSON response
        import json
        try:
            parsed = json.loads(response)
            return jsonify(parsed)
        except json.JSONDecodeError:
            # LLM didn't return valid JSON, return raw response
            return jsonify({
                'error': 'Failed to parse LLM response as JSON',
                'raw_response': response
            }), 500

    except Exception as e:
        logging.error(f"Use case parsing error: {str(e)}", exc_info=True)
        return jsonify({'error': str(e)}), 500

@app.route('/backend/info', methods=['GET'])
def backend_info():
    """Get information about the configured backend"""
    return jsonify({
        'type': config['backend']['type'],
        'model': llm_backend.model_name,
        'available': llm_backend.is_available()
    })

def main():
    global config, llm_backend

    # Load configuration
    config_path = os.getenv('REG_AGENT_LLM_CONFIG', None)
    config = load_config(config_path)

    # Setup logging
    logging.basicConfig(
        level=getattr(logging, config['logging']['level']),
        format=config['logging']['format']
    )

    logging.info("Starting reg-agent LLM server")
    logging.info(f"Backend: {config['backend']['type']}")

    # Initialize backend
    try:
        llm_backend = initialize_backend(config)
        logging.info(f"Backend initialized: {llm_backend.model_name}")
    except Exception as e:
        logging.error(f"Failed to initialize backend: {str(e)}")
        sys.exit(1)

    # Check backend availability
    if not llm_backend.is_available():
        logging.warning(f"Backend {config['backend']['type']} is not available")
        logging.warning("Server will start but may not respond to requests")

    # Start server
    host = config['server']['host']
    port = config['server']['port']
    debug = config['server']['debug']

    logging.info(f"Starting server on {host}:{port}")
    app.run(host=host, port=port, debug=debug)

if __name__ == '__main__':
    main()
