import Foundation

struct VoiceTokenResponseDTO: Decodable {
    let token: String
    let identity: String?
}
