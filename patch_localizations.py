import json
from pathlib import Path

path = Path("Chatforia/Chatforia/Localizable.xcstrings")

with path.open("r", encoding="utf-8") as f:
    catalog = json.load(f)

strings = catalog.setdefault("strings", {})

# Find every language already used in your string catalog
languages = set()
for item in strings.values():
    for lang in item.get("localizations", {}).keys():
        languages.add(lang)

print("Found languages:", ", ".join(sorted(languages)))

updates = {
    "messages.sendTextToStartConversation": {
        "en": "Send a text to start the conversation",
        "cs": "Pošlete SMS a začněte konverzaci",
        "fa": "برای شروع گفتگو یک پیامک بفرستید",
    },
    "sms.refreshFailed": {
        "en": "Couldn’t refresh messages. Please try again.",
        "cs": "Zprávy se nepodařilo obnovit. Zkuste to prosím znovu.",
        "fa": "پیام‌ها به‌روزرسانی نشدند. لطفاً دوباره تلاش کنید.",
    },
    "tap_to_view_contact": {
        "en": "Tap to view contact",
        "cs": "Klepnutím zobrazíte kontakt",
        "fa": "برای مشاهده مخاطب ضربه بزنید",
    },
}

for key, translations in updates.items():
    entry = strings.setdefault(key, {})
    localizations = entry.setdefault("localizations", {})

    for lang in languages:
        # Use real translation when we have it, otherwise fall back to English
        value = translations.get(lang) or translations["en"]

        localizations[lang] = {
            "stringUnit": {
                "state": "translated",
                "value": value
            }
        }

with path.open("w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2)

print("Done. Updated keys:")
for key in updates:
    print("-", key)
