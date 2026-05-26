import SwiftUI
import StoreKit

enum UpgradeTrigger {
    case standard
    case keepNumber
}

struct UpgradeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"
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
        .navigationTitle(
            appText(
                "common.upgrade",
                languageCode: appLanguage
            )
        )
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
                Text(
                    appText(
                        "upgrade.heroTitle",
                        languageCode: appLanguage
                    )
                )
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(themeManager.palette.primaryText)
                    .multilineTextAlignment(.center)

                Text(appText(
                    "upgrade.heroSubtitle",
                    languageCode: appLanguage
                ))
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
            title: appText(
                "upgrade.keepNumberTitle",
                languageCode: appLanguage
            ),
            subtitle: appText(
                "upgrade.keepNumberSubtitle",
                languageCode: appLanguage
            ),
            accent: themeManager.palette.accent
        )
    }

    private var plusCard: some View {
        planCard(
            badge: appText("upgrade.plusBadge", languageCode: appLanguage),
            icon: "checkmark.seal.fill",
            title: appText("upgrade.plusTitle", languageCode: appLanguage),
            subtitle: appText("upgrade.plusSubtitle", languageCode: appLanguage),
            features: [
                appText(
                    "upgrade.feature.noAds",
                    languageCode: appLanguage
                ),
                appText("upgrade.feature.messageForwarding", languageCode: appLanguage),
                appText("upgrade.feature.longerHistory", languageCode: appLanguage),
                appText("upgrade.feature.fasterSupport", languageCode: appLanguage)
            ],
            highlighted: false
        )
    }

    private var premiumCard: some View {
        planCard(
            badge: appText("upgrade.premiumBadge", languageCode: appLanguage),
            icon: "sparkles",
            title: appText("upgrade.premiumTitle", languageCode: appLanguage),
            subtitle: appText("upgrade.premiumSubtitle", languageCode: appLanguage),
            features: [
                appText("upgrade.feature.everythingInPlus", languageCode: appLanguage),
                appText("upgrade.feature.additionalThemes", languageCode: appLanguage),
                appText("upgrade.feature.tonesAndRingtones", languageCode: appLanguage),
                appText("upgrade.feature.aiTools", languageCode: appLanguage),
                appText("upgrade.feature.priorityFeatures", languageCode: appLanguage)
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
                    Text(appText(
                        "upgrade.bestExperience",
                        languageCode: appLanguage
                    ))
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
                Text(appText("profile.customization", languageCode: appLanguage))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                Text(appText("upgrade.customizationSubtitle", languageCode: appLanguage))
                    .font(.subheadline)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }

            HStack(spacing: 10) {
                customizationPill(
                    icon: "paintpalette.fill",
                    title: appText("upgrade.pill.themes", languageCode: appLanguage)
                )

                customizationPill(
                    icon: "message.fill",
                    title: appText("upgrade.pill.messageTones", languageCode: appLanguage)
                )

                customizationPill(
                    icon: "bell.fill",
                    title: appText("upgrade.pill.ringtones", languageCode: appLanguage)
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
            Text(appText("upgrade.choosePlan", languageCode: appLanguage))
                .font(.title3.weight(.semibold))
                .foregroundStyle(themeManager.palette.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(appText("upgrade.bestValueAnnual", languageCode: appLanguage))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(themeManager.palette.accent)

            SubscriptionStoreView(groupID: subscriptionGroupID) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appText("common.upgradeWithApple", languageCode: appLanguage))
                        .font(.headline)
                        .foregroundStyle(themeManager.palette.primaryText)

                    Text(appText("upgrade.appleDescription", languageCode: appLanguage))
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
            Link(
                appText(
                    "legal_privacy_policy",
                    languageCode: appLanguage
                ),
                destination: privacyURL
            )
                .font(.footnote.weight(.semibold))

            Link(appText("legal_terms_of_service", languageCode: appLanguage), destination: termsURL)
                .font(.footnote.weight(.semibold))

            Link(appText("common.manageSubscription", languageCode: appLanguage), destination: manageSubscriptionsURL)
                .font(.footnote.weight(.semibold))

            Text(appText("upgrade.autoRenewNotice", languageCode: appLanguage))
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
                title: appText("upgrade.refreshPurchaseStatus", languageCode: appLanguage),
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
                title: appText("upgrade.maybeLater", languageCode: appLanguage),
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
            ? appText("upgrade.finalizingSubscription", languageCode: appLanguage)
            : appText("upgrade.checkingSubscription", languageCode: appLanguage)
        await SubscriptionManager.shared.refreshEntitlements()
        await auth.refreshCurrentUser()

        if auth.isPaid {
            syncMessage = appText("upgrade.subscriptionActive", languageCode: appLanguage)
            retryCount = 0
            return
        }

        if retryCount < 3 {
            retryCount += 1
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await refreshPurchaseStatus(autoRetry: true)
        } else {
            syncMessage = appText("upgrade.stillSyncing", languageCode: appLanguage)
        }
    }
}
