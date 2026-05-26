import SwiftUI

struct UpgradePromptSheet: View {
    let title: String
    let message: String
    let requiredPlan: AppPlan
    let onUpgradeTapped: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("chatforia_language") private var appLanguage = "en"

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.screenBackground
                    .ignoresSafeArea()

                VStack(spacing: 22) {
                    VStack(spacing: 14) {
                        Circle()
                            .fill(themeManager.palette.accent.opacity(0.14))
                            .frame(width: 72, height: 72)
                            .overlay(
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(themeManager.palette.accent)
                            )

                        VStack(spacing: 8) {
                            Text(title)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(themeManager.palette.primaryText)
                                .multilineTextAlignment(.center)

                            Text(message)
                                .font(.body)
                                .foregroundStyle(themeManager.palette.secondaryText)
                                .multilineTextAlignment(.center)

                            Text(
                                String(
                                    format: appText(
                                        "upgrade.requires_plan_format",
                                        languageCode: appLanguage
                                    ),
                                    planDisplayName(requiredPlan)
                                )
                            )
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(themeManager.palette.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(themeManager.palette.accent.opacity(0.12))
                            .clipShape(Capsule())
                            .padding(.top, 4)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(themeManager.palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(themeManager.palette.border, lineWidth: 1)
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )

                    VStack(spacing: 12) {
                        ThemedGradientButton(
                            title: requiredPlan == .plus
                                ? appText(
                                    "upgrade.to_plus",
                                    languageCode: appLanguage
                                )
                                : appText(
                                    "upgrade.to_premium",
                                    languageCode: appLanguage
                                ),
                            action: {
                                onUpgradeTapped()
                            },
                            horizontalPadding: 20,
                            verticalPadding: 14,
                            font: .headline.weight(.semibold)
                        )
                        .frame(maxWidth: .infinity)

                        ThemedOutlineButton(
                            title: appText(
                                "common.notNow",
                                languageCode: appLanguage
                            ),
                            action: {
                                dismiss()
                            }
                        )
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle(
                appText(
                    "common.upgradeRequired",
                    languageCode: appLanguage
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                AnalyticsManager.shared.capture(
                    "upgrade_viewed",
                    properties: [
                        "source": "upgrade_prompt",
                        "required_plan": planDisplayName(requiredPlan)
                    ]
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        appText(
                            "common.close",
                            languageCode: appLanguage
                        )
                    ) {
                        dismiss()
                    }
                    .foregroundStyle(themeManager.palette.accent)
                }
            }
        }
    }

    private func planDisplayName(_ plan: AppPlan) -> String {
        switch plan {
        case .free:
            return appText("billing.free", languageCode: appLanguage)

        case .plus:
            return appText("billing.plus", languageCode: appLanguage)

        case .premium:
            return appText("billing.premium", languageCode: appLanguage)
        }
    }
}
