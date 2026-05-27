import Foundation
import Combine
import SwiftUI

@MainActor
final class ESIMActivationViewModel: ObservableObject {
    @AppStorage("chatforia_language") private var appLanguage = "en"

    @Published var payload: ESIMActivationDTO
    @Published var isInstalling: Bool = false
    @Published var errorMessage: String?

    init(payload: ESIMActivationDTO) {
        self.payload = payload
    }

    var titleText: String {
        isActive
            ? appText("esim.activeTitle", languageCode: appLanguage)
            : appText("esim.readyTitle", languageCode: appLanguage)
    }

    var subtitleText: String {
        if let planName = nonEmpty(payload.planName) {
            return planName
        }

        return appText("esim.installSubtitle", languageCode: appLanguage)
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

    var qrCodeURLText: String? {
        nonEmpty(payload.qrCodeURL)
    }

    var explicitLpaText: String? {
        nonEmpty(payload.lpaUri)
    }

    var isActive: Bool {
        let status = payload.status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return status == "active"
    }

    var installButtonTitle: String {
        if isInstalling {
            return appText("common.opening", languageCode: appLanguage)
        }

        return isActive
            ? appText("esim.installed", languageCode: appLanguage)
            : appText("esim.install", languageCode: appLanguage)
    }

    var canInstall: Bool {
        !isActive && installURL != nil
    }

    var installURL: URL? {
        if let explicit = explicitLpaText,
           let url = normalizedInstallURL(from: explicit) {
            return url
        }

        if let activation = installationCodeText,
           let url = normalizedInstallURL(from: activation) {
            return url
        }

        if let smdp = smdpAddressText,
           let activation = installationCodeText {
            let raw = "LPA:1$\(smdp)$\(activation)"
            return normalizedInstallURL(from: raw)
        }

        return nil
    }

    var manualSetupAvailable: Bool {
        installationCodeText != nil || smdpAddressText != nil || iccidText != nil
    }

    func beginInstall() async -> URL? {
        errorMessage = nil

        guard let url = installURL else {
            errorMessage = appText("esim.invalidInstallLink", languageCode: appLanguage)
            return nil
        }

        isInstalling = true
        defer { isInstalling = false }

        return url
    }

    func markInstalled() {
        payload = ESIMActivationDTO(
            smdpAddress: payload.smdpAddress,
            activationCode: payload.activationCode,
            iccid: payload.iccid,
            confirmationCode: payload.confirmationCode,
            planName: payload.planName,
            status: "active",
            qrCodeURL: payload.qrCodeURL,
            lpaUri: payload.lpaUri
        )
    }

    private func normalizedInstallURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.lowercased().hasPrefix("lpa:") {
            return URL(string: trimmed)
        }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        return nil
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmed.isEmpty ? nil : trimmed
    }
}
