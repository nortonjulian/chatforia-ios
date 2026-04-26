import SwiftUI

struct UpgradePromptSheet: View {
    let title: String
    let message: String
    let requiredPlan: AppPlan
    let onUpgradeTapped: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

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

                            Text("Requires \(requiredPlan.displayName)")
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
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    VStack(spacing: 12) {
                        ThemedGradientButton(
                            title: requiredPlan == .plus ? "Upgrade to Plus" : "Upgrade to Premium",
                            action: {
                                onUpgradeTapped()
                            },
                            horizontalPadding: 20,
                            verticalPadding: 14,
                            font: .headline.weight(.semibold)
                        )
                        .frame(maxWidth: .infinity)

                        ThemedOutlineButton(
                            title: "Not now",
                            action: {
                                dismiss()
                            }
                        )
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Upgrade Required")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                AnalyticsManager.shared.capture("upgrade_viewed", properties: [
                    "source": "upgrade_prompt",
                    "required_plan": requiredPlan.displayName
                ])
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(themeManager.palette.accent)
                }
            }
        }
    }
}
