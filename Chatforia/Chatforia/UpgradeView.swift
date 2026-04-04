import SwiftUI

struct UpgradeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    Circle()
                        .fill(themeManager.palette.accent.opacity(0.14))
                        .frame(width: 84, height: 84)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(themeManager.palette.accent)
                        )

                    Text("Go Premium")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(themeManager.palette.primaryText)
                        .multilineTextAlignment(.center)

                    Text("Upgrade your Chatforia experience with a cleaner app and more customization.")
                        .font(.body)
                        .foregroundStyle(themeManager.palette.secondaryText)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    benefitRow(
                        icon: "nosign",
                        title: "Remove ads",
                        subtitle: "Enjoy a cleaner, distraction-free experience."
                    )

                    benefitRow(
                        icon: "paintpalette",
                        title: "Premium themes",
                        subtitle: "Unlock additional looks and visual styles."
                    )

                    benefitRow(
                        icon: "music.note",
                        title: "Premium sounds",
                        subtitle: "Get access to more tones and ringtones."
                    )

                    benefitRow(
                        icon: "sparkles.rectangle.stack",
                        title: "More premium features",
                        subtitle: "Get future premium upgrades as Chatforia grows."
                    )
                }

                VStack(spacing: 12) {
                    ThemedGradientButton(
                        title: "Upgrade to Premium",
                        action: {
                            // Wire real purchase flow later
                        },
                        horizontalPadding: 20,
                        verticalPadding: 14,
                        font: .headline.weight(.semibold)
                    )
                    .frame(maxWidth: .infinity)

                    ThemedOutlineButton(
                        title: "Maybe later",
                        action: {
                            dismiss()
                        }
                    )
                }
            }
            .padding()
        }
        .background(themeManager.palette.screenBackground.ignoresSafeArea())
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func benefitRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(themeManager.palette.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }

            Spacer()
        }
        .padding()
        .background(themeManager.palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(themeManager.palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
