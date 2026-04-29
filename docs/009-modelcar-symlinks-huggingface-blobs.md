# ModelCar Symlink Problem with Hugging Face Blob Storage

## Overview

When building ModelCar container images from Hugging Face models, you may encounter a critical issue where the resulting container image contains **symbolic links without their target files**, leading to broken models that cannot be loaded at runtime.

This problem is particularly common with large models like Gemma, Llama, and other modern transformers that use Hugging Face's blob-based storage layout.

## The Problem

### Symptom
After building a ModelCar image and deploying it, the model server fails to start with errors like:
```
FileNotFoundError: [Errno 2] No such file or directory: '/models/model-00001-of-00003.safetensors'
```

### Root Cause

Hugging Face uses a **blob storage layout** with symbolic links to optimize disk usage:

```
~/.cache/huggingface/hub/models--google--gemma-2-2b-it/
├── blobs/
│   ├── 8a5b4d2e...  (actual tensor data, 4.2GB)
│   ├── a3f9c1b7...  (actual tensor data, 4.2GB)
│   └── e7d2c8a4...  (actual tensor data, 1.8GB)
└── snapshots/
    └── abc123def456/
        ├── model-00001-of-00003.safetensors -> ../../blobs/8a5b4d2e...
        ├── model-00002-of-00003.safetensors -> ../../blobs/a3f9c1b7...
        ├── model-00003-of-00003.safetensors -> ../../blobs/e7d2c8a4...
        ├── config.json
        └── tokenizer.json
```

**What happens in the ModelCar build:**

1. **Stage 1 (Downloader)**: `huggingface_hub.snapshot_download()` downloads the model
   - By default uses `local_dir_use_symlinks="auto"` 
   - Creates symlinks in `/models/` pointing to `~/.cache/huggingface/hub/.../blobs/`
   
2. **Stage 2 (Runtime image)**: `COPY --from=downloader /models /models`
   - Docker/Podman `COPY` **only copies the symlinks themselves**
   - The blob targets remain in Stage 1's cache (not copied)
   
3. **Result**: Final image contains broken symlinks
   ```
   /models/model-00001-of-00003.safetensors -> ../../blobs/8a5b4d2e...  (BROKEN!)
   ```

### Why This Happens

The `huggingface_hub` library creates symlinks for efficiency:
- **Deduplication**: Multiple model snapshots can share the same blobs
- **Disk space**: Avoids duplicating multi-gigabyte tensor files
- **Atomic updates**: Snapshots are immutable; only blobs and links change

This is excellent for local development but **incompatible with container layer semantics** where each layer must be self-contained.

## Impact on Different Models

### Models Affected
- **Large models with sharded weights** (Gemma, Llama, Mistral, Qwen, etc.)
  - These use `model-00001-of-NNNNN.safetensors` files
  - Always symlinked when downloaded to `local_dir`
  
- **Models with git-lfs pointers** in their repo
  - Hugging Face Hub uses LFS for files >10MB
  - Downloaded as blobs with symlinks

### Models NOT Affected
- **Very small models** where all files fit in the repo without LFS
  - Example: `TinyLlama-1.1B-Chat-v1.0` (all files <10MB)
  - `snapshot_download` copies actual files, not symlinks

## Solutions

### Solution 1: Disable Symlinks in `snapshot_download()` (Recommended)

Modify `packaging-modelcar/download_model.py` to force copying actual files:

```python
snapshot_download(
    repo_id=repo,
    local_dir=dest,
    allow_patterns=allow_patterns,
    token=token,
    local_dir_use_symlinks=False,  # ← ADD THIS
)
```

**Pros:**
- ✅ Simple one-line fix
- ✅ Works for all models
- ✅ No runtime dependencies on external tools

**Cons:**
- ⚠️ Slightly slower build (actual file copy vs symlink creation)
- ⚠️ Uses more disk space in build context (but final image is the same size)

### Solution 2: Dereference Symlinks During `COPY`

Use `--link` or manual dereference in the Dockerfile:

