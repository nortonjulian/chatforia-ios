import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct ESIMActivationView: View {
    @StateObject var viewModel: ESIMActivationViewModel
    let purchasedPackages: WirelessPurchasesResponseDTO?
    let purchasesErrorMessage: String?
    let onRequestReplacement: (() -> Void)?
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("chatforia_language") private var appLanguage = "en"
    @State private var showingInstallationOptions = false
    @State private var showingReplacementConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroSection
                statusSection

                if !viewModel.isActive {
                    installSection
                }

                detailsSection

                purchasedPackagesSection
                replacementSection

                supportSection
            }
            .padding()
        }
        .background(themeManager.palette.screenBackground.ignoresSafeArea())
        .navigationTitle(appText("esim.title", languageCode: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingInstallationOptions) {
            installationOptionsSheet
        }
        .alert(
            appText("esim.unableToInstall", languageCode: appLanguage),
            isPresented: errorBinding
        ) {
            Button(appText("common.ok", languageCode: appLanguage), role: .cancel) {}
        } message: {
            Text(
                viewModel.errorMessage
                ?? appText("common.tryAgain", languageCode: appLanguage)
            )
        }
    }

    private var heroSection: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(themeManager.palette.accent.opacity(0.14))
                .frame(width: 84, height: 84)
                .overlay(
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(themeManager.palette.accent)
                )

            Text(viewModel.titleText)
                .font(.title2.weight(.bold))
                .foregroundStyle(themeManager.palette.primaryText)
                .multilineTextAlignment(.center)

            Text(viewModel.subtitleText)
                .font(.body)
                .foregroundStyle(themeManager.palette.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appText("common.status", languageCode: appLanguage))
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            HStack(spacing: 10) {
                Image(
                    systemName:
                        viewModel.isActive
                        ? "checkmark.circle.fill"
                        : "clock.badge.checkmark.fill"
                )
                .foregroundStyle(
                    viewModel.isActive
                    ? themeManager.palette.accent
                    : themeManager.palette.buttonEnd
                )

                Text(
                    viewModel.isActive
                    ? appText("ios.your_esim_is_active", languageCode: appLanguage)
                    : appText("esim.readyToInstall", languageCode: appLanguage)
                )
                .font(.body.weight(.semibold))
                .foregroundStyle(themeManager.palette.primaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(themeManager.palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(themeManager.palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var installSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appText("common.install", languageCode: appLanguage))
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            Text(appText("esim.installDirectlyOrUseDetails", languageCode: appLanguage))
                .font(.footnote)
                .foregroundStyle(themeManager.palette.secondaryText)

            Button {
                showingInstallationOptions = true
            } label: {
                Text(viewModel.installButtonTitle)
                    .font(.headline)
                    .foregroundStyle(themeManager.palette.buttonForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [
                                themeManager.palette.buttonStart,
                                themeManager.palette.buttonEnd
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(
                !viewModel.canInstall
                || viewModel.isActive
                || viewModel.isInstalling
            )
            .opacity(
                (!viewModel.canInstall || viewModel.isActive)
                ? 0.55
                : 1
            )

            if !viewModel.canInstall {
                Text(appText("esim.noValidInstallLink", languageCode: appLanguage))
                    .font(.caption)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(themeManager.palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(themeManager.palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var installationOptionsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if viewModel.showsProvisioningDetails {
                        Text("Install your Chatforia eSIM")
                            .font(.title2.weight(.bold))

                        Text(
                            "Use the QR code to install this eSIM on another supported device, "
                            + "or use the manual activation details below."
                        )
                        .font(.body)
                        .foregroundStyle(.secondary)

                        if let payload = qrPayload,
                           let image = makeQRCode(from: payload) {
                            VStack(spacing: 12) {
                                Image(uiImage: image)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 260)
                                    .padding()
                                    .background(Color.white)
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: 16,
                                            style: .continuous
                                        )
                                    )

                                Text(
                                    "To install on another device, scan this QR code "
                                    + "from that device's eSIM setup screen."
                                )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 14) {
                            Text("Manual setup")
                                .font(.headline)

                            Text(
                                "On this iPhone, open Settings → Cellular → Add eSIM "
                                + "and choose the option to enter the details manually."
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                            activationDetail(
                                title: "SM-DP+ Address",
                                value: manualSMDPAddress
                            )

                            activationDetail(
                                title: "Activation Code",
                                value: manualActivationCode
                            )

                            activationDetail(
                                title: "Confirmation Code",
                                value: viewModel.confirmationCodeText
                            )
                        }
                    } else {
                        Text("This eSIM is already active.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("eSIM Installation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingInstallationOptions = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var qrPayload: String? {
        guard viewModel.showsProvisioningDetails else {
            return nil
        }

        let candidates = [
            viewModel.explicitLpaText,
            viewModel.qrCodeURLText
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
            let smdp = viewModel.smdpAddressText,
            let activationCode = viewModel.installationCodeText
        else {
            return nil
        }

        return "LPA:1$\(smdp)$\(activationCode)"
    }

    private var manualLPAComponents: (smdp: String, activationCode: String)? {
        let candidates = [
            viewModel.explicitLpaText,
            viewModel.installationCodeText
        ]

        for candidate in candidates {
            guard let candidate else {
                continue
            }

            let trimmed = candidate.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard trimmed.lowercased().hasPrefix("lpa:1$") else {
                continue
            }

            let components = trimmed.split(
                separator: "$",
                omittingEmptySubsequences: false
            )

            guard components.count >= 3 else {
                continue
            }

            let smdp = String(components[1])
            let activationCode = String(components[2])

            guard !smdp.isEmpty, !activationCode.isEmpty else {
                continue
            }

            return (smdp, activationCode)
        }

        return nil
    }

    private var manualSMDPAddress: String? {
        if let parsed = manualLPAComponents {
            return parsed.smdp
        }

        return viewModel.smdpAddressText
    }

    private var manualActivationCode: String? {
        if let parsed = manualLPAComponents {
            return parsed.activationCode
        }

        guard
            let value = viewModel.installationCodeText,
            !value.lowercased().hasPrefix("lpa:")
        else {
            return nil
        }

        return value
    }

    private func makeQRCode(from value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let transformed = outputImage.transformed(
            by: CGAffineTransform(scaleX: 10, y: 10)
        )

        let context = CIContext()

        guard let cgImage = context.createCGImage(
            transformed,
            from: transformed.extent
        ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    @ViewBuilder
    private func activationDetail(
        title: String,
        value: String?
    ) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(appText("esim.activationDetails", languageCode: appLanguage))
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            if viewModel.showsProvisioningDetails {
                detailRow(title: "esim.lpaUri", value: viewModel.explicitLpaText)
                detailRow(title: "esim.activationCode", value: viewModel.installationCodeText)
                detailRow(title: "esim.confirmationCode", value: viewModel.confirmationCodeText)
                detailRow(title: "esim.smdpAddress", value: viewModel.smdpAddressText)
            }

            detailRow(title: "esim.iccid", value: viewModel.displayIccidText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(themeManager.palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(themeManager.palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var purchasedPackagesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(appText("esim.purchase.historyTitle", languageCode: appLanguage))
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            PurchasedDataPackagesList(
                packages: purchasedPackages?.packages,
                errorMessage: purchasesErrorMessage
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(themeManager.palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var replacementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appText("esim.transfer.title", languageCode: appLanguage))
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            Button(appText("esim.transfer.request", languageCode: appLanguage)) {
                showingReplacementConfirmation = true
            }
            .disabled(
                purchasedPackages?.replacementEligibility.eligible != true ||
                onRequestReplacement == nil
            )
            .alert("Replace eSIM?", isPresented: $showingReplacementConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Replace eSIM", role: .destructive) {
                    // Return to Wireless before starting the existing workflow.
                    // Its completion opens the new installation details.
                    dismiss()
                    onRequestReplacement?()
                }
            } message: {
                Text(appText("esim.transfer.confirmation", languageCode: appLanguage))
            }

            if let reason = purchasedPackages?.replacementEligibility.reason {
                Text(localizedEsimReplacementReason(reason, languageCode: appLanguage))
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)
            } else if purchasedPackages == nil {
                Text(appText("esim.transfer.packagesUnavailable", languageCode: appLanguage))
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(themeManager.palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appText("esim.installationSupportText", languageCode: appLanguage))
            Text(appText("esim.install.dataSettingsIos", languageCode: appLanguage))
            Text(appText("esim.install.troubleshootingIos", languageCode: appLanguage))
        }
        .font(.caption)
        .foregroundStyle(themeManager.palette.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func detailRow(title: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(appText(title, languageCode: appLanguage))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themeManager.palette.secondaryText)

                Text(value)
                    .font(.body)
                    .foregroundStyle(themeManager.palette.primaryText)
                    .textSelection(.enabled)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.errorMessage = nil
                }
            }
        )
    }
}

struct PurchasedDataPackagesList: View {
    let packages: [WirelessPurchasedPackageDTO]?
    let errorMessage: String?
    @AppStorage("chatforia_language") private var appLanguage = "en"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let packages {
                if packages.isEmpty {
                    Text(appText("esim.purchase.none", languageCode: appLanguage))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(packages) { package in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(name(for: package))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(label(for: package.state))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(package.state == "ACTIVE" ? .green : .orange)
                            }

                            Text(package.unlimited
                                 ? appText("esim.purchase.unlimited", languageCode: appLanguage)
                                 : formattedText(
                                    "esim.purchase.remainingOf",
                                    formatGB(package.remainingDataMb),
                                    formatGB(package.totalDataMb)
                                 ))

                            if package.state == "BALANCE_NEEDS_REVIEW",
                               let recorded = package.recordedRemainingDataMb,
                               let provider = package.providerRemainingDataMb {
                                Text(formattedText(
                                    "esim.purchase.balanceConflict",
                                    formatGB(recorded),
                                    formatGB(provider)
                                ))
                                    .foregroundStyle(.orange)
                            }

                            if let purchasedAt = package.purchasedAt {
                                Text(formattedText("esim.purchase.recordedAt", formatDate(purchasedAt)))
                            }

                            Text(package.activatedAt.map {
                                formattedText("esim.purchase.activatedAt", formatDate($0))
                            } ?? appText("esim.purchase.activationUnknown", languageCode: appLanguage))

                            Text(package.expiresAt.map {
                                formattedText("esim.purchase.expiresAt", formatDate($0))
                            } ?? appText("esim.purchase.expiryUnknown", languageCode: appLanguage))

                            if package.state == "EXPIRY_NEEDS_REVIEW" {
                                Text(appText("esim.purchase.expiryConflict", languageCode: appLanguage))
                                    .foregroundStyle(.orange)
                            } else if package.state == "EXPIRED" {
                                Text(appText("esim.purchase.expiredExplanation", languageCode: appLanguage))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                        if package.id != packages.last?.id {
                            Divider()
                        }
                    }
                }
            } else {
                Text(errorMessage ?? appText("esim.purchase.loading", languageCode: appLanguage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatGB(_ megabytes: Int) -> String {
        String(
            format: "%.1f GB",
            locale: Locale(identifier: appLanguage),
            Double(megabytes) / 1024.0
        )
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(
            .dateTime.year().month(.abbreviated).day()
                .locale(Locale(identifier: appLanguage))
        )
    }

    private func formattedText(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: appText(key, languageCode: appLanguage),
            locale: Locale(identifier: appLanguage),
            arguments: arguments
        )
    }

    private func name(for package: WirelessPurchasedPackageDTO) -> String {
        let parts = (package.addonKind ?? "").lowercased().split(separator: "_")
        guard let index = parts.firstIndex(where: { ["local", "europe", "global"].contains(String($0)) }),
              parts.indices.contains(index + 1) else {
            return formattedText("esim.purchase.fallbackName", package.id)
        }
        let region = appText("esim.\(parts[index])", languageCode: appLanguage)
        let size = package.unlimited
            ? appText("esim.unlimited", languageCode: appLanguage)
            : formattedText("esim.purchase.sizeGb", String(parts[index + 1]))
        return formattedText("esim.purchase.name", region, size)
    }

    private func label(for state: String) -> String {
        switch state {
        case "ACTIVE": return appText("ios.active", languageCode: appLanguage)
        case "AWAITING_ACTIVATION": return appText("esim.purchase.stateAwaitingActivation", languageCode: appLanguage)
        case "AWAITING_PROVISIONING": return appText("esim.purchase.stateAwaitingProvisioning", languageCode: appLanguage)
        case "PROVISIONING_NEEDS_REVIEW": return appText("esim.purchase.stateProvisioningReview", languageCode: appLanguage)
        case "PAYMENT_UNVERIFIED": return appText("esim.purchase.statePaymentUnverified", languageCode: appLanguage)
        case "EXPIRED": return appText("ios.expired", languageCode: appLanguage)
        case "EXPIRY_NEEDS_REVIEW": return appText("esim.purchase.stateExpiryReview", languageCode: appLanguage)
        case "BALANCE_NEEDS_REVIEW": return appText("esim.purchase.stateBalanceReview", languageCode: appLanguage)
        case "EXHAUSTED": return appText("esim.purchase.stateExhausted", languageCode: appLanguage)
        case "TERMINATED": return appText("esim.purchase.stateTerminated", languageCode: appLanguage)
        default: return appText("esim.purchase.stateProviderUnverified", languageCode: appLanguage)
        }
    }
}

func localizedEsimReplacementReason(_ reason: String?, languageCode: String) -> String {
    let key: String
    switch reason {
    case "No eligible active data package is available for transfer.":
        key = "esim.transfer.noEligiblePack"
    case "Multiple or pending data packages may share this eSIM. Transfer is unavailable until every remaining entitlement can be preserved.":
        key = "esim.transfer.multipleOrPending"
    case "Unlimited data package transfer requires Telna confirmation.":
        key = "esim.transfer.unlimitedUnconfirmed"
    case "This data package cannot be safely transferred with the current provider workflow.":
        key = "esim.transfer.unsupportedPack"
    case "Transfer requires one active, unexpired data package with a confirmed balance.":
        key = "esim.transfer.activePackRequired"
    default:
        key = "esim.transfer.unavailable"
    }
    return appText(key, languageCode: languageCode)
}
