import Foundation

extension JSONDecoder {
    static func tolerantISO8601Decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        if #available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *) {
            decoder.dateDecodingStrategy = .iso8601
        } else {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
            decoder.dateDecodingStrategy = .formatted(f)
        }
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }
}