```dockerfile
# Instead of:
COPY --from=downloader /models /models

# Use find + cp to dereference:
RUN --mount=type=bind,from=downloader,source=/models,target=/tmp/models \
    mkdir -p /models && \
    find /tmp/models -type f -exec cp -L {} /models/ \; && \
    find /tmp/models -type f -name "*.json" -exec cp {} /models/ \;
```

**Pros:**
- ✅ Keeps Stage 1 efficient with symlinks
- ✅ Only dereferences in the final COPY

**Cons:**
- ❌ Complex Dockerfile syntax
- ❌ Harder to maintain
- ❌ Requires careful path handling for nested directories

### Solution 3: Use `cp -L` (Dereference) in Download Script

Add post-processing to `download_model.py`:

```python
import shutil
import glob

# After snapshot_download:
for symlink_path in glob.glob(f"{dest}/**/*.safetensors", recursive=True):
    if os.path.islink(symlink_path):
        target = os.readlink(symlink_path)
        os.unlink(symlink_path)
        shutil.copy2(os.path.join(os.path.dirname(symlink_path), target), symlink_path)
```

**Pros:**
- ✅ Fine-grained control over which files to dereference

**Cons:**
- ❌ More complex Python code
- ❌ Need to handle all potential file extensions
- ❌ Reinvents what `local_dir_use_symlinks=False` already does

## Recommended Approach

**Use Solution 1** (`local_dir_use_symlinks=False`) because:

1. **Officially supported** by `huggingface_hub` for exactly this use case
2. **Minimal code change** (one parameter)
3. **Self-documenting** (clear intent in the code)
4. **Future-proof** (library handles edge cases)

## Implementation

Update `packaging-modelcar/download_model.py`:

```python
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
        local_dir_use_symlinks=False,  # ← CRITICAL: Avoid symlinks in ModelCar images
    )
    print(f"Downloaded {repo!r} -> {dest}", file=sys.stderr)
    return 0
```

## Fixing Existing Model Folders with Symlinks

If you already have a model folder structure with symlinks (e.g., from a previous download, transferred from another system, or provided on external media), you need to dereference the symlinks before building a ModelCar image.

### Identifying the Problem

Check if your model folder has symlinks:

```bash
# List files and look for symlinks (indicated by 'l' in permissions and '->' in output)
ls -lh /path/to/model/

# Example output showing BROKEN symlinks:
# lrwxrwxrwx ... model-00001-of-00003.safetensors -> ../../blobs/8a5b4d2e... (red/broken)
# lrwxrwxrwx ... model-00002-of-00003.safetensors -> ../../blobs/a3f9c1b7... (red/broken)
# -rw-r--r-- ... config.json (normal file, OK)
```

If the symlink targets show as broken (red in color-enabled terminals) or point to `../../blobs/` that don't exist, you have the symlink problem.

### Solution: Dereference Symlinks in Place

#### Option A: Using `rsync` (Recommended)

`rsync` can copy and dereference symlinks while preserving the directory structure:

```bash
# Create a temporary directory for dereferenced files
mkdir -p /tmp/model-fixed

# Copy with symlink dereferencing (-L follows symlinks)
rsync -avL /path/to/model-with-symlinks/ /tmp/model-fixed/

# Verify the result (should show actual files, not symlinks)
ls -lh /tmp/model-fixed/

# Replace the original if verification passes
rm -rf /path/to/model-with-symlinks
mv /tmp/model-fixed /path/to/model-with-symlinks
```

**Pros:**
- ✅ Safe (works on a copy first)
- ✅ Preserves timestamps and permissions
- ✅ Handles nested directories correctly

#### Option B: Using `cp -rL` (Simpler)

For simpler cases without nested complexity:

```bash
# Create a temporary directory
mkdir -p /tmp/model-fixed

# Copy and dereference all symlinks
cp -rL /path/to/model-with-symlinks/* /tmp/model-fixed/

# Verify
ls -lh /tmp/model-fixed/

# Replace original
rm -rf /path/to/model-with-symlinks
mv /tmp/model-fixed /path/to/model-with-symlinks
```

