import SwiftUI

struct PlanView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"

    @State private var showUpgrade = false

    private let manageSubscriptionsURL =
        URL(string: "https://apps.apple.com/account/subscriptions")!

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                currentPlanSection
                billingSection
                includedSection
            }
            .padding()
        }
        .background(themeManager.palette.screenBackground)
        .navigationTitle(appText("billing.planAndBilling", languageCode: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showUpgrade) {
            UpgradeView()
                .environmentObject(auth)
                .environmentObject(themeManager)
        }
    }

    private var currentPlanSection: some View {
        SectionCardView(title: appText("billing.myPlan", languageCode: appLanguage)) {
            VStack(alignment: .leading, spacing: 14) {
                Text(
                    appText("billing.currentPlan", languageCode: appLanguage)
                        .replacingOccurrences(of: "{plan}", with: currentPlan.displayName)
                )
                    .font(.subheadline)
                    .foregroundStyle(themeManager.palette.secondaryText)

                Text(currentPlanDisplayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                Text(planDescription)
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }
            .padding(.vertical, 8)
        }
    }

    private var billingSection: some View {
        SectionCardView(title: appText("billing.comparePlans", languageCode: appLanguage)) {
            VStack(spacing: 16) {
                planComparisonSection

                Divider()
                    .overlay(themeManager.palette.border)
                    .padding(.vertical, 6)

                switch currentPlan {
                case .free:
                    ThemedOutlineButton(
                        title: appText("common.upgrade", languageCode: appLanguage)
                    ) {
                        showUpgrade = true
                    }

                case .plus:
                    ThemedOutlineButton(
                        title: appText("upgrade.to_premium", languageCode: appLanguage)
                    ) {
                        showUpgrade = true
                    }

                    ThemedOutlineButton(
                        title: appText("common.manageSubscription", languageCode: appLanguage)
                    ) {
                        openManageSubscriptions()
                    }

                case .premium:
                    ThemedOutlineButton(
                        title: appText("common.manageSubscription", languageCode: appLanguage)
                    ) {
                        openManageSubscriptions()
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var planComparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appText("billing.compareDescription", languageCode: appLanguage))
                .font(.footnote)
                .foregroundStyle(themeManager.palette.secondaryText)

            HStack {
                Spacer()

                Text(appText("billing.plus", languageCode: appLanguage))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .frame(width: 40)

                Text(appText("billing.premium", languageCode: appLanguage))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .frame(width: 60)
            }

            planRow(appText("billing.feature.adFree", languageCode: appLanguage), plus: true, premium: true)
            planRow(appText("billing.feature.longerHistory", languageCode: appLanguage), plus: true, premium: true)
            planRow(appText("billing.feature.forwarding", languageCode: appLanguage), plus: true, premium: true)
            planRow(appText("billing.feature.aiTools", languageCode: appLanguage), plus: false, premium: true)
            planRow(appText("billing.feature.premiumThemes", languageCode: appLanguage), plus: false, premium: true)
            planRow(appText("billing.feature.prioritySupport", languageCode: appLanguage), plus: false, premium: true)
        }
    }

    private var includedSection: some View {
        SectionCardView(title: appText("billing.includedTitle", languageCode: appLanguage)) {
            VStack(alignment: .leading, spacing: 12) {
                featureRow(appText("billing.included.messaging", languageCode: appLanguage))
                featureRow(appText("billing.included.translation", languageCode: appLanguage))
                featureRow(appText("billing.included.mediaSharing", languageCode: appLanguage))

                if currentPlan == .plus || currentPlan == .premium {
                    featureRow(appText("billing.included.expandedAccess", languageCode: appLanguage))
                    featureRow(appText("billing.included.enhancedFeatures", languageCode: appLanguage))
                }

                if currentPlan == .premium {
                    featureRow(appText("billing.included.premiumThemes", languageCode: appLanguage))
                    featureRow(appText("billing.included.premiumSounds", languageCode: appLanguage))
                    featureRow(appText("billing.included.aiTools", languageCode: appLanguage))
                    featureRow(appText("billing.included.prioritySupport", languageCode: appLanguage))
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func featureRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(themeManager.palette.accent)

            Text(text)
                .font(.body)
                .foregroundStyle(themeManager.palette.primaryText)

            Spacer()
        }
    }

    private func planRow(
        _ title: String,
        plus: Bool,
        premium: Bool
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.primaryText)

            Spacer()

            HStack(spacing: 16) {
                Image(systemName: plus ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(
                        plus
                            ? themeManager.palette.accent
                            : themeManager.palette.secondaryText
                    )
                    .frame(width: 40)

                Image(systemName: premium ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(
                        premium
                            ? themeManager.palette.buttonEnd
                            : themeManager.palette.secondaryText
                    )
                    .frame(width: 60)
            }
        }
    }

    private var currentPlan: AppPlan {
        AppPlan(serverValue: auth.currentUser?.normalizedPlan)
    }

    private var currentPlanDisplayName: String {
        switch currentPlan {
        case .free:
            return appText("billing.free", languageCode: appLanguage)
        case .plus:
            return appText("billing.plus", languageCode: appLanguage)
        case .premium:
            return appText("billing.premium", languageCode: appLanguage)
        }
    }

    private var planDescription: String {
        switch currentPlan {
        case .free:
            return appText("billing.description.free", languageCode: appLanguage)
        case .plus:
            return appText("billing.description.plus", languageCode: appLanguage)
        case .premium:
            return appText("billing.description.premium", languageCode: appLanguage)
        }
    }

    private func openManageSubscriptions() {
        UIApplication.shared.open(manageSubscriptionsURL)
    }
}

#Preview {
    NavigationStack {
        PlanView()
            .environmentObject(AuthStore())
            .environmentObject(ThemeManager())
    }
}
