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
                MonthlyUsageCard().id(auth.currentUser?.id)
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
            planRow(appText("billing.feature.aiTools", languageCode: appLanguage), plus: true, premium: true)
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
                    featureRow(appText("billing.included.aiTools", languageCode: appLanguage))
                }

                if currentPlan == .premium {
                    featureRow(appText("billing.included.premiumThemes", languageCode: appLanguage))
                    featureRow(appText("billing.included.premiumSounds", languageCode: appLanguage))
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


private struct MonthlyUsageCard: View {
    @State private var snapshot: PlanEntitlementsResponse?
    @State private var loading = true
    @State private var failed = false
    private let meters: [(String, String, Int)] = [
        ("riaActions", "Shared AI actions", 1),
        ("translationChars", "Translation characters", 1),
        ("hostedParticipantSeconds", "App-call participant-minutes", 60),
        ("smsMessages", "SMS and MMS messages", 1),
        ("pstnSeconds", "Phone-call minutes", 60),
        ("forwardingSeconds", "Forwarding minutes", 60),
        ("voiceNoteTranscriptionSeconds", "Voice-note transcription minutes", 60),
        ("voicemailTranscriptionSeconds", "Voicemail transcription minutes", 60)
    ]

    var body: some View {
        SectionCardView(title: String(localized: "Monthly usage", table: "Usage")) {
            VStack(alignment: .leading, spacing: 12) {
                if loading { ProgressView() }
                if failed { Text("Usage is unavailable. Please retry.", tableName: "Usage").foregroundStyle(.red) }
                if let snapshot {
                    ForEach(meters, id: \.0) { item in
                        let (key, label, divisor) = item
                        if let meter = snapshot.usage[key] {
                            let remaining = max(0, min(meter.remaining, meter.limit - meter.used))
                            VStack(alignment: .leading) {
                                Text(LocalizedStringKey(label), tableName: "Usage").font(.subheadline.bold())
                                Text("\(format(remaining, divisor)) of \(format(meter.limit, divisor)) remaining", tableName: "Usage")
                                    .font(.footnote)
                            }
                        }
                    }
                    if let date = resetDate(snapshot) {
                        Text("Resets \(date) at 00:00 UTC.", tableName: "Usage").font(.footnote)
                    }
                }
                Text("AI tools share one action allowance. Translation counts processed characters. Voice-note transcription and live captions share recorded usage; voicemail is separate. A zero limit means no included allowance. Feature eligibility still depends on your plan.", tableName: "Usage").font(.footnote)
                Text("App calls count each connected person's time against the caller's allowance. Two people calling for one minute use two participant-minutes.", tableName: "Usage").font(.footnote)
                Text("Reaching a limit pauses that feature until reset. It does not stop ordinary in-app text chat. Usage updates after processing; refresh for the latest balance.", tableName: "Usage").font(.footnote)
                Button { Task { await load() } } label: { Text("Refresh usage", tableName: "Usage") }.disabled(loading)
            }
        }.task { await load() }
    }

    private func format(_ value: Int, _ divisor: Int) -> String {
        let amount = floor(Double(value) / Double(divisor) * 10) / 10
        return amount.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func resetDate(_ value: PlanEntitlementsResponse) -> String? {
        guard let raw = value.resetAt else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: raw) else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    @MainActor private func load() async {
        loading = true; failed = false; snapshot = nil
        defer { loading = false }
        guard let token = TokenStore.shared.read(), !token.isEmpty else { failed = true; return }
        do {
            let response: PlanEntitlementsResponse = try await APIClient.shared.send(
                APIRequest(path: "premium/usage", method: .GET, requiresAuth: true), token: token)
            guard !Task.isCancelled else { return }
            guard resetDate(response) != nil, meters.allSatisfy({ item in
                guard let meter = response.usage[item.0] else { return false }
                return meter.used >= 0 && meter.limit >= 0 && meter.remaining >= 0
            }) else { failed = true; return }
            snapshot = response
        } catch { if !Task.isCancelled { failed = true } }
    }
}