**Note:** `-L` (or `--dereference`) tells `cp` to follow symlinks and copy the actual file content.

#### Option C: In-Place Conversion (Advanced)

For users comfortable with bash scripting, you can dereference symlinks in place:

```bash
cd /path/to/model-with-symlinks

# Find all symlinks and replace them with actual file copies
find . -type l | while read -r symlink; do
    # Get the target path
    target=$(readlink -f "$symlink")
    
    # Only proceed if target exists
    if [ -f "$target" ]; then
        echo "Dereferencing: $symlink -> $target"
        # Remove the symlink
        rm "$symlink"
        # Copy the actual file in its place
        cp "$target" "$symlink"
    else
        echo "WARNING: Broken symlink: $symlink (target not found)"
    fi
done
```

**Warning:** This modifies files in place. Make a backup first if the source data is irreplaceable.

### Building ModelCar with Fixed Folder

Once symlinks are dereferenced, you can build a ModelCar using a local directory:

#### Approach 1: Modify Dockerfile to COPY Local Folder

Create a custom Dockerfile that skips the download stage:

```dockerfile
# Custom ModelCar from local dereferenced folder
FROM registry.access.redhat.com/ubi9/ubi-micro:latest

# Copy the already-dereferenced local model folder
COPY ./model-dereferenced /models
RUN chmod -R a=rX /models

USER 1001
```

Build it:

```bash
# Assuming your dereferenced model is in ./model-dereferenced/
podman build -f Dockerfile.local -t localhost/modelcar-gemma:local .
```

#### Approach 2: Use Multi-Stage with Local COPY

Modify the existing `packaging-modelcar/Dockerfile`:

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-micro:latest

# Copy from local context instead of downloading
COPY ./model-dereferenced /models
RUN chmod -R a=rX /models

USER 1001
```

Then build from the parent directory:

```bash
podman build -f packaging-modelcar/Dockerfile.local \
  --build-context model-dereferenced=/path/to/dereferenced/model \
  -t localhost/modelcar-gemma:local .
```

### Verification After Dereferencing

Verify the fixed folder has actual files:

```bash
# Should show files with actual sizes, NOT symlinks
ls -lh /path/to/model-with-symlinks/

# Example CORRECT output:
# -rw-r--r-- 1 user user 4.2G Apr 29 12:00 model-00001-of-00003.safetensors
# -rw-r--r-- 1 user user 4.2G Apr 29 12:01 model-00002-of-00003.safetensors
# -rw-r--r-- 1 user user  723 Apr 29 12:00 config.json

# Check for any remaining symlinks (should return nothing)
find /path/to/model-with-symlinks -type l
```

## Verification

After fixing, verify the ModelCar image contains actual files, not symlinks:

```bash
# Build the image
podman build -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg MODEL_REPO=google/gemma-2-2b-it \
  -t localhost/modelcar-gemma:test

# Inspect the image
podman run --rm localhost/modelcar-gemma:test ls -lh /models/

# Should show actual files with sizes, NOT symlinks:
# -rw-r--r-- 1 1001 root 4.2G Apr 29 12:00 model-00001-of-00003.safetensors
# -rw-r--r-- 1 1001 root 4.2G Apr 29 12:01 model-00002-of-00003.safetensors
# (NOT: lrwxrwxrwx ... model-00001-of-00003.safetensors -> ../../blobs/...)
```

## References

- Hugging Face Hub Documentation: [Download files from the Hub](https://huggingface.co/docs/huggingface_hub/guides/download#download-an-entire-repository)
- ModelCar for OpenShift AI: [Red Hat Developer Article](https://developers.redhat.com/articles/2025/01/30/build-and-deploy-modelcar-container-openshift-ai)
- Related: `docs/006-chart-scope-and-modelcar-startup-logs.md` (ModelCar integration details)

## Related Issues

- Kueue topology constraints: `docs/005-kueue-topology-tas.md`
- GPU resource allocation: Check `kubectl describe node` for actual vs quota GPU availability
- Chart values structure: `docs/002-namespace-and-resource-identity.md`
