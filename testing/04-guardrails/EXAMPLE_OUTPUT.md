# Example Test Output

This shows the new simplified output format of `test-all-guardrails.sh`:

```

╔════════════════════════════════════════╗
║  NeMo Guardrails Test Suite            ║
╚════════════════════════════════════════╝

Model: gpt-oss-20b
Namespace: model-gpt-oss

🔗 Testing endpoint: https://gpt-oss-20b-nemo-guardrails-model-gpt-oss.apps.cluster.example.com

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1️⃣  BASELINE - Normal Request
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📨 Input: Hello, how are you? Please respond in one sentence.
💬 Output: I'm doing well, thank you for asking!
✅ PASSED (normal request allowed)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
2️⃣  DETERMINISTIC VALIDATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

─────────────────────────────────────────
🧪 Input Length Limit (2000 chars)
─────────────────────────────────────────
📨 Input: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx... [2100 chars total]
💬 Output: Your message is too long. Please keep messages under 2000 characters.
✅ BLOCKED (guardrail active)

─────────────────────────────────────────
🧪 Output Length Limit (4000 chars)
─────────────────────────────────────────
📨 Input: Write a very detailed 5000-word essay about the history of computing. M...
💬 Output: I apologize, my response was too long. Let me summarize more concisely.
✅ BLOCKED (guardrail active)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Tests completed. Review output above for pass/fail status.

✅ Active guardrails tested:
   • Input message length validation (2000 char limit)
   • Output response length validation (4000 char limit)

📋 Optional deterministic guardrails (not tested):
   • Rate limiting
   • Profanity filtering
   • JSON validation
   • PII detection (email, phone, SSN)

⚠️  LLM-based guardrails (not available):
   • Jailbreak detection
   • Topic control (politics, harmful, medical, etc.)
   Note: These require self-check rails implementation,
   not supported with current input rails configuration.

💡 To enable optional deterministic features:
   Edit chart/values-gpt-oss-20b.yaml → guardrails.nemo.config

🔍 View guardrails logs:
   oc logs -n model-gpt-oss -l app=gpt-oss-20b-nemo-guardrails --tail=50 -f

```

## Key Improvements

**Cleaner Output:**
- Each test shows: Input → Output → Status
- Long messages are truncated for readability
- JSON parsing errors are handled gracefully
- Clear visual separators between sections

**Less Verbose:**
- Removed repetitive headers and explanations
- Simplified success/failure indicators
- Compact summary section
- Each guardrail test is one clean block

**Easier to Scan:**
- Unicode borders and emojis for visual hierarchy
- Clear test categories (Baseline, Deterministic, Topic Control)
- Consistent formatting across all tests
- Status at a glance (✅/⚠️)
