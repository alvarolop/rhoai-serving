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

Current guardrails (defined in `chart/templates/nemo/configmap.yaml`):

```colang
define flow check message length
  if $user_message.length > 2000
    bot inform message too long
    stop

define bot inform message too long
  "Your message is too long. Please keep messages under 2000 characters."
```

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
