# NeMo Guardrails Testing

Test scripts for validating NeMo Guardrails integration with model deployments.

## Prerequisites

- Model deployed with `guardrails.enabled: true` and `guardrails.type: nemo`
- NeMo Guardrails pod running in the model namespace
- Route exposed for external access

## Quick Start

### Test GPT-OSS 20B with Guardrails

```bash
./testing/04-guardrails/test-nemo-guardrails.sh
```

### Test a Different Model

```bash
./testing/04-guardrails/test-nemo-guardrails.sh <model-name> <namespace>

# Examples:
./testing/04-guardrails/test-nemo-guardrails.sh gemma-4-31b-it-fp8-dynamic model-gemma4-fp8
./testing/04-guardrails/test-nemo-guardrails.sh gpt-oss-20b model-gpt-oss
```

## What the Test Does

The script performs two tests:

### Test 1: Normal Request ✅
- Sends a short message (under 2000 characters)
- **Expected**: Model responds normally
- **Purpose**: Verify guardrails allow valid requests

### Test 2: Long Message ⛔
- Sends a message with 2001 characters (exceeds limit)
- **Expected**: Guardrail blocks request with message:
  ```
  "Your message is too long. Please keep messages under 2000 characters."
  ```
- **Purpose**: Verify guardrails enforce the rails.co rules

## Guardrail Configuration

The NeMo Guardrails configuration is organized into multiple files in the ConfigMap (`chart/templates/nemo/configmap.yaml`):

### **config.yaml**
- Model configuration and connection settings
- PII detection settings (optional, commented out)
- Rails activation (which input/output flows to run)

### **rails.co** - Main Guardrails
Active guardrails:
- ✅ **Message length validation** (2000 chars input, 4000 chars output)
- ✅ **Topic control** (uses LLM for semantic matching):
  - Political discussions
  - Personal information requests
  - Harmful/dangerous content
  - Financial advice
  - Medical advice

### **actions.py** - Custom Python Actions
Advanced features (commented out by default):
- Rate limiting (10 requests/minute per user)
- Profanity filtering with word lists
- Email/URL pattern detection
- JSON output validation

### **flows_advanced.co** - Optional Advanced Flows
Examples of complex guardrails (commented out):
- Multi-turn validation
- Context-aware restrictions
- Time-based controls

## How Topic Control Works

NeMo uses the **main LLM for intent recognition** (no separate guard model needed):

**Example:** User asks "wht's ur opnion on da election?"

1. NeMo prompts the LLM with canonical examples:
   ```
   Does "wht's ur opnion on da election?" match:
   - ask about politics: "What do you think about elections?", "Tell me your political views"
   ```
2. LLM recognizes it matches "user ask about politics"
3. Guardrail triggers → Bot responds: "I'm not able to discuss political topics..."

**This handles:**
- ✅ Misspellings ("wht's ur opnion")
- ✅ Paraphrasing ("give me your political views")
- ✅ Different languages ("¿qué piensas de las elecciones?")
- ✅ Context variations ("I want to know your stance on voting")

**No pattern matching limitations!**

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
