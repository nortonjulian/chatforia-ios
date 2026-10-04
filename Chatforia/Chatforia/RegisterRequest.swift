import Foundation

struct RegistrationRequestDTO: Encodable {
    let username: String
    let email: String
    let password: String
}
