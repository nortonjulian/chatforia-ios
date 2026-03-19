import SwiftUI

struct PlanView: View {
    @EnvironmentObject var auth: AuthStore

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
        .background(Color(uiColor: .systemGroupedBackground))
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
                    .foregroundStyle(.secondary)

                Text(currentPlan.displayName)
                    .font(.title3.weight(.semibold))

                Text(planDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    private var billingSection: some View {
        SectionCardView(title: "Choose Your Plan") {
            VStack(spacing: 16) {
                planComparisonSection

                Divider()
                    .padding(.vertical, 6)

                if currentPlan == .free {

                    // PLUS
                    Button {
                        handleUpgradeToPlusTapped()
                    } label: {
                        Text(plusButtonTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)

                    // PREMIUM MONTHLY
                    Button {
                        handleUpgradeToPremiumMonthlyTapped()
                    } label: {
                        Text(premiumMonthlyButtonTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)

                    // PREMIUM ANNUAL (🔥 highlighted)
                    Button {
                        handleUpgradeToPremiumAnnualTapped()
                    } label: {
                        VStack(spacing: 4) {

                            // 🔥 Stronger badge
                            Text("BEST VALUE")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.white)
                                .clipShape(Capsule())

                            Text(premiumAnnualButtonTitle)
                                .font(.headline)

                            Text("Save 25% vs monthly")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.borderedProminent)
                    
                } else if currentPlan == .plus {

                    Button {
                        handleUpgradeToPremiumMonthlyTapped()
                    } label: {
                        Text(premiumMonthlyButtonTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        handleUpgradeToPremiumAnnualTapped()
                    } label: {
                        VStack(spacing: 2) {
                            Text(premiumAnnualButtonTitle)
                                .font(.headline)

                            Text("Save 25% vs monthly")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        handleManageBillingTapped()
                    } label: {
                        Text("Manage Billing")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)

                } else {

                    Button {
                        handleManageBillingTapped()
                    } label: {
                        Text("Manage Billing")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var planComparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Go ad-free with Plus, or unlock AI tools and customization with Premium.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()

                Text("Plus")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 40)

                Text("Premium")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.green)

            Text(text)
                .font(.body)

            Spacer()
        }
    }

    private func planRow(_ title: String, plus: Bool, premium: Bool) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)

            Spacer()

            HStack(spacing: 16) {
                Image(systemName: plus ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(plus ? .green : .gray)
                    .frame(width: 40)

                Image(systemName: premium ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(premium ? Color.accentColor : .gray)
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

    // MARK: Pricing Labels

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
    
    // MARK: Actions

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
    }
}
