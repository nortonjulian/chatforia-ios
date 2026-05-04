import SwiftUI

struct PlanView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var showUpgrade = false

    private let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

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
        .navigationTitle("Plan & Billing")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showUpgrade) {
            UpgradeView()
                .environmentObject(auth)
                .environmentObject(themeManager)
        }
    }

    private var currentPlanSection: some View {
        SectionCardView(title: "My Plan") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Current plan")
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
        SectionCardView(title: "Compare Plans") {
            VStack(spacing: 16) {
                planComparisonSection

                Divider()
                    .overlay(themeManager.palette.border)
                    .padding(.vertical, 6)

                switch currentPlan {
                case .free:
                    ThemedOutlineButton(title: "Upgrade") {
                        showUpgrade = true
                    }

                case .plus:
                    ThemedOutlineButton(title: "Upgrade to Premium") {
                        showUpgrade = true
                    }

                    ThemedOutlineButton(title: "Manage Subscription") {
                        openManageSubscriptions()
                    }

                case .premium:
                    ThemedOutlineButton(title: "Manage Subscription") {
                        openManageSubscriptions()
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var planComparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Go ad-free with Plus, or unlock AI tools and customization with Premium.")
                .font(.footnote)
                .foregroundStyle(themeManager.palette.secondaryText)

            HStack {
                Spacer()

                Text("Plus")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .frame(width: 40)

                Text("Premium")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .frame(width: 60)
            }

            planRow("Ad-free experience", plus: true, premium: true)
            planRow("Longer message history", plus: true, premium: true)
            planRow("Call & text forwarding", plus: true, premium: true)
            planRow("AI tools", plus: false, premium: true)
            planRow("Premium themes & sounds", plus: false, premium: true)
            planRow("Priority support", plus: false, premium: true)
        }
    }

    private var includedSection: some View {
        SectionCardView(title: "Included") {
            VStack(alignment: .leading, spacing: 12) {
                featureRow("Messaging")
                featureRow("Translation")
                featureRow("Media sharing")

                if currentPlan == .plus || currentPlan == .premium {
                    featureRow("Expanded access")
                    featureRow("Enhanced features")
                }

                if currentPlan == .premium {
                    featureRow("Premium themes")
                    featureRow("Premium sounds")
                    featureRow("AI tools")
                    featureRow("Priority support")
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

    private func planRow(_ title: String, plus: Bool, premium: Bool) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.primaryText)

            Spacer()

            HStack(spacing: 16) {
                Image(systemName: plus ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(plus ? themeManager.palette.accent : themeManager.palette.secondaryText)
                    .frame(width: 40)

                Image(systemName: premium ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(premium ? themeManager.palette.buttonEnd : themeManager.palette.secondaryText)
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
            return "Basic access to Chatforia with core messaging features."
        case .plus:
            return "Ad-free access with longer history and forwarding features."
        case .premium:
            return "Full access to premium customization, AI tools, and priority support."
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
