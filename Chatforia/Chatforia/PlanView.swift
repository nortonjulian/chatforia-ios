import SwiftUI

struct PlanView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var plusQuote: PricingQuote?
    @State private var premiumMonthlyQuote: PricingQuote?
    @State private var premiumAnnualQuote: PricingQuote?

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
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            async let plus = PricingQuoteService.shared.getQuote(product: .plus)
            async let premiumMonthly = PricingQuoteService.shared.getQuote(product: .premiumMonthly)
            async let premiumAnnual = PricingQuoteService.shared.getQuote(product: .premiumAnnual)

            plusQuote = await plus
            premiumMonthlyQuote = await premiumMonthly
            premiumAnnualQuote = await premiumAnnual
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
        SectionCardView(title: "Choose Your Plan") {
            VStack(spacing: 16) {
                planComparisonSection

                Divider()
                    .overlay(themeManager.palette.border)
                    .padding(.vertical, 6)

                if currentPlan == .free {
                    ThemedOutlineButton(title: plusButtonTitle) {
                        handleUpgradeToPlusTapped()
                    }

                    ThemedOutlineButton(title: premiumMonthlyButtonTitle) {
                        handleUpgradeToPremiumMonthlyTapped()
                    }

                    Button {
                        handleUpgradeToPremiumAnnualTapped()
                    } label: {
                        VStack(spacing: 4) {
                            Text("BEST VALUE")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(themeManager.palette.primaryText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(themeManager.palette.highlightedSurface)
                                .clipShape(Capsule())

                            Text(premiumAnnualButtonTitle)
                                .font(.headline)
                                .foregroundStyle(themeManager.palette.buttonForeground)

                            Text("Save 25% vs monthly")
                                .font(.caption2)
                                .foregroundStyle(themeManager.palette.buttonForeground.opacity(0.9))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
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
                        .shadow(color: themeManager.palette.buttonEnd.opacity(0.28), radius: 10, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)

                } else if currentPlan == .plus {
                    ThemedOutlineButton(title: premiumMonthlyButtonTitle) {
                        handleUpgradeToPremiumMonthlyTapped()
                    }

                    Button {
                        handleUpgradeToPremiumAnnualTapped()
                    } label: {
                        VStack(spacing: 4) {
                            Text(premiumAnnualButtonTitle)
                                .font(.headline)
                                .foregroundStyle(themeManager.palette.buttonForeground)

                            Text("Save 25% vs monthly")
                                .font(.caption)
                                .foregroundStyle(themeManager.palette.buttonForeground.opacity(0.9))
                        }
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
                        .shadow(color: themeManager.palette.buttonEnd.opacity(0.28), radius: 10, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)

                    ThemedOutlineButton(title: "Manage Billing") {
                        handleManageBillingTapped()
                    }

                } else {
                    ThemedOutlineButton(title: "Manage Billing") {
                        handleManageBillingTapped()
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
        AppPlan(serverValue: auth.currentUser?.plan)
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

    private var plusButtonTitle: String {
        let price = PricingQuoteService.shared.formattedPrice(for: plusQuote, fallbackProduct: .plus) ?? "$4.99"
        return "Upgrade to Plus — \(price)/mo"
    }

    private var premiumMonthlyButtonTitle: String {
        let price = PricingQuoteService.shared.formattedPrice(
            for: premiumMonthlyQuote,
            fallbackProduct: .premiumMonthly
        ) ?? "$24.99"

        return "Upgrade to Premium Monthly — \(price)/mo"
    }

    private var premiumAnnualButtonTitle: String {
        let price = PricingQuoteService.shared.formattedPrice(
            for: premiumAnnualQuote,
            fallbackProduct: .premiumAnnual
        ) ?? "$225.00"

        return "Upgrade to Premium Annual — \(price)/yr"
    }

    private func handleManageBillingTapped() {
        print("TODO: Paddle billing portal")
    }

    private func handleUpgradeToPlusTapped() {
        print("TODO: Paddle checkout - Plus")
    }

    private func handleUpgradeToPremiumMonthlyTapped() {
        print("TODO: Paddle checkout - Premium Monthly")
    }

    private func handleUpgradeToPremiumAnnualTapped() {
        print("TODO: Paddle checkout - Premium Annual")
    }
}

#Preview {
    NavigationStack {
        PlanView()
            .environmentObject(AuthStore())
            .environmentObject(ThemeManager())
    }
}
