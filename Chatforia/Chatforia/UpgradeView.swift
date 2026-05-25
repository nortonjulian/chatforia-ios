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
        .navigationTitle(String(localized: "common.upgrade"))
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
                Text(String(localized: "upgrade.heroTitle"))
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(themeManager.palette.primaryText)
                    .multilineTextAlignment(.center)

                Text(String(localized: "upgrade.heroSubtitle"))
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
            title: String(localized: "upgrade.keepNumberTitle"),
            subtitle: String(localized: "upgrade.keepNumberSubtitle"),
            accent: themeManager.palette.accent
        )
    }

    private var plusCard: some View {
        planCard(
            badge: String(localized: "upgrade.plusBadge"),
            icon: "checkmark.seal.fill",
            title: String(localized: "upgrade.plusTitle"),
            subtitle: String(localized: "upgrade.plusSubtitle"),
            features: [
                String(localized: "upgrade.feature.noAds"),
                String(localized: "upgrade.feature.messageForwarding"),
                String(localized: "upgrade.feature.longerHistory"),
                String(localized: "upgrade.feature.fasterSupport")
            ],
            highlighted: false
        )
    }

    private var premiumCard: some View {
        planCard(
            badge: String(localized: "upgrade.premiumBadge"),
            icon: "sparkles",
            title: String(localized: "upgrade.premiumTitle"),
            subtitle: String(localized: "upgrade.premiumSubtitle"),
            features: [
                String(localized: "upgrade.feature.everythingInPlus"),
                String(localized: "upgrade.feature.additionalThemes"),
                String(localized: "upgrade.feature.tonesAndRingtones"),
                String(localized: "upgrade.feature.aiTools"),
                String(localized: "upgrade.feature.priorityFeatures")
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
                    Text(String(localized: "upgrade.bestExperience"))
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
                Text(String(localized: "profile.customization"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                Text(String(localized: "upgrade.customizationSubtitle"))
                    .font(.subheadline)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }

            HStack(spacing: 10) {
                customizationPill(
                    icon: "paintpalette.fill",
                    title: String(localized: "upgrade.pill.themes")
                )

                customizationPill(
                    icon: "message.fill",
                    title: String(localized: "upgrade.pill.messageTones")
                )

                customizationPill(
                    icon: "bell.fill",
                    title: String(localized: "upgrade.pill.ringtones")
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
            Text(String(localized: "upgrade.choosePlan"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(themeManager.palette.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(localized: "upgrade.bestValueAnnual"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(themeManager.palette.accent)

            SubscriptionStoreView(groupID: subscriptionGroupID) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "common.upgradeWithApple"))
                        .font(.headline)
                        .foregroundStyle(themeManager.palette.primaryText)

                    Text(String(localized: "upgrade.appleDescription"))
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
            Link(String(localized: "legal_privacy_policy"), destination: privacyURL)
                .font(.footnote.weight(.semibold))

            Link(String(localized: "legal_terms_of_service"), destination: termsURL)
                .font(.footnote.weight(.semibold))

            Link(String(localized: "common.manageSubscription"), destination: manageSubscriptionsURL)
                .font(.footnote.weight(.semibold))

            Text(String(localized: "upgrade.autoRenewNotice"))
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
                title: String(localized: "upgrade.refreshPurchaseStatus"),
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
                title: String(localized: "upgrade.maybeLater"),
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
        syncMessage = autoRetry
            ? String(localized: "upgrade.finalizingSubscription")
            : String(localized: "upgrade.checkingSubscription")

        await SubscriptionManager.shared.refreshEntitlements()
        await auth.refreshCurrentUser()

        if auth.isPaid {
            syncMessage = String(localized: "upgrade.subscriptionActive")
            retryCount = 0
            return
        }

        if retryCount < 3 {
            retryCount += 1
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await refreshPurchaseStatus(autoRetry: true)
        } else {
            syncMessage = String(localized: "upgrade.stillSyncing")
        }
    }
}
