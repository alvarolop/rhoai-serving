"""
Custom NeMo Guardrails Actions

Three core guardrails actions:
1. Jailbreak detection - Block prompt injection attempts
2. Malicious script blocking - Prevent exploit code generation
3. Script output filtering - Remove dangerous JavaScript/HTML from responses
"""
from typing import Optional
from nemoguardrails.actions import action

# ============================================================
# 1. JAILBREAK DETECTION
# ============================================================

@action(is_system_action=True)
async def check_jailbreak(context: Optional[dict] = None) -> bool:
    """
    Check if user message is a jailbreak attempt.
    Returns: True if allowed, False if jailbreak detected

    Keyword-based pattern matching for common prompt injection techniques.
    """
    user_message = context.get("user_message", "").lower()

    jailbreak_patterns = [
        "ignore all previous instructions",
        "ignore previous instructions",
        "forget your instructions",
        "you are dan",
        "do anything now",
        "developer mode",
        "admin mode",
        "god mode",
        "jailbreak",
        "bypass",
        "override",
        "disregard",
        "repeat the text above",
        "tell me your prompt",
        "what are your instructions",
        "system prompt"
    ]

    for pattern in jailbreak_patterns:
        if pattern in user_message:
            return False  # Block - jailbreak detected

    return True  # Allow - no jailbreak detected

# ============================================================
# 2. MALICIOUS SCRIPT BLOCKING
# ============================================================

@action(is_system_action=True)
async def check_malicious_script_request(context: Optional[dict] = None) -> bool:
    """
    Check if user is asking for malicious scripts or exploit code.
    Returns: True if allowed, False if malicious script request detected

    Prevents generation of viruses, malware, exploits, and attack tools.
    """
    user_message = context.get("user_message", "").lower()

    malicious_patterns = [
        "write a virus",
        "create a virus",
        "make a virus",
        "write malware",
        "create malware",
        "ransomware",
        "keylogger",
        "backdoor",
        "trojan",
        "exploit code",
        "reverse shell",
        "sql injection",
        "xss script",
        "cross-site scripting",
        "remote code execution",
        "privilege escalation",
        "bypass antivirus",
        "evade detection",
        "cryptominer",
        "botnet",
        "ddos script",
        "phishing script",
        "credential stealer",
        "password cracker"
    ]

    for pattern in malicious_patterns:
        if pattern in user_message:
            return False  # Block - malicious script request detected

    return True  # Allow - no malicious script request detected

# ============================================================
# 3. SCRIPT OUTPUT FILTERING
# ============================================================

@action(is_system_action=True)
async def check_script_output(context: Optional[dict] = None) -> bool:
    """
    Check if bot response contains script tags or executable JavaScript.
    Returns: True if allowed, False if script content detected

    Prevents XSS attacks and dangerous HTML/JavaScript in bot responses.
    """
    bot_message = context.get("bot_message", "")
    if not bot_message:
        return True  # Allow if no message yet

    bot_message_lower = bot_message.lower()

    script_indicators = [
        "<script",
        "</script>",
        "javascript:",
        "onerror=",
        "onload=",
        "onclick=",
        "<iframe",
        "eval(",
        "document.cookie",
        "document.write",
        "window.location"
    ]

    for indicator in script_indicators:
        if indicator in bot_message_lower:
            return False  # Block - script content detected

    return True  # Allow - no script content detected
