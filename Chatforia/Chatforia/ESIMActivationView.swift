import SwiftUI

struct ESIMActivationView: View {
    @StateObject var viewModel: ESIMActivationViewModel
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"
    @Environment(\.openURL) private var openURL

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
                Task {
                    guard let url = await viewModel.beginInstall() else {
                        return
                    }

                    openURL(url)
                }
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
