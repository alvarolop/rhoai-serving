#!/usr/bin/env python3
"""Group a downloaded model into size-bounded layer directories for the ModelCar image.

Weights are split into /models-chunk-NN directories of about LAYER_MAX_GB each (default 5), so the
layers are small and the container runtime can pull them in parallel. Everything that is not a
*.safetensors file (config, tokenizer, chat template...) goes to /models-other. The Dockerfile COPYs
each directory as its own layer, so it never has to be edited per model.

A single file bigger than LAYER_MAX_GB cannot be split: it gets a layer of its own.
The build fails (instead of silently dropping weights) if the model needs more than MAX_CHUNKS layers.
"""
import os
import shutil
import sys

SRC = os.environ.get("MODEL_DEST", "/models")
OTHER = "/models-other"
CHUNK = "/models-chunk-{:02d}"
MAX_CHUNKS = int(os.environ.get("MAX_CHUNKS", "10"))
LIMIT = float(os.environ.get("LAYER_MAX_GB", "5")) * 1e9


def main() -> int:
    os.makedirs(OTHER, exist_ok=True)
    for i in range(1, MAX_CHUNKS + 1):
        os.makedirs(CHUNK.format(i), exist_ok=True)

    # Top-level files only: this leaves the huggingface_hub ".cache" directory behind.
    files = sorted(f for f in os.listdir(SRC) if os.path.isfile(os.path.join(SRC, f)))
    chunk, used = 1, 0
    for name in files:
        path = os.path.join(SRC, name)
        if not name.endswith(".safetensors"):
            shutil.move(path, os.path.join(OTHER, name))
            continue
        size = os.path.getsize(path)
        if used and used + size > LIMIT:
            chunk, used = chunk + 1, 0
        if chunk > MAX_CHUNKS:
            sys.exit(f"ERROR: the model needs more than {MAX_CHUNKS} layers of {LIMIT / 1e9:.0f} GB. "
                     f"Raise LAYER_MAX_GB, or MAX_CHUNKS and the COPY lines in the Dockerfile.")
        shutil.move(path, os.path.join(CHUNK.format(chunk), name))
        used += size

    for d in [OTHER] + [CHUNK.format(i) for i in range(1, MAX_CHUNKS + 1)]:
        os.chmod(d, 0o755)
        for f in os.listdir(d):
            os.chmod(os.path.join(d, f), 0o644)
    print(f"Split {SRC}: {chunk} weight layer(s) of about {LIMIT / 1e9:.0f} GB + config files", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
