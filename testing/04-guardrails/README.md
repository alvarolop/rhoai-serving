# NeMo Guardrails Testing

Test scripts for validating NeMo Guardrails integration with model deployments.

## Prerequisites

- Model deployed with `guardrails.enabled: true` and `guardrails.type: nemo`
- NeMo Guardrails pod running in the model namespace
- Route exposed for external access

## Quick Start

### Comprehensive Test Suite (Recommended)

Tests all active guardrails with multiple variations:

```bash
./testing/04-guardrails/test-all-guardrails.sh
# Defaults to gpt-oss-20b in model-gpt-oss namespace

# Or specify model:
./testing/04-guardrails/test-all-guardrails.sh gemma-4-31b-it-fp8-dynamic model-gemma4-fp8
```

### Simple Test (Basic Validation)

Quick test of message length validation:

```bash
./testing/04-guardrails/test-nemo-guardrails.sh
# Or: ./testing/04-guardrails/test-nemo-guardrails.sh <model-name> <namespace>
```

## What the Comprehensive Test Suite Does

The `test-all-guardrails.sh` script validates all active guardrails with multiple test scenarios:

### 1. Baseline Validation ✅
- **Normal Request**: Sends valid message (under limits, appropriate topic)
- **Expected**: Model responds normally
- **Purpose**: Verify guardrails allow legitimate requests

### 2. Deterministic Validation ⛔
- **Input Length Limit**: Sends 2100 characters (exceeds 2000 limit)
  - Expected: "Your message is too long. Please keep messages under 2000 characters."
- **Output Length Limit**: Requests very long response (triggers 4000 char limit)
  - Expected: "I apologize, my response was too long. Let me summarize more concisely."

**Total:** 3 test cases (baseline + 2 deterministic validations)

## LLM-Based Guardrails (Not Available)

The following guardrails require LLM semantic matching and are **not currently working** in input rails context:

### ⚠️ Jailbreak Detection (Disabled)
- Requires LLM to match adversarial patterns
- Not supported with current input rails implementation

### ⚠️ Topic Control (Disabled)
- Politics, personal info, harmful content, financial advice, medical advice
- Requires LLM semantic matching to detect intent
- Not supported with current input rails implementation

**Why removed:** NeMo Guardrails input rails with `when user <intent>` syntax doesn't trigger LLM calls for semantic matching. These guardrails would require implementing self-check rails or moving to dialog rails context, which is beyond the scope of this basic demonstration.

## Guardrail Configuration

NeMo Guardrails uses a **two-layer configuration** approach:

### 🎛️ **Per-Model Control Panel** (Customizable)
**Location:** `chart/values-<model>.yaml` → `guardrails.nemo.config`

This YAML field controls **which guardrails are active** for each model deployment:
- Rails activation (which input/output flows to run)
- PII detection settings (optional, commented out by default)
- Sensitive data entities (EMAIL_ADDRESS, PHONE_NUMBER, etc.)

**Example:**
```yaml
guardrails:
  nemo:
    config: |
      rails:
        input:
          flows:
            - check message length
            - check forbidden topics
        output:
          flows:
            - check output length
```

To enable optional features like profanity filtering, rate limiting, or PII detection:
1. Edit your model's values file (e.g., `values-gpt-oss-20b.yaml`)
2. Uncomment the desired flows in `guardrails.nemo.config`
3. Redeploy via Helm or ArgoCD

### 📚 **Guardrails Library** (Hardcoded)
**Location:** `chart/templates/nemo/configmap.yaml`

The comprehensive library of **available guardrails** (same for all models):

**rails.co** - Flow Definitions:
- ✅ **Message length validation** (2000 chars input, 4000 chars output) - ACTIVE
- ❌ **Jailbreak detection** - DISABLED (requires LLM semantic matching)
- ❌ **Topic control** - DISABLED (requires LLM semantic matching):
  - Political discussions
  - Personal information requests
  - Harmful/dangerous content
  - Financial advice
  - Medical advice

**actions.py** - Custom Python Actions:
- Rate limiting (10 requests/minute per user)
- Profanity filtering with word lists
- Email/URL pattern detection
- JSON output validation

**flows_advanced.co** - Advanced Flow Examples:
- Multi-turn validation
- Context-aware restrictions
- Time-based controls

**This separation allows:**
- ✅ Consistent guardrails library across all models
- ✅ Per-model customization of which guardrails to activate
- ✅ Easy updates to the library without touching values files

## Optional Guardrails (Available but Not Active by Default)

The guardrails library includes additional features that can be enabled per model:

### Input Rails
- **Rate Limiting**: Prevent abuse with request throttling (10 req/min default)
  ```yaml
  - check rate limit  # Uncomment in config
  ```
- **Profanity Filtering**: Block offensive language
  ```yaml
  - check profanity  # Uncomment in config
  ```

### Output Rails
- **JSON Validation**: Ensure structured output format
  ```yaml
  - validate json output  # Uncomment in config
  ```

### Sensitive Data Detection
- **PII Detection**: Regex-based detection for emails, phone numbers, credit cards, SSN
  ```yaml
  sensitive_data_detection:
    input:
      entities:
        - EMAIL_ADDRESS
        - PHONE_NUMBER
        - CREDIT_CARD
  ```

### Custom Actions
The `actions.py` file includes reusable validation functions:
- `check_email_pattern()` - Detect email addresses in messages
- `check_url_pattern()` - Detect URLs in messages
- Custom validation logic extensible in Python

## Limitations

**LLM-Based Guardrails Not Supported:**

NeMo Guardrails supports LLM-based semantic matching for intents (jailbreak detection, topic control), but this requires proper implementation using:
- **Self-check rails** - Explicit LLM prompting for validation
- **Dialog rails** - Multi-turn conversation context (not input rails)

The simple `when user <intent>` syntax in input rails **does not trigger LLM calls** for semantic matching, as evidenced by logs showing "0 total calls, 0 total tokens" when these flows execute.

For production deployments requiring semantic content filtering, consider:
1. Using dedicated guard models (NemoGuard, LlamaGuard)
2. Implementing self-check rails with explicit LLM prompts
3. Moving validation to dialog rails context
4. Using regex patterns for deterministic matching

## Troubleshooting

### Route Not Found
```bash
oc get route -n <namespace> | grep nemo
```

### Token Not Found
```bash
oc get secret <model-name>-sa-token -n <namespace>
```

### Check Guardrails Logs
```bash
oc logs -n <namespace> -l app=<model-name>-nemo-guardrails -c nemo-guardrails --tail=50 -f
```

### Check Pod Status
```bash
oc get pods -n <namespace> | grep nemo
```

## Direct Model Access vs Guardrails

**Through Guardrails (Protected):**
```bash
https://<model-name>-nemo-guardrails-<namespace>.apps.<cluster>/v1/chat/completions
```

**Direct to Model (Unprotected):**
```bash
https://<model-name>-<namespace>.apps.<cluster>/v1/chat/completions
```

Only requests through the guardrails endpoint are protected by rails.co rules.
