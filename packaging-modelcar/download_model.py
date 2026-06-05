#!/usr/bin/env python3
"""Download Hugging Face weights into /models for the ModelCar final stage (OpenShift AI / KServe)."""
import os
import sys

from huggingface_hub import snapshot_download


def main() -> int:
    repo = os.environ.get("MODEL_REPO", "TinyLlama/TinyLlama-1.1B-Chat-v1.0").strip()
    dest = os.environ.get("MODEL_DEST", "/models").strip()

    # Download only essential files for vLLM
    # vLLM uses standard HuggingFace format (model-*.safetensors), NOT consolidated-*.safetensors
    raw_patterns = os.environ.get(
        "HF_ALLOW_PATTERNS",
        "*.safetensors,*.json,*.txt,*.model,tokenizer.json,tokenizer_config.json,merges.txt,vocab.json,special_tokens_map.json",
    )
    allow_patterns = [p.strip() for p in raw_patterns.split(",") if p.strip()]

    # Exclude Mistral's consolidated format (vLLM doesn't need it)
    # This prevents downloading duplicate weights (~50% size reduction for Mistral models)
    raw_ignore = os.environ.get("HF_IGNORE_PATTERNS", "consolidated*.safetensors")
    ignore_patterns = [p.strip() for p in raw_ignore.split(",") if p.strip()] if raw_ignore else None

    token = os.environ.get("HF_TOKEN") or None

    os.makedirs(dest, exist_ok=True)
    snapshot_download(
        repo_id=repo,
        local_dir=dest,
        allow_patterns=allow_patterns,
        ignore_patterns=ignore_patterns,
        token=token,
    )
    print(f"Downloaded {repo!r} -> {dest}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
