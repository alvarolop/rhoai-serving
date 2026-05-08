# helm-docs Setup

This chart uses [helm-docs](https://github.com/norwoodj/helm-docs) to automatically generate documentation from `values.yaml` comments.

## Installation

### Linux (amd64)

```bash
wget https://github.com/norwoodj/helm-docs/releases/download/v1.14.2/helm-docs_1.14.2_Linux_x86_64.tar.gz
tar -xzf helm-docs_1.14.2_Linux_x86_64.tar.gz
sudo mv helm-docs /usr/local/bin/
rm helm-docs_1.14.2_Linux_x86_64.tar.gz
```

### macOS (Homebrew)

```bash
brew install norwoodj/tap/helm-docs
```

### Using Go

```bash
go install github.com/norwoodj/helm-docs/cmd/helm-docs@latest
```

## Usage

Generate `README.md` from `values.yaml` comments:

```bash
cd chart/
make docs
```

Or run helm-docs directly:

```bash
cd chart/
helm-docs
```

This will:
1. Parse special comment syntax in `values.yaml` (`# --` for descriptions)
2. Use `README.md.gotmpl` as the template
3. Generate `README.md` with auto-generated values table

## Comment Syntax

In `values.yaml`, use these special comments:

```yaml
# @section -- Section Name

# -- Field description here
fieldName: value

# -- Another field with complex default
# @default -- calculated at runtime
complexField: {}

# -- Ignored field (won't appear in docs)
# @ignored
secretField: ""
```

## Template Customization

Edit `README.md.gotmpl` to customize the generated README structure. The template uses Go templating with helm-docs functions:

- `{{ template "chart.header" . }}` - Chart name header
- `{{ template "chart.description" . }}` - From Chart.yaml
- `{{ template "chart.valuesSection" . }}` - Auto-generated values table
- `{{ template "chart.maintainersSection" . }}` - Maintainers from Chart.yaml

## CI/CD Integration

To verify README.md is up-to-date in CI:

```bash
helm-docs --dry-run
git diff --exit-code README.md
```
