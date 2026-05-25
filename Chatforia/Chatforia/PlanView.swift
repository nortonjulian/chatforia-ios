import SwiftUI

struct PlanView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager

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
        .navigationTitle(String(localized: "billing.planAndBilling"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showUpgrade) {
            UpgradeView()
                .environmentObject(auth)
                .environmentObject(themeManager)
        }
    }

    private var currentPlanSection: some View {
        SectionCardView(title: String(localized: "billing.myPlan")) {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(localized: "billing.currentPlan"))
                    .font(.subheadline)
                    .foregroundStyle(themeManager.palette.secondaryText)

                Text(currentPlan.displayName)
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
        SectionCardView(title: String(localized: "billing.comparePlans")) {
            VStack(spacing: 16) {
                planComparisonSection

                Divider()
                    .overlay(themeManager.palette.border)
                    .padding(.vertical, 6)

                switch currentPlan {
                case .free:
                    ThemedOutlineButton(
                        title: String(localized: "common.upgrade")
                    ) {
                        showUpgrade = true
                    }

                case .plus:
                    ThemedOutlineButton(
                        title: String(localized: "upgrade.to_premium")
                    ) {
                        showUpgrade = true
                    }

                    ThemedOutlineButton(
                        title: String(localized: "common.manageSubscription")
                    ) {
                        openManageSubscriptions()
                    }

                case .premium:
                    ThemedOutlineButton(
                        title: String(localized: "common.manageSubscription")
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
            Text(String(localized: "billing.compareDescription"))
                .font(.footnote)
                .foregroundStyle(themeManager.palette.secondaryText)

            HStack {
                Spacer()

                Text(String(localized: "billing.plus"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .frame(width: 40)

                Text(String(localized: "billing.premium"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .frame(width: 60)
            }

            planRow(String(localized: "billing.feature.adFree"), plus: true, premium: true)
            planRow(String(localized: "billing.feature.longerHistory"), plus: true, premium: true)
            planRow(String(localized: "billing.feature.forwarding"), plus: true, premium: true)
            planRow(String(localized: "billing.feature.aiTools"), plus: false, premium: true)
            planRow(String(localized: "billing.feature.premiumThemes"), plus: false, premium: true)
            planRow(String(localized: "billing.feature.prioritySupport"), plus: false, premium: true)
        }
    }

    private var includedSection: some View {
        SectionCardView(title: String(localized: "billing.includedTitle")) {
            VStack(alignment: .leading, spacing: 12) {
                featureRow(String(localized: "billing.included.messaging"))
                featureRow(String(localized: "billing.included.translation"))
                featureRow(String(localized: "billing.included.mediaSharing"))

                if currentPlan == .plus || currentPlan == .premium {
                    featureRow(String(localized: "billing.included.expandedAccess"))
                    featureRow(String(localized: "billing.included.enhancedFeatures"))
                }

                if currentPlan == .premium {
                    featureRow(String(localized: "billing.included.premiumThemes"))
                    featureRow(String(localized: "billing.included.premiumSounds"))
                    featureRow(String(localized: "billing.included.aiTools"))
                    featureRow(String(localized: "billing.included.prioritySupport"))
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

    private var planDescription: String {
        switch currentPlan {
        case .free:
            return String(localized: "billing.description.free")
        case .plus:
            return String(localized: "billing.description.plus")
        case .premium:
            return String(localized: "billing.description.premium")
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
