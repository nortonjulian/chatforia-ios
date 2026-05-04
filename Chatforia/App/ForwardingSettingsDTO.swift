import Foundation

struct ForwardingSettingsDTO: Codable, Equatable {
    let forwardingEnabledSms: Bool
    let forwardSmsToPhone: Bool
    let forwardPhoneNumber: String
    let forwardSmsToEmail: Bool
    let forwardEmail: String
    let forwardingEnabledCalls: Bool
    let forwardToPhoneE164: String
    let forwardQuietHoursStart: Int?
    let forwardQuietHoursEnd: Int?

    static let empty = ForwardingSettingsDTO(
        forwardingEnabledSms: false,
        forwardSmsToPhone: false,
        forwardPhoneNumber: "",
        forwardSmsToEmail: false,
        forwardEmail: "",
        forwardingEnabledCalls: false,
        forwardToPhoneE164: "",
        forwardQuietHoursStart: nil,
        forwardQuietHoursEnd: nil
    )

    enum CodingKeys: String, CodingKey {
        case forwardingEnabledSms
        case forwardSmsToPhone
        case forwardPhoneNumber
        case forwardSmsToEmail
        case forwardEmail
        case forwardingEnabledCalls
        case forwardToPhoneE164
        case forwardQuietHoursStart
        case forwardQuietHoursEnd
    }

    init(
        forwardingEnabledSms: Bool,
        forwardSmsToPhone: Bool,
        forwardPhoneNumber: String,
        forwardSmsToEmail: Bool,
        forwardEmail: String,
        forwardingEnabledCalls: Bool,
        forwardToPhoneE164: String,
        forwardQuietHoursStart: Int?,
        forwardQuietHoursEnd: Int?
    ) {
        self.forwardingEnabledSms = forwardingEnabledSms
        self.forwardSmsToPhone = forwardSmsToPhone
        self.forwardPhoneNumber = forwardPhoneNumber
        self.forwardSmsToEmail = forwardSmsToEmail
        self.forwardEmail = forwardEmail
        self.forwardingEnabledCalls = forwardingEnabledCalls
        self.forwardToPhoneE164 = forwardToPhoneE164
        self.forwardQuietHoursStart = forwardQuietHoursStart
        self.forwardQuietHoursEnd = forwardQuietHoursEnd
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        forwardingEnabledSms = try c.decodeIfPresent(Bool.self, forKey: .forwardingEnabledSms) ?? false
        forwardSmsToPhone = try c.decodeIfPresent(Bool.self, forKey: .forwardSmsToPhone) ?? false
        forwardPhoneNumber = try c.decodeIfPresent(String.self, forKey: .forwardPhoneNumber) ?? ""
        forwardSmsToEmail = try c.decodeIfPresent(Bool.self, forKey: .forwardSmsToEmail) ?? false
        forwardEmail = try c.decodeIfPresent(String.self, forKey: .forwardEmail) ?? ""
        forwardingEnabledCalls = try c.decodeIfPresent(Bool.self, forKey: .forwardingEnabledCalls) ?? false
        forwardToPhoneE164 = try c.decodeIfPresent(String.self, forKey: .forwardToPhoneE164) ?? ""
        forwardQuietHoursStart = try c.decodeIfPresent(Int.self, forKey: .forwardQuietHoursStart)
        forwardQuietHoursEnd = try c.decodeIfPresent(Int.self, forKey: .forwardQuietHoursEnd)
    }
}
