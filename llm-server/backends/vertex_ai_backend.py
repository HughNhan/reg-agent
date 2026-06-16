"""
Vertex AI Claude Backend
Google Cloud's hosted Claude API
"""

import logging
from typing import Optional

try:
    from anthropic import AnthropicVertex
    VERTEX_AVAILABLE = True
except ImportError:
    VERTEX_AVAILABLE = False
    logging.warning("anthropic package not installed - Vertex AI backend unavailable")

class VertexAIBackend:
    """Vertex AI Claude backend"""

    def __init__(self, project_id: str, location: str, model: str):
        if not VERTEX_AVAILABLE:
            raise RuntimeError("anthropic package required for Vertex AI backend")

        self.project_id = project_id
        self.location = location
        self.model = model
        self.model_name = f"vertex-ai:{model}"

        try:
            self.client = AnthropicVertex(
                project_id=project_id,
                region=location
            )
        except Exception as e:
            logging.error(f"Failed to initialize Vertex AI client: {str(e)}")
            raise

    def is_available(self) -> bool:
        """Check if Vertex AI is accessible"""
        try:
            # Try a minimal test request
            response = self.client.messages.create(
                model=self.model,
                max_tokens=10,
                messages=[{"role": "user", "content": "test"}]
            )
            return True
        except Exception as e:
            logging.error(f"Vertex AI availability check failed: {str(e)}")
            return False

    def complete(
        self,
        prompt: str,
        system: Optional[str] = None,
        max_tokens: int = 4096,
        temperature: float = 0.7
    ) -> str:
        """
        Generate completion using Vertex AI Claude

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

            # Call Vertex AI
            response = self.client.messages.create(**request_params)

            # Extract completion
            return response.content[0].text

        except Exception as e:
            logging.error(f"Vertex AI API error: {str(e)}")
            raise RuntimeError(f"Vertex AI request failed: {str(e)}")
