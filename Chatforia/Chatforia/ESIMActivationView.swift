import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct ESIMActivationView: View {
    @StateObject var viewModel: ESIMActivationViewModel
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"
    @State private var showingInstallationOptions = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroSection
                statusSection

                if !viewModel.isActive {
                    installSection
                }

                detailsSection

                if !viewModel.isActive {
                    supportSection
                }
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
                    ? appText("esim.serviceActive", languageCode: appLanguage)
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

            detailRow(title: "esim.plan", value: viewModel.payload.planName)
            detailRow(title: "esim.lpaUri", value: viewModel.explicitLpaText)
            detailRow(title: "esim.activationCode", value: viewModel.installationCodeText)
            detailRow(title: "esim.confirmationCode", value: viewModel.confirmationCodeText)
            detailRow(title: "esim.smdpAddress", value: viewModel.smdpAddressText)
            detailRow(title: "esim.iccid", value: viewModel.iccidText)
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

    private var supportSection: some View {
        Text(appText("esim.installationSupportText", languageCode: appLanguage))
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
