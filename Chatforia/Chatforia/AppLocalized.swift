import Foundation

func appText(_ key: String, languageCode: String) -> String {
    let normalized = languageCode.replacingOccurrences(of: "_", with: "-")

    let candidates = [
        normalized,
        normalized.lowercased(),
        Locale(identifier: normalized).identifier,
        "en"
    ]

    for code in candidates {
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            let value = bundle.localizedString(
                forKey: key,
                value: nil,
                table: "Localizable"
            )

            if value != key {
                return value
            }
        }
    }

    return key
}
