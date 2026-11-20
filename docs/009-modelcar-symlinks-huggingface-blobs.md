# 009 — Appendix: ModelCar images with dangling Hugging Face symlinks

> Appendix, mostly historical. Resolved in `huggingface_hub` 0.24+ (see below); kept for troubleshooting older tooling and local folders.

**TL;DR**

- A ModelCar built from a Hugging Face **cache folder** can contain **symlinks without their targets**: the pod fails with `FileNotFoundError: /models/model-0000X-of-0000Y.safetensors`.
- Cause: the cache stores weights in `blobs/` and exposes them in `snapshots/` as symlinks; copying only `snapshots/` copies the links, not the data.
- Fix: download with `snapshot_download(local_dir=...)` (real files, no symlinks in `huggingface_hub` 0.24+), or dereference with `cp -rL`.
- `packaging-modelcar/` is safe: `download_model.py` uses `snapshot_download(local_dir=...)`, so `/models` holds real files. Its final `RUN` also fails the build if `/models` has fewer `.safetensors` than the download produced (that catches a missing `COPY` layer, not symlinks).

## What goes wrong

```
~/.cache/huggingface/hub/models--<org>--<model>/
├── blobs/<hash>                        real data (GBs)
└── snapshots/<rev>/
    ├── model-00001-of-00003.safetensors  ──symlink──▶ ../../blobs/<hash>
    └── config.json                       normal file

COPY snapshots/<rev> /models   ─▶  the image holds the links, not blobs/  ─▶  broken at runtime
```

It hits large multi-shard models first (Gemma, Llama), because small ones are often a single real file.

## Fixes

| Option | When |
|--------|------|
| `snapshot_download(repo_id, local_dir="/models")` | default today (`huggingface_hub` 0.24+); `local_dir_use_symlinks` is deprecated |
| `snapshot_download(..., local_dir_use_symlinks=False)` | older `huggingface_hub` versions |
| `cp -rL <snapshot> <dest>` | the folder already exists and you cannot re-download |

## Check and repair an existing folder

```bash
# Symlinks show up as "l" in the permissions and "->" in the listing
ls -la <folder> | grep -- '->'
find <folder> -type l

# Dereference into a clean copy, verify, then replace
cp -rL <folder> <folder>.fixed
find <folder>.fixed -type l | wc -l     # must print 0
mv <folder> <folder>.bak && mv <folder>.fixed <folder>
```

`rsync -aL <folder>/ <folder>.fixed/` does the same and can resume.

## In the image

- Put real files in `/models` (the Dockerfile in `packaging-modelcar/` does).
- After the build, `podman run --rm --entrypoint ls <image> -la /models` must show regular files with sizes, not `->` entries.
- A pod stuck in `Init` or crash-looping right after the model is mounted usually means an empty or truncated `/models`: check this before blaming vLLM.
