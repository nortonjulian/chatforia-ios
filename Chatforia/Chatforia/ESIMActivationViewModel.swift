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
        if isActive {
            return appText(
                "esim.activeSubtitle",
                languageCode: appLanguage
            )
        }

        if let planName = nonEmpty(payload.planName) {
            return planName
        }

        return appText(
            "esim.installSubtitle",
            languageCode: appLanguage
        )
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

    var showsProvisioningDetails: Bool {
        !isActive
    }

    var displayIccidText: String? {
        guard let iccid = iccidText else {
            return nil
        }

        let suffix = String(iccid.suffix(4))
        return "•••• •••• •••• \(suffix)"
    }

    var isMockProfile: Bool {
        let values = [
            payload.smdpAddress,
            payload.lpaUri,
            payload.qrCodeURL
        ]

        return values
            .compactMap { $0?.lowercased() }
            .contains {
                $0.contains(
                    "mock.smdp.chatforia.com"
                )
            }
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
        guard !isActive,
              let lpaCode = installLPACode else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "esimsetup.apple.com"
        components.path = "/esim_qrcode_provisioning"
        components.queryItems = [
            URLQueryItem(
                name: "carddata",
                value: lpaCode
            )
        ]

        return components.url
    }

    private var installLPACode: String? {
        let candidates = [
            explicitLpaText,
            qrCodeURLText,
            installationCodeText
        ]

        for candidate in candidates {
            guard let candidate else {
                continue
            }

            let trimmed = candidate.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            if trimmed.lowercased().hasPrefix("lpa:") {
                return trimmed
            }
        }

        guard
            let smdp = smdpAddressText,
            let activation = installationCodeText
        else {
            return nil
        }

        return "LPA:1$\(smdp)$\(activation)"
    }

    var manualSetupAvailable: Bool {
        installationCodeText != nil || smdpAddressText != nil || iccidText != nil
    }

    func beginInstall() async -> URL? {
        errorMessage = nil
        isInstalling = true

        defer {
            isInstalling = false
        }

        AnalyticsManager.shared.capture(
            "esim_install_started",
            properties: [
                "status": payload.status,
                "hasQRCode": payload.qrCodeURL != nil,
                "hasICCID": payload.iccid != nil,
                "isMock": isMockProfile
            ]
        )

        if isMockProfile {
            do {
                try await ESIMService.shared
                    .activateCurrentProfile(
                        iccid: payload.iccid,
                        activationCode:
                            payload.activationCode
                    )

                markInstalled()
                return nil
            } catch {
                errorMessage =
                    error.localizedDescription

                return nil
            }
        }

        guard let url = installURL else {
            errorMessage = appText(
                "esim.invalidInstallLink",
                languageCode: appLanguage
            )

            return nil
        }

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

        AnalyticsManager.shared.capture("esim_activated", properties: [
            "planName": payload.planName ?? "unknown",
            "iccidPresent": payload.iccid != nil
        ])
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmed.isEmpty ? nil : trimmed
    }
}
