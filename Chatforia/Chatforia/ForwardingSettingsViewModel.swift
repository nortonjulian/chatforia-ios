import Foundation
import Combine

@MainActor
final class ForwardingSettingsViewModel: ObservableObject {
    @Published var forwardingEnabledSms = false
    @Published var forwardSmsToPhone = false
    @Published var forwardPhoneNumber = ""
    @Published var forwardSmsToEmail = false
    @Published var forwardEmail = ""

    @Published var forwardingEnabledCalls = false
    @Published var forwardToPhoneE164 = ""

    @Published var forwardQuietHoursStart: Int? = nil
    @Published var forwardQuietHoursEnd: Int? = nil

    @Published var isLoading = false
    @Published var isSaving = false
    @Published var banner: String?
    @Published var errorMessage: String?

    private(set) var initialState: ForwardingSettingsDTO?

    func load(from dto: ForwardingSettingsDTO) {
        forwardingEnabledSms = dto.forwardingEnabledSms
        forwardSmsToPhone = dto.forwardSmsToPhone
        forwardPhoneNumber = dto.forwardPhoneNumber
        forwardSmsToEmail = dto.forwardSmsToEmail
        forwardEmail = dto.forwardEmail
        forwardingEnabledCalls = dto.forwardingEnabledCalls
        forwardToPhoneE164 = dto.forwardToPhoneE164
        forwardQuietHoursStart = dto.forwardQuietHoursStart
        forwardQuietHoursEnd = dto.forwardQuietHoursEnd
        initialState = dto
    }

    func makeRequest() -> ForwardingSettingsDTO {
        ForwardingSettingsDTO(
            forwardingEnabledSms: forwardingEnabledSms,
            forwardSmsToPhone: forwardSmsToPhone,
            forwardPhoneNumber: normalizePhone(forwardPhoneNumber),
            forwardSmsToEmail: forwardSmsToEmail,
            forwardEmail: forwardEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            forwardingEnabledCalls: forwardingEnabledCalls,
            forwardToPhoneE164: normalizePhone(forwardToPhoneE164),
            forwardQuietHoursStart: forwardQuietHoursStart,
            forwardQuietHoursEnd: forwardQuietHoursEnd
        )
    }

    var hasChanges: Bool {
        guard let initialState else { return false }
        let current = makeRequest()

        return initialState.forwardingEnabledSms != current.forwardingEnabledSms ||
            initialState.forwardSmsToPhone != current.forwardSmsToPhone ||
            initialState.forwardPhoneNumber != current.forwardPhoneNumber ||
            initialState.forwardSmsToEmail != current.forwardSmsToEmail ||
            initialState.forwardEmail != current.forwardEmail ||
            initialState.forwardingEnabledCalls != current.forwardingEnabledCalls ||
            initialState.forwardToPhoneE164 != current.forwardToPhoneE164 ||
            initialState.forwardQuietHoursStart != current.forwardQuietHoursStart ||
            initialState.forwardQuietHoursEnd != current.forwardQuietHoursEnd
    }

    func reset() {
        guard let initialState else { return }
        load(from: initialState)
        banner = nil
        errorMessage = nil
    }

    var validationErrors: [String: String] {
        var out: [String: String] = [:]

        if forwardingEnabledSms {
            if forwardSmsToPhone && !isValidE164(forwardPhoneNumber) {
                out["forwardPhoneNumber"] = "Enter a valid E.164 phone (e.g. +15551234567)."
            }
            if forwardSmsToEmail && !isValidEmail(forwardEmail) {
                out["forwardEmail"] = "Enter a valid email."
            }
            if !forwardSmsToPhone && !forwardSmsToEmail {
                out["smsToggle"] = "Choose at least one destination (phone or email)."
            }
        }

        if forwardingEnabledCalls && !isValidE164(forwardToPhoneE164) {
            out["forwardToPhoneE164"] = "Enter a valid E.164 phone."
        }

        let values = [forwardQuietHoursStart, forwardQuietHoursEnd]
        for value in values {
            if let value, value < 0 || value > 23 {
                out["quiet"] = "Quiet hours must be between 0 and 23."
                break
            }
        }

        return out
    }

    private func normalizePhone(_ value: String) -> String {
        value.replacingOccurrences(of: #"[^0-9+]"#, with: "", options: .regularExpression)
    }

    private func isValidE164(_ value: String) -> Bool {
        let normalized = normalizePhone(value)
        let pattern = #"^\+?[1-9]\d{7,14}$"#
        return normalized.range(of: pattern, options: .regularExpression) != nil
    }

    private func isValidEmail(_ value: String) -> Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}
