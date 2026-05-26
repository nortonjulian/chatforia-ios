import SwiftUI

struct ESIMActivationView: View {
    @StateObject var viewModel: ESIMActivationViewModel
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroSection
                statusSection
                installSection
                detailsSection
                supportSection
            }
            .padding()
        }
        .background(themeManager.palette.screenBackground.ignoresSafeArea())
        .navigationTitle(String(localized: "esim.activate"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            String(localized: "esim.unableToInstall"),
            isPresented: errorBinding
        ) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(
                viewModel.errorMessage
                ?? String(localized: "common.tryAgain")
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

            Text(String(localized: "common.status"))
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
                    ? String(localized: "esim.serviceActive")
                    : String(localized: "esim.readyToInstall")
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

            Text(String(localized: "common.install"))
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            Text(
                String(
                    localized:
                    "esim.installDirectlyOrUseDetails"
                )
            )
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
                Text(
                    String(
                        localized:
                        "esim.noValidInstallLink"
                    )
                )
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

            Text(String(localized: "esim.activationDetails"))
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
        Text(
            String(
                localized:
                "esim.installationSupportText"
            )
        )
        .font(.caption)
        .foregroundStyle(themeManager.palette.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func detailRow(title: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
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