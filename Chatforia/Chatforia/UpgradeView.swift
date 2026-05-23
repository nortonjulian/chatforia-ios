import SwiftUI
import StoreKit

enum UpgradeTrigger {
    case standard
    case keepNumber
}

struct UpgradeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var syncMessage: String?
    @State private var retryCount = 0

    let trigger: UpgradeTrigger

    init(trigger: UpgradeTrigger = .standard) {
        self.trigger = trigger
    }

    private let subscriptionGroupID = "22027546"

    private let privacyURL = URL(string: "https://chatforia.com/privacy")!
    private let termsURL = URL(string: "https://chatforia.com/legal/terms")!
    private let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    private var currentPlan: AppPlan {
        AppPlan(serverValue: auth.currentUser?.plan)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                heroSection

                if trigger == .keepNumber {
                    keepNumberAlert
                }

                plusCard
                premiumCard
                customizationSection
                subscriptionSection
                legalSection
                actionSection
            }
            .padding()
        }
        .background(themeManager.palette.screenBackground.ignoresSafeArea())
        .navigationTitle("common.upgrade")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            retryCount = 0
            await refreshPurchaseStatus(autoRetry: true)
        }
    }

    private var heroSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                themeManager.palette.buttonStart.opacity(0.22),
                                themeManager.palette.buttonEnd.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 92, height: 92)

                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(themeManager.palette.accent)
            }

            VStack(spacing: 8) {
                Text("Unlock more of Chatforia")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(themeManager.palette.primaryText)
                    .multilineTextAlignment(.center)

                Text("Choose a cleaner, more personal Chatforia experience.")
                    .font(.body)
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 8)
    }

    private var keepNumberAlert: some View {
        featureCard(
            icon: "lock.fill",
            title: "Keep your number",
            subtitle: "Upgrade to Premium to keep your number protected from recycling.",
            accent: themeManager.palette.accent
        )
    }

    private var plusCard: some View {
        planCard(
            badge: "PLUS",
            icon: "checkmark.seal.fill",
            title: "Cleaner communication",
            subtitle: "Remove distractions and unlock practical communication tools.",
            features: [
                "No ads",
                "Message forwarding",
                "Longer message history",
                "Faster support"
            ],
            highlighted: false
        )
    }

    private var premiumCard: some View {
        planCard(
            badge: "PREMIUM",
            icon: "sparkles",
            title: "The full Chatforia experience",
            subtitle: "Unlock personalization, AI tools, and advanced Chatforia features.",
            features: [
                "Everything in Plus",
                "Additional Chatforia themes",
                "Message tones & ringtones",
                "AI tools",
                "Priority features"
            ],
            highlighted: true
        )
    }

    private func planCard(
        badge: String,
        icon: String,
        title: String,
        subtitle: String,
        features: [String],
        highlighted: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(badge, systemImage: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(highlighted ? themeManager.palette.buttonForeground : themeManager.palette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        highlighted
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [themeManager.palette.buttonStart, themeManager.palette.buttonEnd],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        : AnyShapeStyle(themeManager.palette.accent.opacity(0.12))
                    )
                    .clipShape(Capsule())

                Spacer()

                if highlighted {
                    Text("upgrade.bestExperience")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(themeManager.palette.accent)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(themeManager.palette.primaryText)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(themeManager.palette.accent)

                        Text(feature)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(themeManager.palette.primaryText)
                    }
                }
            }
        }
        .padding(18)
        .background(
            highlighted
            ? themeManager.palette.highlightedSurface.opacity(0.65)
            : themeManager.palette.cardBackground
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    highlighted ? themeManager.palette.accent.opacity(0.55) : themeManager.palette.border,
                    lineWidth: highlighted ? 1.5 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(
            color: highlighted ? themeManager.palette.accent.opacity(0.12) : .clear,
            radius: 14,
            x: 0,
            y: 8
        )
    }

    private var customizationSection: some View {
        VStack(alignment: .leading, spacing: 14) {

            VStack(alignment: .leading, spacing: 6) {
                Text("profile.customization")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                Text("Unlock additional Chatforia themes, tones, and personalization features with Premium.")
                    .font(.subheadline)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }

            HStack(spacing: 10) {

                customizationPill(
                    icon: "paintpalette.fill",
                    title: "Themes"
                )

                customizationPill(
                    icon: "message.fill",
                    title: "Message tones"
                )

                customizationPill(
                    icon: "bell.fill",
                    title: "Ringtones"
                )
            }
        }
    }

    private func customizationPill(
        icon: String,
        title: String
    ) -> some View {

        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.palette.accent)

            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(themeManager.palette.primaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(themeManager.palette.cardBackground)
        .overlay(
            Capsule()
                .stroke(themeManager.palette.border, lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("upgrade.choosePlan")
                .font(.title3.weight(.semibold))
                .foregroundStyle(themeManager.palette.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("Best value • Save almost 36% annually")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(themeManager.palette.accent)

            SubscriptionStoreView(groupID: subscriptionGroupID) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Upgrade with Apple")
                        .font(.headline)
                        .foregroundStyle(themeManager.palette.primaryText)

                    Text("Plus removes ads and adds forwarding. Premium unlocks additional themes, message tones, ringtones, AI tools, and the full Chatforia experience.")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.palette.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
            .subscriptionStoreControlStyle(.prominentPicker)
            .subscriptionStoreButtonLabel(.multiline)
            .storeButton(.visible, for: .restorePurchases)
            .storeButton(.visible, for: .redeemCode)
            .background(themeManager.palette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(themeManager.palette.border, lineWidth: 1)
            )
        }
    }

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Link("Privacy Policy", destination: privacyURL)
                .font(.footnote.weight(.semibold))

            Link("Terms of Use", destination: termsURL)
                .font(.footnote.weight(.semibold))

            Link("Manage Subscription", destination: manageSubscriptionsURL)
                .font(.footnote.weight(.semibold))

            Text("Auto-renewable subscription. Payment is charged to your Apple Account at confirmation of purchase. Subscription automatically renews unless canceled at least 24 hours before the end of the current period. You can manage and cancel your subscription in your Apple account settings.")
                .font(.footnote)
                .foregroundStyle(themeManager.palette.secondaryText)
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

    private var actionSection: some View {
        VStack(spacing: 12) {
            ThemedOutlineButton(
                title: "Refresh purchase status",
                action: {
                    Task {
                        retryCount = 0
                        await refreshPurchaseStatus()
                    }
                }
            )

            if let syncMessage {
                Text(syncMessage)
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }

            ThemedOutlineButton(
                title: "Maybe later",
                action: {
                    dismiss()
                }
            )
        }
    }

    private func featureCard(
        icon: String,
        title: String,
        subtitle: String,
        accent: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
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

    private func refreshPurchaseStatus(autoRetry: Bool = false) async {
        syncMessage = autoRetry ? "Finalizing your subscription…" : "Checking your subscription…"

        await SubscriptionManager.shared.refreshEntitlements()
        await auth.refreshCurrentUser()

        if auth.isPaid {
            syncMessage = "Your subscription is active."
            retryCount = 0
            return
        }

        if retryCount < 3 {
            retryCount += 1
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await refreshPurchaseStatus(autoRetry: true)
        } else {
            syncMessage = "Still syncing. Please try again in a moment."
        }
    }
}
