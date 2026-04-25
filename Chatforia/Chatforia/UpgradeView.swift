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
    
    let trigger: UpgradeTrigger

    init(trigger: UpgradeTrigger = .standard) {
        self.trigger = trigger
    }

    // Replace with your real App Store Connect subscription group ID
    private let subscriptionGroupID = "22027546"

    private let privacyURL = URL(string: "https://chatforia.com/privacy")!
    private let termsURL = URL(string: "https://chatforia.com/terms")!
    private let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                
                if trigger == .keepNumber {
                    keepNumberAlert
                }
                
                benefitsSection
                subscriptionSection
                legalSection
                actionSection
            }
            .padding()
        }
        .background(themeManager.palette.screenBackground.ignoresSafeArea())
        .navigationTitle("Upgrade")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var keepNumberAlert: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(themeManager.palette.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text("Keep your number")
                    .font(.headline)
                    .foregroundStyle(themeManager.palette.primaryText)

                Text("Don’t lose your number — upgrade to Premium to keep it protected from recycling.")
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

    private var headerSection: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(themeManager.palette.accent.opacity(0.14))
                .frame(width: 84, height: 84)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(themeManager.palette.accent)
                )

            Text("Upgrade Chatforia")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(themeManager.palette.primaryText)
                .multilineTextAlignment(.center)

            Text("Choose Plus or Premium with monthly or annual billing.")
                .font(.body)
                .foregroundStyle(themeManager.palette.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private var benefitsSection: some View {
        VStack(spacing: 12) {
            benefitRow(
                icon: "nosign",
                title: "Plus",
                subtitle: "Remove ads and enjoy a cleaner Chatforia experience."
            )

            benefitRow(
                icon: "paintpalette",
                title: "Premium themes",
                subtitle: "Unlock additional looks and visual styles."
            )

            benefitRow(
                icon: "music.note",
                title: "Premium sounds",
                subtitle: "Get access to more tones and ringtones."
            )

            benefitRow(
                icon: "sparkles.rectangle.stack",
                title: "Premium",
                subtitle: "Unlock advanced features and future premium upgrades."
            )
        }
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plans")
                .font(.title3.weight(.semibold))
                .foregroundStyle(themeManager.palette.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            SubscriptionStoreView(groupID: subscriptionGroupID) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose the plan that fits you best.")
                        .font(.headline)
                        .foregroundStyle(themeManager.palette.primaryText)

                    Text("Plus removes ads. Premium includes more customization and premium features.")
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
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                title: "Maybe later",
                action: {
                    dismiss()
                }
            )
        }
    }

    private func benefitRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(themeManager.palette.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
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
}
