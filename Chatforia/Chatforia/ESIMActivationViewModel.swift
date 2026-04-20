import Foundation
import Combine

@MainActor
final class ESIMActivationViewModel: ObservableObject {
    @Published var payload: ESIMActivationDTO
    @Published var isInstalling: Bool = false
    @Published var errorMessage: String?

    init(payload: ESIMActivationDTO) {
        self.payload = payload
    }

    var titleText: String {
        isActive ? "Your eSIM is active" : "Your eSIM is ready"
    }

    var subtitleText: String {
        if let planName = nonEmpty(payload.planName) {
            return planName
        }
        return "Install your eSIM to start using your data pack."
    }

    var installationCodeText: String? {
        nonEmpty(payload.activationCode)
    }

    var confirmationCodeText: String? {
        nonEmpty(payload.confirmationCode)
    }

    var iccidText: String? {
        nonEmpty(payload.iccid)
    }

    var smdpAddressText: String? {
        nonEmpty(payload.smdpAddress)
    }

    var isActive: Bool {
        let status = payload.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return status == "active"
    }

    var installButtonTitle: String {
        isActive ? "Installed" : "Install eSIM"
    }

    var qrCodeURLText: String? {
        nonEmpty(payload.qrCodeURL)
    }

    var canInstall: Bool {
        !isActive && (installationCodeText != nil || qrCodeURLText != nil)
    }

    func markInstalled() {
        payload = ESIMActivationDTO(
            smdpAddress: payload.smdpAddress,
            activationCode: payload.activationCode,
            iccid: payload.iccid,
            confirmationCode: payload.confirmationCode,
            planName: payload.planName,
            status: "active",
            qrCodeURL: payload.qrCodeURL
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
