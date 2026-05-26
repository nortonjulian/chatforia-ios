import Foundation

private var localizationBundles: [String: Bundle] = [:]

func appText(_ key: String, languageCode: String) -> String {

    if let cached = localizationBundles[languageCode] {
        return cached.localizedString(
            forKey: key,
            value: key,
            table: "Localizable"
        )
    }

    guard
        let path = Bundle.main.path(
            forResource: languageCode,
            ofType: "lproj"
        ),
        let bundle = Bundle(path: path)
    else {
        return Bundle.main.localizedString(
            forKey: key,
            value: key,
            table: "Localizable"
        )
    }

    localizationBundles[languageCode] = bundle

    return bundle.localizedString(
        forKey: key,
        value: key,
        table: "Localizable"
    )
}
