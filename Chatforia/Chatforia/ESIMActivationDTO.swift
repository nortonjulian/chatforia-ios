import Foundation

struct ESIMActivationDTO: Codable {
    let smdpAddress: String
    let activationCode: String
    let iccid: String?
    let confirmationCode: String?
    let planName: String?
    let status: String
    let qrCodeURL: String?
}
