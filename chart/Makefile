.PHONY: docs
docs: ## Generate README.md from values.yaml comments using helm-docs
	@command -v helm-docs >/dev/null 2>&1 || { echo >&2 "helm-docs not found. Install: https://github.com/norwoodj/helm-docs"; exit 1; }
	helm-docs --chart-search-root=.

.PHONY: verify-docs
verify-docs: ## Verify README.md is up-to-date with values.yaml
	@./verify-docs.sh

.PHONY: help
help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
