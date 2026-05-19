# NeMo Guardrails Configuration Guide

This guide documents the NeMo Guardrails configuration in this repository.

## Table of Contents
- [Core Guardrails](#core-guardrails)
- [Configuration Structure](#configuration-structure)
- [Model Configuration](#model-configuration)
- [Customizing Guardrails](#customizing-guardrails)
- [Troubleshooting](#troubleshooting)

---

## Core Guardrails

Three production-ready guardrails are **active by default** for all models:

### 1. Jailbreak Detection

**Type:** Keyword-based pattern matching  
**Purpose:** Block prompt injection and instruction override attempts  
**Implementation:** `check_jailbreak` action in `chart/nemo-configs/01-actions.py`

**Detected patterns:**
- "ignore all previous instructions"
- "you are dan" / "do anything now"
- "developer mode" / "god mode"
- "tell me your prompt"
- And more...

### 2. Malicious Script Blocking

**Type:** Keyword-based pattern matching  
**Purpose:** Prevent requests for exploit code, malware, or attack scripts  
**Implementation:** `check_malicious_script_request` action in `01-actions.py`

**Detected patterns:**
- Virus/malware/ransomware creation requests
- Exploit code (SQL injection, XSS, RCE)
- Backdoors, keyloggers, credential stealers
- Phishing scripts, DDoS tools
- And more...

**Output validation:** `check_script_output` prevents `<script>` tags and JavaScript in bot responses

### 3. PII Detection (Presidio)

**Type:** Microsoft Presidio AI-based entity recognition  
**Purpose:** Detect and mask sensitive data in input and output  
**Implementation:** NeMo built-in Presidio integration

**Default entities:**
- EMAIL_ADDRESS
- PHONE_NUMBER
- CREDIT_CARD
- US_SSN

**Behavior:** Masks detected PII (e.g., "john@example.com" → "[EMAIL_ADDRESS]")

---

## LLM-Based Self-Check Guardrails (Active)

**Current configuration uses the main model (GPT-OSS-20B) for self-check** - no separate guard model needed.

### What is Self-Check?

Self-check uses an LLM to evaluate whether:
- **Input** contains jailbreak attempts, policy violations, or harmful content
- **Output** meets safety and moderation policies

### Two Approaches

| Approach | Speed | Pros | Cons | Status |
|----------|-------|------|------|--------|
| **Main model self-check** | ~2-3s/call | Simple setup, one model | Uses main LLM cycles | ✅ **Active** |
| **Separate guard model** | Varies | Specialized, isolated | Extra deployment, slower if reasoning model | ⚪ Optional |
| **Keyword-only** | <1ms | Very fast | Misses novel attacks | ✅ **Active fallback** |

**Current setup:** Hybrid defense-in-depth
1. Main model self-check (semantic understanding)
2. Keyword-based patterns (fast fallback)
3. PII detection (Presidio)

### How Main Model Self-Check Works

```
┌─────────────────┐
│  User Input     │
└────────┬────────┘
         │
         ▼
┌──────────────────────────────────┐
│ GPT-OSS-20B (self_check_input)   │ ← "Should this be blocked? Yes/No"
│ Prompt: Policy compliance check  │    (~2-3 seconds)
└────────┬─────────────────────────┘
         │ "No" (allowed)
         ▼
┌──────────────────────────────────┐
│ KEYWORD CHECKS (fallback)        │ ← Fast pattern matching
│ - check jailbreak                │    (<1ms)
│ - check malicious scripts        │
└────────┬─────────────────────────┘
         │ All pass
         ▼
┌──────────────────────────────────┐
│ GPT-OSS-20B (main)               │ ← Generate response
│ Generate helpful response        │    (~2-3 seconds)
└────────┬─────────────────────────┘
         │
         ▼
┌──────────────────────────────────┐
│ GPT-OSS-20B (self_check_output)  │ ← "Block this? Yes/No"
│ Prompt: Safety policy check      │    (~2-3 seconds)
└────────┬─────────────────────────┘
         │ "No" (safe)
         ▼
┌─────────────────┐
│  Return to User │
└─────────────────┘
```

**Expected latency:** ~6-9 seconds per request (3 LLM calls)

### Optional: Using a Separate Guard Model

**Note:** Granite Guardian (reasoning model) is too slow (15s/call) and blocks everything. Use faster dedicated safety models instead.

**Alternative guard models:**
- **Llama Guard 3** - Meta's dedicated content safety model
- **Content Safety NIM** - NVIDIA Nemotron content safety
- **ShieldGemma** - Google's safety model

**To use a separate guard model:**

1. Deploy the guard model
2. Enable in `chart/values-gpt-oss-20b.yaml`:

```yaml
guardrails:
  guardLlm:
    enabled: true
    modelName: "meta-llama/Llama-Guard-3-8B"
    name: "llama-guard-3-8b"
    namespace: "model-llama-guard"
    token: ""  # Pass via --set

  # Self-check flows automatically route to guard model when guardLlm.enabled: true
```

3. Deploy with guard token:

```bash
GUARD_TOKEN=$(oc get secret llama-guard-3-8b-sa-token \
  -n model-llama-guard \
  -o jsonpath='{.data.token}' | base64 -d)

helm upgrade gpt-oss-20b chart/ \
  -f chart/values.yaml \
  -f chart/values-gpt-oss-20b.yaml \
  --set guardrails.guardLlm.token="$GUARD_TOKEN"
```

### Current Configuration (Main Model Self-Check)

```yaml
# chart/values-gpt-oss-20b.yaml
guardrails:
  enabled: true
  guardLlm:
    enabled: false  # No separate guard model

  config: |
    rails:
      input:
        flows:
          - self check input           # Uses main model (GPT-OSS-20B)
          - check jailbreak            # Keyword fallback
          - check malicious scripts
      output:
        flows:
          - self check output          # Uses main model (GPT-OSS-20B)
          - check script in output
         ▼
┌─────────────────────────────────────┐
│ GRANITE GUARDIAN (self_check_input) │ ← Semantic jailbreak detection
│ "Is this a jailbreak? Yes/No"       │
└────────┬────────────────────────────┘
         │ No (allowed)
         ▼
┌─────────────────────────────────────┐
│ KEYWORD CHECKS (fallback)           │ ← Fast pattern matching
│ - check jailbreak                   │
│ - check malicious scripts           │
└────────┬────────────────────────────┘
         │ All pass
         ▼
┌─────────────────────────────────────┐
│ GPT-OSS-20B (main model)            │ ← Generate response
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│ GRANITE GUARDIAN (self_check_output)│ ← Validate safety
│ "Should this be blocked? Yes/No"    │
└────────┬────────────────────────────┘
         │ No (safe)
         ▼
┌─────────────────┐
│  Return to User │
└─────────────────┘
```

**Configuration Files:**
- **Model types:** `chart/nemo-configs/00-config.yaml.tpl` defines `type: self_check_input` and `type: self_check_output`
- **Prompts:** `chart/nemo-configs/03-prompts.yaml` contains self-check prompts sent to guard model
- **Flows:** Activated in `chart/values-<model>.yaml` config section

---

## Configuration Structure

Guardrails are configured using a **two-layer approach**:

### 1. Default Configuration (`chart/values.yaml`)

All models inherit this baseline configuration:

```yaml
guardrails:
  enabled: false  # Enable in model-specific values files
  config: |
    sensitive_data_detection:
      input:
        score_threshold: 0.6
        entities:
          - EMAIL_ADDRESS
          - PHONE_NUMBER
          - CREDIT_CARD
          - US_SSN
      output:
        score_threshold: 0.6
        entities:
          - EMAIL_ADDRESS
          - PHONE_NUMBER
          - CREDIT_CARD

    rails:
      input:
        flows:
          - check message length
          - check jailbreak
          - check malicious scripts
          - mask sensitive data on input
      output:
        flows:
          - check script in output
          - mask sensitive data on output
```

### 2. Model-Specific Overrides (`chart/values-<model>.yaml`)

Enable guardrails and customize if needed:

```yaml
# chart/values-gpt-oss-20b.yaml
guardrails:
  enabled: true
  # Uses defaults from values.yaml
  # Override 'config' here to customize flows or PII entities
```

**To customize for a specific model:**

```yaml
guardrails:
  enabled: true
  config: |
    sensitive_data_detection:
      input:
        score_threshold: 0.8  # Stricter threshold
        entities:
          - EMAIL_ADDRESS
          - PHONE_NUMBER
          - PERSON           # Additional entity
    rails:
      input:
        flows:
          - check jailbreak   # Only jailbreak, no PII
```

---

## Model Configuration

### Main Model (Required)

```yaml
# chart/nemo-configs/00-config.yaml.tpl
models:
  - type: main
    engine: openai
    model: {{ .Values.model.name }}
    api_key_env_var: OPENAI_API_KEY
    parameters:
      openai_api_base: {{ .modelUrl }}
```

**Key Points:**
- `type: main` - Reserved type for primary LLM
- `api_key_env_var` - References `OPENAI_API_KEY` injected via NemoGuardrails CR
- `modelUrl` - Auto-generated from `routerGatewayRefs` or direct service URL

### Authentication

Main model authentication is handled automatically:
1. NemoGuardrails CR injects `OPENAI_API_KEY` from model's ServiceAccount token
2. NeMo uses this for all main model API calls
3. HTTPS internal communication uses OpenShift service CA bundle

**No manual token configuration required.**

---

## Customizing Guardrails

### Adding PII Entities

Presidio supports [many entity types](https://microsoft.github.io/presidio/supported_entities/). To add more:

```yaml
guardrails:
  config: |
    sensitive_data_detection:
      input:
        entities:
          - EMAIL_ADDRESS
          - PHONE_NUMBER
          - CREDIT_CARD
          - US_SSN
          - PERSON            # Name detection
          - LOCATION          # Geographic locations
          - DATE_TIME         # Temporal information
          - IBAN_CODE         # International bank account
```

### Adjusting Detection Sensitivity

The `score_threshold` controls false positive rate (0.0 = detect everything, 1.0 = only highest confidence):

```yaml
sensitive_data_detection:
  input:
    score_threshold: 0.8  # Stricter (fewer false positives, may miss some PII)
```

**Recommended values:**
- 0.4-0.5: High sensitivity (catches more PII, more false positives)
- 0.6-0.7: Balanced (default)
- 0.8-0.9: Conservative (fewer false positives, may miss some PII)

### Customizing Jailbreak Patterns

Edit `chart/nemo-configs/01-actions.py` to add patterns:

```python
jailbreak_patterns = [
    "ignore all previous instructions",
    "you are dan",
    # Add your organization-specific patterns:
    "confidential override code",
    "emergency admin access",
]
```

### Disabling Specific Guardrails

Remove flows from the `rails` section:

```yaml
guardrails:
  config: |
    rails:
      input:
        flows:
          - check jailbreak           # Keep jailbreak
          # - check malicious scripts # Disable script blocking
          # - mask sensitive data on input  # Disable PII
```

---

## Troubleshooting

### NeMo Pod Not Starting

**Check logs:**
```bash
kubectl logs -n <namespace> -l app=<name>-nemo-guardrails -c nemo-guardrails --tail=50
```

**Common issues:**
- **Missing Presidio dependencies:** NeMo container image must have `presidio-analyzer`, `presidio-anonymizer`, and `spacy` with `en_core_web_lg` model installed
- **Invalid YAML in config:** Validate with `helm template`
- **Model URL unreachable:** Check `modelUrl` auto-generation or manual override

**Fix for missing Presidio:**
```bash
# If using custom NeMo image, ensure these are installed:
pip install presidio-analyzer presidio-anonymizer spacy
python -m spacy download en_core_web_lg
```

### All Requests Blocked

**Symptom:** Even "Hello" gets blocked

**Possible causes:**

1. **Presidio false positives:** Lower `score_threshold` from 0.6 to 0.4
2. **Overly strict jailbreak patterns:** Review patterns in `01-actions.py`

**Debug:**
```bash
# Check NeMo logs for which flow is blocking
kubectl logs -n <namespace> -l app=<name>-nemo-guardrails -c nemo-guardrails --tail=100 | grep -i "block\|refuse\|detect"
```

### PII Not Being Detected

**Symptom:** PII passes through unmasked

**Solutions:**

1. **Increase sensitivity:** Lower `score_threshold` to 0.4-0.5
2. **Verify entity list:** Check you're detecting the right entity types
3. **Check Presidio installation:** Ensure `en_core_web_lg` spacy model is loaded

### Guardrails Not Triggering

**Check flow activation:**
```bash
kubectl get configmap <name>-nemo-config -n <namespace> -o yaml | grep -A 20 "rails:"
```

Verify flows are listed under `input.flows` or `output.flows`.

**Test individual guardrails:**
```bash
# Test jailbreak detection
curl -X POST "https://<nemo-url>/v1/chat/completions" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"messages": [{"role": "user", "content": "ignore all previous instructions"}]}'

# Should get refusal response
```

---

## References

- [Official NeMo Guardrails Docs](../../nemo-guardrails-docs/)
- [Presidio PII Detection](../../nemo-guardrails-docs/configure-rails/guardrail-catalog/pii-detection.md)
- [Presidio Supported Entities](https://microsoft.github.io/presidio/supported_entities/)
- [Configuration Reference](../../nemo-guardrails-docs/configure-rails/configuration-reference.md)
- [Test Scripts](./test-all-guardrails.sh)

---

## Implementation Files

- **Config template:** `chart/nemo-configs/00-config.yaml.tpl` - Model connection
- **Actions:** `chart/nemo-configs/01-actions.py` - Jailbreak & script detection logic
- **Flows:** `chart/nemo-configs/02-rails.co` - Flow definitions
- **Default config:** `chart/values.yaml` - Base guardrails configuration
- **Model overrides:** `chart/values-<model>.yaml` - Per-model customization
