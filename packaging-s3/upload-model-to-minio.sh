#!/usr/bin/env bash
# Upload a small model tree to in-cluster MinIO (S3 API) for KServe / OpenShift AI storageUri-style flows.
#
# Defaults match rhoai-gitops/components/minio (see application-minio.yaml): namespace "minio",
# Service "minio", API port 9000, root user minio / minio123 unless overridden by env vars.
#
# Typical use from your laptop (requires oc, aws CLI v2, and Python+huggingface_hub for --hf-repo):
#   1) oc port-forward -n "${MINIO_NAMESPACE:-minio}" "svc/${MINIO_SERVICE_NAME:-minio}" 9000:9000
#   2) In another shell:
#        export MINIO_ENDPOINT=http://127.0.0.1:9000
#        ./packaging-s3/upload-model-to-minio.sh --bucket rhoai-demo-models --prefix tinyllama-1.1b \
#          --hf-repo TinyLlama/TinyLlama-1.1B-Chat-v1.0
#   Or sync an existing directory:
#        ./packaging-s3/upload-model-to-minio.sh --bucket rhoai-demo-models --prefix my-run-001 \
#          --source "$HOME/models/my-export"
#
# Wire the bucket in Helm: set model.connection.protocol: s3, model.connection.s3.*, and
# model.connection.s3.path to the same prefix (see chart/values-example-minio-s3-tinyllama.yaml).

set -euo pipefail

BUCKET=""
PREFIX=""
SOURCE=""
HF_REPO=""
ENDPOINT="${MINIO_ENDPOINT:-http://127.0.0.1:9000}"
ACCESS_KEY="${MINIO_ACCESS_KEY:-${AWS_ACCESS_KEY_ID:-minio}}"
SECRET_KEY="${MINIO_SECRET_KEY:-${AWS_SECRET_ACCESS_KEY:-minio123}}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

usage() {
  cat <<'EOF'
Upload a model directory (or Hugging Face snapshot) to MinIO/S3 for KServe-style URIs.

Usage:
  packaging-s3/upload-model-to-minio.sh --bucket <name> [--prefix <path>] (--source <dir> | --hf-repo <org/name>)
                                        [--endpoint <url>]

Env (defaults suit rhoai-gitops in-cluster Minio + oc port-forward):
  MINIO_ENDPOINT        default http://127.0.0.1:9000
  MINIO_ACCESS_KEY      default minio
  MINIO_SECRET_KEY      default minio123
  AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY  (aliases for the above)
  AWS_DEFAULT_REGION    default us-east-1
  HF_TOKEN              optional for gated --hf-repo models
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket) BUCKET="${2:?}"; shift 2 ;;
    --prefix) PREFIX="${2:?}"; shift 2 ;;
    --source) SOURCE="${2:?}"; shift 2 ;;
    --hf-repo) HF_REPO="${2:?}"; shift 2 ;;
    --endpoint) ENDPOINT="${2:?}"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 1 ;;
  esac
done

if [[ -z "$BUCKET" ]]; then
  echo "error: --bucket is required" >&2
  usage 1
fi

if [[ -n "$SOURCE" && -n "$HF_REPO" ]]; then
  echo "error: pass only one of --source or --hf-repo" >&2
  exit 1
fi
if [[ -z "$SOURCE" && -z "$HF_REPO" ]]; then
  echo "error: provide --source <dir> or --hf-repo <org/model>" >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "error: aws CLI not found (install awscli v2)." >&2
  exit 1
fi

UPLOAD_DIR=""
cleanup() {
  if [[ -n "${UPLOAD_DIR}" && -d "${UPLOAD_DIR}" ]]; then
    rm -rf "${UPLOAD_DIR}"
  fi
}
trap cleanup EXIT

if [[ -n "$HF_REPO" ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 required for --hf-repo" >&2
    exit 1
  fi
  UPLOAD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rhoai-minio-model.XXXXXX")"
  export HUGGINGFACE_HUB_REPO="$HF_REPO"
  export HUGGINGFACE_HUB_DEST="$UPLOAD_DIR"
  export HF_TOKEN="${HF_TOKEN:-}"
  python3 <<'PY'
import os
from huggingface_hub import snapshot_download

repo = os.environ["HUGGINGFACE_HUB_REPO"]
dest = os.environ["HUGGINGFACE_HUB_DEST"]
token = os.environ.get("HF_TOKEN") or None
patterns = [
    "*.safetensors",
    "*.json",
    "*.txt",
    "*.model",
    "tokenizer.json",
    "tokenizer_config.json",
    "merges.txt",
    "vocab.json",
    "special_tokens_map.json",
]
snapshot_download(repo_id=repo, local_dir=dest, allow_patterns=patterns, token=token)
print("Downloaded", repo, "->", dest)
PY
  SOURCE="$UPLOAD_DIR"
elif [[ ! -d "$SOURCE" ]]; then
  echo "error: --source is not a directory: $SOURCE" >&2
  exit 1
fi

export AWS_ACCESS_KEY_ID="$ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
export AWS_DEFAULT_REGION="$REGION"

# Create bucket (ok if it already exists).
set +e
aws --endpoint-url "$ENDPOINT" s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1
exists=$?
set -e
if [[ "$exists" -ne 0 ]]; then
  aws --endpoint-url "$ENDPOINT" s3 mb "s3://${BUCKET}"
fi

TARGET="s3://${BUCKET}/"
if [[ -n "$PREFIX" ]]; then
  # Normalize: no leading slash, trailing slash for sync destination "folder"
  PREFIX="${PREFIX#/}"
  PREFIX="${PREFIX%/}"
  TARGET="s3://${BUCKET}/${PREFIX}/"
fi

aws --endpoint-url "$ENDPOINT" s3 sync "$SOURCE" "$TARGET" --only-show-errors

echo ""
echo "Done. Objects under: ${TARGET}"
echo "Helm hint: chart/values-example-minio-s3-tinyllama.yaml (set model.connection.s3.* and protocol: s3)."
echo "Remember: from outside the cluster use oc port-forward; inside the cluster use http://minio.minio.svc.cluster.local:9000"
