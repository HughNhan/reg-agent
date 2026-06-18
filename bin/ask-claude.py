#!/usr/bin/env python3
"""
Minimal Claude helper for reg-agent analysis tasks.
Usage: bin/ask-claude <task> [file]

Examples:
  bin/ask-claude analyze-failure artifacts/logs/installer.log
  bin/ask-claude explain-results artifacts/results/summary.json
  bin/ask-claude recommend-quads "I need 3 SNO nodes with 28 cores"
"""
import sys
import json
from pathlib import Path
from anthropic import AnthropicVertex

PROJECT_ID = "itpc-gcp-pnd-pe-eng-claude"
REGION = "us-east5"
MODEL = "claude-sonnet-4-6"

def load_reg_agent_context() -> str:
    """Load reg-agent documentation for context"""
    script_dir = Path(__file__).parent.parent  # Go up to reg-agent-clone/
    context_parts = []

    # Read key documentation files
    docs = [
        script_dir / "README.md",
        script_dir / "CLAUDE.md",
        script_dir / "vars" / "config.json.template",
        script_dir / "config" / "config.schema.json",
    ]

    for doc in docs:
        if doc.exists():
            try:
                content = doc.read_text()
                context_parts.append(f"=== {doc.name} ===\n{content}\n")
            except:
                pass

    if context_parts:
        return "\n".join(context_parts)
    return ""

def ask_claude(prompt: str, context: str = "") -> str:
    """Send prompt to Claude via Vertex AI"""
    try:
        client = AnthropicVertex(project_id=PROJECT_ID, region=REGION)
    except Exception as e:
        error_msg = str(e).lower()
        if "credentials" in error_msg or "authentication" in error_msg or "unauthorized" in error_msg:
            print("Error: Google Cloud authentication required.", file=sys.stderr)
            print("", file=sys.stderr)
            print("Please authenticate with:", file=sys.stderr)
            print("  gcloud auth login", file=sys.stderr)
            print("  gcloud auth application-default login", file=sys.stderr)
            print("", file=sys.stderr)
            print("Or check your project access:", file=sys.stderr)
            print(f"  gcloud config set project {PROJECT_ID}", file=sys.stderr)
            sys.exit(1)
        else:
            raise

    # Always include reg-agent context as system knowledge
    reg_agent_context = load_reg_agent_context()

    full_prompt = prompt
    if reg_agent_context:
        full_prompt = f"You are helping with reg-agent, a CI/CD orchestration tool for OpenShift performance testing.\n\n{reg_agent_context}\n\n"

    if context:
        full_prompt += f"Additional context:\n{context}\n\n"

    full_prompt += f"User request: {prompt}"

    try:
        message = client.messages.create(
            model=MODEL,
            max_tokens=2048,
            messages=[{"role": "user", "content": full_prompt}],
        )
        return message.content[0].text
    except Exception as e:
        error_msg = str(e).lower()
        if "permission" in error_msg or "access" in error_msg or "forbidden" in error_msg:
            print("Error: No access to Vertex AI Claude models.", file=sys.stderr)
            print("", file=sys.stderr)
            print("Your project may not have Claude enabled.", file=sys.stderr)
            print("Contact your Google Cloud admin or use a different project.", file=sys.stderr)
            sys.exit(1)
        else:
            raise

def extract_and_read_files(text: str) -> tuple[str, str]:
    """Extract file paths from text and read them. Returns (modified_text, file_contents)"""
    import re
    import os

    # Find potential file paths in the text - match longer patterns first
    # Patterns: ./path, /path, path/to/file.ext, file.ext.template, etc.
    file_pattern = r'(?:\.?/)?(?:[\w\-]+/)*[\w\-\.]+\.(?:json\.template|yaml\.template|yml\.template|json|yaml|yml|txt|log|md|sh|py|conf|env)'

    files_content = []
    modified_text = text
    processed_files = set()

    # Find all matches and sort by length (longest first) to handle .template files properly
    matches = list(re.finditer(file_pattern, text))
    matches.sort(key=lambda m: len(m.group(0)), reverse=True)

    for match in matches:
        potential_file = match.group(0)

        # Skip if we already processed this file or a longer version of it
        if any(potential_file in processed for processed in processed_files):
            continue

        # Try to resolve relative to current directory first, then script directory
        for base_path in [os.getcwd(), Path(__file__).parent.parent]:
            file_path = Path(base_path) / potential_file.lstrip('./')
            if file_path.exists() and file_path.is_file():
                try:
                    content = file_path.read_text()
                    files_content.append(f"=== {potential_file} ===\n{content}\n")
                    modified_text = modified_text.replace(potential_file, f"{potential_file} (contents loaded)")
                    processed_files.add(potential_file)
                    break
                except:
                    pass

    return modified_text, "\n".join(files_content) if files_content else ""

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    task = sys.argv[1]
    arg = sys.argv[2] if len(sys.argv) > 2 else None

    # Check if arg is a file or a text query
    context = ""
    query = ""
    if arg and Path(arg).is_file():
        # It's a file - read it as context
        try:
            context = Path(arg).read_text()
        except Exception as e:
            print(f"Error reading {arg}: {e}", file=sys.stderr)
            sys.exit(1)
    elif arg:
        # It's a text query
        query = arg

    # Also check if the task itself contains file references
    full_query = f"{task} {query}".strip()
    modified_query, auto_context = extract_and_read_files(full_query)
    if auto_context:
        context = auto_context + "\n" + context

    # Task-specific prompts
    if task == "analyze-failure":
        prompt = "Analyze this log and identify the root cause of failure. Be specific and concise."
    elif task == "explain-results":
        prompt = "Explain these test results. Highlight any anomalies or performance concerns."
    elif task == "recommend-quads":
        prompt = f"Recommend QUADS server configuration for reg-agent based on this requirement: {query or 'general performance testing'}"
    else:
        # Custom query - use modified query that shows which files were loaded
        prompt = modified_query if auto_context else (f"{task}: {query}" if query else task)

    try:
        response = ask_claude(prompt, context)
        print(response)
    except Exception as e:
        print(f"Error calling Claude: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
