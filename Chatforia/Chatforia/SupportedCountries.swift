import Foundation

enum SupportedCountries {
    static let codes: [String] = [
        "US", "CA", "GB", "IE", "FR", "DE", "ES", "IT", "NL", "BE",
        "CH", "AT", "SE", "NO", "DK", "FI", "AU", "NZ", "JP", "KR",
        "SG", "HK", "IN", "PK", "BD", "ID", "PH", "TH", "VN", "MY",
        "BR", "MX", "AR", "CL", "CO", "PE", "ZA", "NG", "KE", "EG",
        "MA", "AE", "SA", "IL", "TR"
    ]

    static var options: [CountryOption] {
        let locale = Locale.current

        return codes.map { code in
            CountryOption(
                id: code,
                code: code,
                name: locale.localizedString(forRegionCode: code) ?? code,
                flag: flagEmoji(for: code)
            )
        }
    }

    private static func flagEmoji(for iso2: String) -> String {
        let base: UInt32 = 127397
        return iso2.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(base + $0.value)
        }
        .map(String.init)
        .joined()
    }
}
