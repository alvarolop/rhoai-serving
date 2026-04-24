#!/usr/bin/env python3
"""Download Hugging Face weights into /models for the ModelCar final stage (OpenShift AI / KServe)."""
import os
import sys

from huggingface_hub import snapshot_download


def main() -> int:
    repo = os.environ.get("MODEL_REPO", "TinyLlama/TinyLlama-1.1B-Chat-v1.0").strip()
    dest = os.environ.get("MODEL_DEST", "/models").strip()
    raw_patterns = os.environ.get(
        "HF_ALLOW_PATTERNS",
        "*.safetensors,*.json,*.txt,*.model,tokenizer.json,tokenizer_config.json,merges.txt,vocab.json,special_tokens_map.json",
    )
    allow_patterns = [p.strip() for p in raw_patterns.split(",") if p.strip()]
    token = os.environ.get("HF_TOKEN") or None

    os.makedirs(dest, exist_ok=True)
    snapshot_download(
        repo_id=repo,
        local_dir=dest,
        allow_patterns=allow_patterns,
        token=token,
    )
    print(f"Downloaded {repo!r} -> {dest}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
