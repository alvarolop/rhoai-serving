#!/usr/bin/env bash
# Verify that chart/README.md is up-to-date with values.yaml
# Usage: ./verify-docs.sh
# Exit code 0 if README is current, 1 if it needs regeneration

set -euo pipefail

cd "$(dirname "$0")"

# Check if helm-docs is installed
if ! command -v helm-docs &> /dev/null; then
    echo "❌ helm-docs not found. Install from https://github.com/norwoodj/helm-docs"
    echo "   Linux: wget https://github.com/norwoodj/helm-docs/releases/download/v1.14.2/helm-docs_1.14.2_Linux_x86_64.tar.gz"
    echo "   macOS: brew install norwoodj/tap/helm-docs"
    exit 1
fi

echo "📝 Running helm-docs in dry-run mode..."
if helm-docs --dry-run 2>&1 | grep -q "WARN"; then
    echo ""
    echo "⚠️  README.md is out of date!"
    echo ""
    echo "The values.yaml comments have changed. Regenerate README.md by running:"
    echo "  cd chart/ && make docs"
    echo ""
    echo "Or commit the changes with:"
    echo "  helm-docs"
    echo "  git add README.md"
    echo "  git commit -m 'docs: regenerate chart README'"
    exit 1
else
    echo "✅ README.md is up-to-date with values.yaml"
    exit 0
fi
