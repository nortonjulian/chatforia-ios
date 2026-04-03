import Foundation
import CryptoKit

enum SHA256Helper {
    static func hexDigest(_ data: Data) -> String {
        let digest = CryptoKit.SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
