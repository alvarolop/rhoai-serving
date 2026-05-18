"""
Custom NeMo Guardrails Actions

These actions provide additional validation logic beyond what Colang flows can do.
"""
from typing import Optional
from nemoguardrails.actions import action
import re

# ============================================================
# JAILBREAK DETECTION (via Guard LLM)
# ============================================================

@action(is_system_action=True)
async def check_jailbreak(context: Optional[dict] = None) -> bool:
    """
    Check if user message is a jailbreak attempt.
    Returns: True if allowed, False if jailbreak detected

    NOTE: This is a simple keyword-based detector for demonstration.
    For production, integrate with Granite Guardian guard LLM via
    NeMo's built-in self-check mechanism or custom LLM API calls.
    """
    user_message = context.get("user_message", "").lower()

    # Simple jailbreak detection keywords
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

    # Check if message contains jailbreak patterns
    for pattern in jailbreak_patterns:
        if pattern in user_message:
            return False  # Block - jailbreak detected

    return True  # Allow - no jailbreak detected

# ============================================================
# MALICIOUS SCRIPT DETECTION
# ============================================================

@action(is_system_action=True)
async def check_malicious_script_request(context: Optional[dict] = None) -> bool:
    """
    Check if user is asking for malicious scripts or code.
    Returns: True if allowed, False if malicious script request detected
    """
    user_message = context.get("user_message", "").lower()

    # Malicious script request patterns
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

    # Check if message contains malicious script patterns
    for pattern in malicious_patterns:
        if pattern in user_message:
            return False  # Block - malicious script request detected

    return True  # Allow - no malicious script request detected

@action(is_system_action=True)
async def check_script_output(context: Optional[dict] = None) -> bool:
    """
    Check if bot response contains script tags or potentially executable code.
    Returns: True if allowed, False if script content detected
    """
    bot_message = context.get("bot_message", "")
    if not bot_message:
        return True  # Allow if no message yet

    bot_message_lower = bot_message.lower()

    # Script tag patterns (HTML/JavaScript)
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

    # Check if message contains script indicators
    for indicator in script_indicators:
        if indicator in bot_message_lower:
            return False  # Block - script content detected

    return True  # Allow - no script content detected

# ============================================================
# RATE LIMITING
# ============================================================

# Simple in-memory rate limiter (use Redis for production)
_request_counts = {}

@action(is_system_action=True)
async def check_rate_limit(context: Optional[dict] = None) -> str:
    """
    Check if user has exceeded rate limit.
    Returns: "blocked" if rate limit exceeded, "allowed" otherwise
    """
    user_id = context.get("user_id", "anonymous")
    current_time = context.get("current_time", 0)

    # Simple sliding window: max 10 requests per minute
    if user_id not in _request_counts:
        _request_counts[user_id] = []

    # Clean old requests (older than 1 minute)
    _request_counts[user_id] = [
        t for t in _request_counts[user_id]
        if current_time - t < 60
    ]

    if len(_request_counts[user_id]) >= 10:
        return "blocked"

    _request_counts[user_id].append(current_time)
    return "allowed"

# ============================================================
# PROFANITY FILTERING
# ============================================================

# Basic profanity list (extend as needed)
PROFANITY_LIST = [
    "badword1", "badword2", "offensive",
    # Add more as needed
]

@action(is_system_action=True)
async def check_profanity(context: Optional[dict] = None) -> str:
    """
    Check for profanity in user message.
    Returns: "blocked" if profanity found, "allowed" otherwise
    """
    user_message = context.get("user_message", "").lower()

    for word in PROFANITY_LIST:
        if word in user_message:
            return "blocked"

    return "allowed"

# ============================================================
# STRUCTURED OUTPUT VALIDATION
# ============================================================

@action(is_system_action=True)
async def validate_json_output(context: Optional[dict] = None) -> str:
    """
    Validate that bot output is valid JSON.
    Returns: "valid" or "invalid"
    """
    import json
    bot_message = context.get("bot_message", "")

    try:
        json.loads(bot_message)
        return "valid"
    except json.JSONDecodeError:
        return "invalid"

# ============================================================
# CUSTOM VALIDATION EXAMPLES
# ============================================================

@action(is_system_action=True)
async def check_email_pattern(context: Optional[dict] = None) -> str:
    """
    Check if message contains email addresses.
    Returns: "found" or "not_found"
    """
    user_message = context.get("user_message", "")
    email_pattern = r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'

    if re.search(email_pattern, user_message):
        return "found"
    return "not_found"

@action(is_system_action=True)
async def check_url_pattern(context: Optional[dict] = None) -> str:
    """
    Check if message contains URLs.
    Returns: "found" or "not_found"
    """
    user_message = context.get("user_message", "")
    url_pattern = r'https?://[^\s]+'

    if re.search(url_pattern, user_message):
        return "found"
    return "not_found"
