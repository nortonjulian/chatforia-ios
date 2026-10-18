#!/usr/bin/env python3
"""Compile the production receipt formatter against this checkout's catalog."""
from pathlib import Path
import json
import shutil
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'Chatforia' / 'Chatforia'
sheet = (SRC / 'MessageReceiptSheet.swift').read_text()
row = (SRC / 'ChatMessageRowView.swift').read_text()
formatter = sheet[sheet.index('enum GroupReceiptLabel {'):]
assert 'GroupReceiptLabel.readByUser(raw, languageCode: appLanguage)' in row
assert 'GroupReceiptLabel.readByCount(readers.count, languageCode: appLanguage)' in row
assert 'GroupReceiptLabel.seenByPeopleCount(readers.count, languageCode: appLanguage)' in sheet
assert 'GroupReceiptLabel.userWithId(user.id, languageCode: appLanguage)' in sheet
catalog = json.loads((SRC / 'Localizable.xcstrings').read_text())['strings']
keys = ['messages.readByUser', 'messages.readByCount', 'messages.seenByPeopleCount', 'common.userWithId']
fixtures = {key: {lang: value['stringUnit']['value'] for lang, value in catalog[key]['localizations'].items()
                  if 'stringUnit' in value} for key in keys}
print('PASS: both receipt views use the scoped formatter; catalog read successfully')
if not shutil.which('xcrun'):
    raise SystemExit('Run on macOS with Xcode for native formatter checks.')
harness = r'''
import Foundation
let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fixtures = try! JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: fixtureURL))
func appText(_ key: String, languageCode: String) -> String { fixtures[key]?[languageCode] ?? key }
@main struct GroupLabelQA {
    static func main() {
        var checks = 0
        func check(_ value: Bool, _ label: String) {
            precondition(value, label)
            checks += 1
            print("PASS: \(label)")
        }
        check(GroupReceiptLabel.readByUser("papi", languageCode: "en") == "Read by papi", "English identifies reader")
        check(GroupReceiptLabel.readByCount(2, languageCode: "en") == "Read by 2", "English identifies count")
        check(GroupReceiptLabel.seenByPeopleCount(2, languageCode: "en") == "Seen by 2 people", "receipt sheet count")
        check(GroupReceiptLabel.userWithId(68, languageCode: "en") == "User 68", "missing username identifies user ID")
        check(GroupReceiptLabel.readByUser("papi", languageCode: "es") == "Leído por papi", "Spanish named token")
        check(GroupReceiptLabel.readByCount(2, languageCode: "zh-CN").contains("2"), "legacy numeric printf token")
        check(GroupReceiptLabel.readByUser("papi", languageCode: "zh-CN").contains("papi"), "legacy object printf token")
        let unusual = "name %@ %d {count} $1 \\ café"
        check(GroupReceiptLabel.readByUser(unusual, languageCode: "en") == "Read by \(unusual)", "participant name stays literal")
        check(GroupReceiptLabel.readByUser("papi", languageCode: "missing") == "Read by papi", "missing translation has identifying fallback")
        check(GroupReceiptLabel.readByCount(2, languageCode: "ar") == "Read by 2", "malformed translated format has safe fallback")
        for (key, languages) in fixtures {
            for language in languages.keys.sorted() {
                let text: String
                let expected: String
                switch key {
                case "messages.readByUser":
                    expected = "qa_reader_68"
                    text = GroupReceiptLabel.readByUser(expected, languageCode: language)
                case "messages.readByCount":
                    expected = "123"
                    text = GroupReceiptLabel.readByCount(123, languageCode: language)
                case "messages.seenByPeopleCount":
                    expected = "123"
                    text = GroupReceiptLabel.seenByPeopleCount(123, languageCode: language)
                default:
                    expected = "68"
                    text = GroupReceiptLabel.userWithId(68, languageCode: language)
                }
                precondition(text.contains(expected) && !text.contains("{name}") && !text.contains("{count}") && !text.contains("{id}"),
                             "\(language): \(key) failed")
                checks += 1
            }
            print("PASS: \(key) across \(languages.count) catalog languages")
        }
        print("\(checks) native receipt-label checks passed")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='chatforia-group-labels-') as temp:
    temp = Path(temp)
    (temp / 'Formatter.swift').write_text('import Foundation\n' + formatter)
    (temp / 'Harness.swift').write_text(harness)
    (temp / 'fixtures.json').write_text(json.dumps(fixtures))
    executable = temp / 'verify'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                    str(temp / 'Formatter.swift'), str(temp / 'Harness.swift'), '-o', str(executable)], check=True)
    subprocess.run([str(executable), str(temp / 'fixtures.json')], check=True)
