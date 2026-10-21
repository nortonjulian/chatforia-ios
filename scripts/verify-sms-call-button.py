#!/usr/bin/env python3
from pathlib import Path
import re


SOURCE = Path("Chatforia/Chatforia/SMSThreadView.swift")
text = SOURCE.read_text(encoding="utf-8")


def require(label: str, pattern: str) -> None:
    if not re.search(pattern, text, re.S):
        raise AssertionError(f"FAIL: {label}")
    print(f"PASS: {label}")


require(
    "SMS thread receives the shared call manager",
    r"@EnvironmentObject\s+private\s+var\s+callManager:\s*CallManager",
)
require(
    "SMS toolbar exposes exactly one phone control",
    r"ToolbarItemGroup\(placement:\s*\.topBarTrailing\).*?"
    r"Button\s*\{\s*startPhoneCall\(\)\s*\}.*?"
    r"Image\(systemName:\s*\"phone\.fill\"\)",
)
require(
    "phone control has an accessible localized label",
    r"phone\.fill.*?\.accessibilityLabel\(\s*"
    r"appText\(\"common\.call\",\s*languageCode:\s*appLanguage\)\s*\)",
)
require(
    "call uses the resolved SMS number with conversation fallback",
    r"private\s+func\s+startPhoneCall\(\).*?"
    r"vm\.resolvedPhone\(\s*fallback:\s*activeConversation\.phone\s*\)",
)
require(
    "missing number is rejected visibly",
    r"startPhoneCall\(\).*?phone\.isEmpty\s+else\s*\{.*?"
    r"vm\.errorText\s*=\s*\"Could not find a phone number to call\.\"",
)
require(
    "caller name uses the same resolved SMS title shown in the header",
    r"let\s+displayName\s*=\s*vm\.resolvedTitle\(\s*"
    r"fallback:\s*activeConversation\.title,\s*"
    r"fallbackPhone:\s*activeConversation\.phone\s*\)",
)
require(
    "SMS call uses the existing phone-number destination",
    r"callManager\.startCall\(\s*to:\s*\.phoneNumber\("
    r"phone,\s*displayName:\s*displayName\),\s*auth:\s*auth\s*\)",
)

sms_view = re.search(
    r"struct\s+SMSThreadView:\s*View\s*\{(?P<body>.*?)(?=\nprivate\s+struct)",
    text,
    re.S,
)
if not sms_view:
    raise AssertionError("FAIL: could not isolate SMSThreadView")

body = sms_view.group("body")
if "startVideoCall" in body or 'systemName: "video.fill"' in body:
    raise AssertionError("FAIL: SMS thread must not expose an app-video action")
print("PASS: SMS thread does not invent a video action")

if body.count("startPhoneCall()") != 2:
    raise AssertionError("FAIL: SMS phone action must have one caller and one implementation")
print("PASS: SMS phone action is wired once")

print("9 native SMS call-button checks passed")
