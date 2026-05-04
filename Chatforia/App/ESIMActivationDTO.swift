import Foundation

struct ESIMActivationDTO: Codable {
    let smdpAddress: String?
    let activationCode: String?
    let iccid: String?
    let confirmationCode: String?
    let planName: String?
    let status: String
    let qrCodeURL: String?
    let lpaUri: String?

    enum CodingKeys: String, CodingKey {
        case smdpAddress
        case activationCode
        case iccid
        case confirmationCode
        case planName
        case status
        case qrCodeURL
        case lpaUri
    }
}
