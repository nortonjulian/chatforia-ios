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
        .navigationTitle("Activate eSIM")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Unable to install eSIM", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Please try again.")
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
            Text("Status")
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            HStack(spacing: 10) {
                Image(systemName: viewModel.isActive ? "checkmark.circle.fill" : "clock.badge.checkmark.fill")
                    .foregroundStyle(viewModel.isActive ? themeManager.palette.accent : themeManager.palette.buttonEnd)

                Text(viewModel.isActive ? "Service active" : "Ready to install")
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
            Text("Install")
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            Text("Install directly on this iPhone, or use the activation details below on another supported device.")
                .font(.footnote)
                .foregroundStyle(themeManager.palette.secondaryText)

            Button {
                Task {
                    guard let url = await viewModel.beginInstall() else { return }
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
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canInstall || viewModel.isActive || viewModel.isInstalling)
            .opacity((!viewModel.canInstall || viewModel.isActive) ? 0.55 : 1)

            if !viewModel.canInstall {
                Text("Your carrier hasn’t provided a valid install link yet. You can still use the manual activation details below when available.")
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
            Text("Activation details")
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            detailRow(title: "Plan", value: viewModel.payload.planName)
            detailRow(title: "LPA URI", value: viewModel.explicitLpaText)
            detailRow(title: "Activation code", value: viewModel.installationCodeText)
            detailRow(title: "Confirmation code", value: viewModel.confirmationCodeText)
            detailRow(title: "SM-DP+ address", value: viewModel.smdpAddressText)
            detailRow(title: "ICCID", value: viewModel.iccidText)
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
        Text("eSIM installation steps can vary by device. Make sure your iPhone is unlocked and eSIM-compatible before installing. If direct install is unavailable, use the activation details above in Settings > Cellular > Add eSIM.")
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
