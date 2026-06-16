"""
Anthropic API Backend
Direct Claude API access
"""

import logging
from typing import Optional

try:
    from anthropic import Anthropic
    ANTHROPIC_AVAILABLE = True
except ImportError:
    ANTHROPIC_AVAILABLE = False
    logging.warning("anthropic package not installed - Anthropic API backend unavailable")

class AnthropicAPIBackend:
    """Anthropic API backend for direct Claude access"""

    def __init__(self, api_key: str, model: str, max_tokens: int = 4096):
        if not ANTHROPIC_AVAILABLE:
            raise RuntimeError("anthropic package required for Anthropic API backend")

        if not api_key:
            raise ValueError("ANTHROPIC_API_KEY is required")

        self.api_key = api_key
        self.model = model
        self.default_max_tokens = max_tokens
        self.model_name = f"anthropic:{model}"

        try:
            self.client = Anthropic(api_key=api_key)
        except Exception as e:
            logging.error(f"Failed to initialize Anthropic client: {str(e)}")
            raise

    def is_available(self) -> bool:
        """Check if Anthropic API is accessible"""
        try:
            # Try a minimal test request
            response = self.client.messages.create(
                model=self.model,
                max_tokens=10,
                messages=[{"role": "user", "content": "test"}]
            )
            return True
        except Exception as e:
            logging.error(f"Anthropic API availability check failed: {str(e)}")
            return False

    def complete(
        self,
        prompt: str,
        system: Optional[str] = None,
        max_tokens: int = 4096,
        temperature: float = 0.7
    ) -> str:
        """
        Generate completion using Anthropic API

        Args:
            prompt: User prompt
            system: System prompt (optional)
            max_tokens: Maximum tokens to generate
            temperature: Sampling temperature

        Returns:
            Generated text
        """
        try:
            # Build request
            request_params = {
                "model": self.model,
                "max_tokens": max_tokens,
                "temperature": temperature,
                "messages": [
                    {"role": "user", "content": prompt}
                ]
            }

            if system:
                request_params["system"] = system

            # Call Anthropic API
            response = self.client.messages.create(**request_params)

            # Extract completion
            return response.content[0].text

        except Exception as e:
            logging.error(f"Anthropic API error: {str(e)}")
            raise RuntimeError(f"Anthropic API request failed: {str(e)}")
