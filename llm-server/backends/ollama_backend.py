"""
Ollama LLM Backend
Free, local LLM option
"""

import requests
import logging
from typing import Optional

class OllamaBackend:
    """Ollama backend for local LLM inference"""

    def __init__(self, url: str, model: str, timeout: int = 120):
        self.url = url
        self.model = model
        self.timeout = timeout
        self.model_name = f"ollama:{model}"

    def is_available(self) -> bool:
        """Check if Ollama is running and model is available"""
        try:
            # Check if Ollama server is running
            response = requests.get(f"{self.url}/api/tags", timeout=5)
            if response.status_code != 200:
                return False

            # Check if model is available
            models = response.json().get('models', [])
            model_names = [m['name'] for m in models]

            return any(self.model in name for name in model_names)

        except Exception as e:
            logging.error(f"Ollama availability check failed: {str(e)}")
            return False

    def complete(
        self,
        prompt: str,
        system: Optional[str] = None,
        max_tokens: int = 4096,
        temperature: float = 0.7
    ) -> str:
        """
        Generate completion using Ollama

        Args:
            prompt: User prompt
            system: System prompt (optional)
            max_tokens: Maximum tokens to generate
            temperature: Sampling temperature

        Returns:
            Generated text
        """
        try:
            # Build messages
            messages = []
            if system:
                messages.append({
                    "role": "system",
                    "content": system
                })

            messages.append({
                "role": "user",
                "content": prompt
            })

            # Call Ollama API
            response = requests.post(
                f"{self.url}/api/chat",
                json={
                    "model": self.model,
                    "messages": messages,
                    "stream": False,
                    "options": {
                        "temperature": temperature,
                        "num_predict": max_tokens
                    }
                },
                timeout=self.timeout
            )

            response.raise_for_status()

            # Extract completion
            result = response.json()
            return result['message']['content']

        except requests.exceptions.RequestException as e:
            logging.error(f"Ollama API error: {str(e)}")
            raise RuntimeError(f"Ollama request failed: {str(e)}")
        except Exception as e:
            logging.error(f"Unexpected error: {str(e)}")
            raise
