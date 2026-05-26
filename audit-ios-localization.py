import re
from pathlib import Path

ROOT = Path("Chatforia/Chatforia")

patterns = [
    r'Text\("([^"]*[A-Za-z][^"]*)"\)',
    r'Button\("([^"]*[A-Za-z][^"]*)"',
    r'NavigationLink\("([^"]*[A-Za-z][^"]*)"',
    r'\.navigationTitle\("([^"]*[A-Za-z][^"]*)"\)',
    r'\.alert\("([^"]*[A-Za-z][^"]*)"',
    r'ThemedGradientButton\(\s*title:\s*"([^"]*[A-Za-z][^"]*)"',
    r'ThemedOutlineButton\(\s*title:\s*"([^"]*[A-Za-z][^"]*)"',
    r'ThemedTextField\(\s*title:\s*"([^"]*[A-Za-z][^"]*)"',
    r'ThemedSecureField\(\s*title:\s*"([^"]*[A-Za-z][^"]*)"',
]

ignore_if_contains = [
    "http",
    "https",
    ".com",
    "@",
    "Chatforia",
]

def is_probably_key(value):
    return "." in value and " " not in value

results = []

for file in ROOT.rglob("*.swift"):
    text = file.read_text(encoding="utf-8", errors="ignore")
    lines = text.splitlines()

    for line_no, line in enumerate(lines, start=1):
        for pattern in patterns:
            for match in re.finditer(pattern, line):
                value = match.group(1)

                if is_probably_key(value):
                    continue

                if any(x in value for x in ignore_if_contains):
                    continue

                results.append((str(file), line_no, value.strip(), line.strip()))

print(f"\nFound {len(results)} likely hard-coded localization strings:\n")

for file, line_no, value, line in results:
    print(f"{file}:{line_no}")
    print(f"  VALUE: {value}")
    print(f"  LINE : {line}")
    print()