import SwiftUI

struct WirelessHomeView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"

    @State private var selectedScope: EsimScope = .local
    @State private var quotes: [PricingProduct: PricingQuote] = [:]

    @State private var activationStatus: ESIMStatus = .none
    @State private var activationPayload: ESIMActivationDTO?

    @State private var showActivation = false
    @State private var isPurchasingPack = false
    @State private var purchaseErrorMessage: String?
    @State private var purchasingPackProduct: String?

    @State private var wirelessStatus: WirelessStatusDTO?
    @State private var isLoadingStatus = false
    @State private var statusErrorMessage: String?

    @State private var selectedPackForCheckout: DataPackOption?
    @State private var showCheckout = false

    enum ESIMStatus {
        case none
        case readyToInstall
        case active
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroSection
                scopePickerSection
                activationSection
                usageSection

                if let purchaseErrorMessage {
                    Text(purchaseErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                packsSection
                actionsSection
                disclaimerSection
            }
            .padding()
        }
        .background(themeManager.palette.screenBackground)
        .navigationTitle(appText("ios.wireless", languageCode: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedScope) {
            await loadQuotes()
            await loadActivationIfExists()
            await loadWirelessStatus()
        }
        .navigationDestination(isPresented: $showActivation) {
            if let payload = activationPayload {
                ESIMActivationView(
                    viewModel: ESIMActivationViewModel(payload: payload)
                )
            }
        }
        .sheet(isPresented: $showCheckout) {
            if let pack = selectedPackForCheckout {
                CheckoutSheetView(
                    pack: pack,
                    onConfirm: {
                        Task {
                            await handleCheckoutConfirmed(pack)
                        }
                    }
                )
                .environmentObject(themeManager)
            }
        }
    }

    private var usageSection: some View {
        SectionCardView(
            title: appText("ios.current_usage", languageCode: appLanguage)
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if isLoadingStatus {
                    HStack(spacing: 10) {
                        ProgressView()

                        Text(appText("ios.loading_usage", languageCode: appLanguage))
                            .font(.footnote)
                            .foregroundStyle(themeManager.palette.secondaryText)
                    }
                    .padding(.vertical, 8)

                } else if let statusErrorMessage {
                    Text(statusErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.vertical, 8)

                } else if let status = wirelessStatus,
                          let source = status.source,
                          let totalMb = source.totalDataMb,
                          let remainingMb = source.remainingDataMb,
                          totalMb > 0 {

                    let usedMb = max(0, totalMb - remainingMb)
                    let progress = min(max(Double(usedMb) / Double(totalMb), 0), 1)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatGB(remainingMb))
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(themeManager.palette.primaryText)

                                Text(
                                    String(
                                        format: appText("ios.remaining_of", languageCode: appLanguage),
                                        formatGB(totalMb)
                                    )
                                )
                                .font(.footnote)
                                .foregroundStyle(themeManager.palette.secondaryText)
                            }

                            Spacer()

                            statusBadge(status.state)
                        }

                        ProgressView(value: progress)
                            .tint(statusColor(status.state))

                        HStack {
                            infoPill(
                                title: appText("ios.used", languageCode: appLanguage),
                                value: formatGB(usedMb)
                            )

                            Spacer()

                            infoPill(
                                title: appText("ios.left", languageCode: appLanguage),
                                value: formatGB(remainingMb)
                            )

                            Spacer()

                            infoPill(
                                title: appText("ios.expires", languageCode: appLanguage),
                                value: expirationText(from: source)
                            )
                        }
                    }
                    .padding(.vertical, 8)

                } else if let status = wirelessStatus, status.mode == "NONE" {
                    Text(
                        appText(
                            "ios.no_active_data_pack_yet_buy_a_pack_below_to_start_tracking_usage",
                            languageCode: appLanguage
                        )
                    )
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .padding(.vertical, 8)

                } else {
                    Text(
                        appText(
                            "ios.usage_details_will_appear_once_your_data_pack_is_active",
                            languageCode: appLanguage
                        )
                    )
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func loadWirelessStatus() async {
        isLoadingStatus = true
        statusErrorMessage = nil

        defer { isLoadingStatus = false }

        do {
            let status = try await WirelessService.shared.fetchWirelessStatus()
            print("✅ STATUS:", status)
            wirelessStatus = status
        } catch {
            wirelessStatus = nil
            statusErrorMessage = appText(
                "ios.we_couldnt_load_your_usage_right_now",
                languageCode: appLanguage
            )
            print("Failed to load wireless status:", error)
        }
    }

    private func statusBadge(_ state: String) -> some View {
        Text(stateLabel(state))
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor(state))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusColor(state).opacity(0.12))
            .clipShape(Capsule())
    }

    private func infoPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(themeManager.palette.secondaryText)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.palette.primaryText)
        }
    }

    private func statusColor(_ state: String) -> Color {
        switch state.uppercased() {
        case "LOW":
            return .orange
        case "EXHAUSTED", "EXPIRED":
            return .red
        default:
            return themeManager.palette.accent
        }
    }

    private func stateLabel(_ state: String) -> String {
        switch state.uppercased() {
        case "LOW":
            return appText("ios.low", languageCode: appLanguage)
        case "EXHAUSTED":
            return appText("ios.out", languageCode: appLanguage)
        case "EXPIRED":
            return appText("ios.expired", languageCode: appLanguage)
        case "OK":
            return appText("ios.active", languageCode: appLanguage)
        default:
            return appText("ios.unknown", languageCode: appLanguage)
        }
    }

    private func formatGB(_ mb: Int) -> String {
        let gb = Double(mb) / 1024.0

        if gb >= 10 {
            return String(format: "%.0f GB", gb)
        } else {
            return String(format: "%.1f GB", gb)
        }
    }

    private func expirationText(from source: WirelessStatusSourceDTO) -> String {
        if let days = source.daysRemaining {
            if days <= 0 {
                return appText("ios.today", languageCode: appLanguage)
            }

            if days == 1 {
                return appText("ios.one_day", languageCode: appLanguage)
            }

            return "\(days) \(appText("ios.days", languageCode: appLanguage))"
        }

        if let expiresAt = source.expiresAt {
            return expiresAt.formatted(date: .abbreviated, time: .omitted)
        }

        return appText("common.emptyDash", languageCode: appLanguage)
    }

    private var actionsSection: some View {
        SectionCardView(title: appText("ios.manage", languageCode: appLanguage)) {
            VStack(spacing: 12) {
                ThemedOutlineButton(
                    title: appText("ios.manage_wireless", languageCode: appLanguage)
                ) {
                    handleManageWirelessTapped()
                }

                ThemedOutlineButton(
                    title: appText("ios.port_my_number", languageCode: appLanguage)
                ) {
                    handlePortNumberTapped()
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var heroSection: some View {
        SectionCardView(
            title: appText("ios.chatforia_mobile", languageCode: appLanguage)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    appText(
                        "ios.stay_connected_when_youre_traveling_or_away_from_wifi",
                        languageCode: appLanguage
                    )
                )
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

                Text(
                    appText(
                        "ios.choose_a_one_time_esim_data_pack_for_local_europe_or_global_coverage",
                        languageCode: appLanguage
                    )
                )
                .font(.footnote)
                .foregroundStyle(themeManager.palette.secondaryText)
            }
            .padding(.vertical, 8)
        }
    }

    private var scopePickerSection: some View {
        SectionCardView(
            title: appText("wireless.coverage", languageCode: appLanguage)
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker(
                    selection: $selectedScope,
                    label: Text(appText("wireless.coverage", languageCode: appLanguage))
                ) {
                    ForEach(EsimScope.allCases) { scope in
                        Text(
                            scope.displayName(languageCode: appLanguage)
                        )
                            .tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                Text(
                    selectedScope.subtitle(languageCode: appLanguage)
                )
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)

                Text(
                    appText(
                        "ios.we_dont_sell_data_packs_under_3_gb",
                        languageCode: appLanguage
                    )
                )
                .font(.footnote)
                .foregroundStyle(themeManager.palette.secondaryText)
            }
            .padding(.vertical, 8)
        }
    }

    private var packsSection: some View {
        VStack(spacing: 16) {
            ForEach(WirelessCatalog.packs(for: selectedScope)) { pack in
                dataPackCard(pack)
            }
        }
    }

    private func dataPackCard(_ pack: DataPackOption) -> some View {
        SectionCardView(
            title: pack.title(languageCode: appLanguage)
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(
                    pack.displayDataAmount(languageCode: appLanguage)
                )
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                Text(priceLabel(for: pack))
                    .font(.title3.bold())
                    .foregroundStyle(themeManager.palette.primaryText)

                Text(
                    pack.description(languageCode: appLanguage)
                )
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)

                VStack(alignment: .leading, spacing: 10) {
                    featureRow(appText("ios.instant_esim_activation", languageCode: appLanguage))
                    featureRow(appText("ios.one_time_pack_no_contract", languageCode: appLanguage))
                    featureRow(appText("ios.top_up_anytime", languageCode: appLanguage))
                }

                Button {
                    selectedPackForCheckout = pack
                    showCheckout = true
                } label: {
                    HStack {
                        if isPurchasingPack {
                            ProgressView()
                                .tint(themeManager.palette.buttonForeground)
                        }

                        Text(
                            isPurchasingPack
                            ? appText("common.processing", languageCode: appLanguage)
                            : appText("ios.choose_this_pack", languageCode: appLanguage)
                        )
                        .font(.headline)
                        .foregroundStyle(themeManager.palette.buttonForeground)
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
                    .shadow(
                        color: themeManager.palette.buttonEnd.opacity(0.28),
                        radius: 10,
                        x: 0,
                        y: 4
                    )
                }
                .buttonStyle(.plain)
                .disabled(isPurchasingPack || showCheckout)
                .opacity((isPurchasingPack || showCheckout) ? 0.7 : 1)
            }
            .padding(.vertical, 8)
        }
    }

    private var activationSection: some View {
        SectionCardView(title: appText("ios.your_esim", languageCode: appLanguage)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(statusTextFull)
                    .font(.headline)
                    .foregroundStyle(themeManager.palette.primaryText)

                if let plan = activationPayload?.planName, !plan.isEmpty {
                    Text(plan)
                        .font(.footnote)
                        .foregroundStyle(themeManager.palette.secondaryText)
                }

                Button {
                    handleActivationTapped()
                } label: {
                    Text(buttonTextFull)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 8)
        }
    }

    private var statusTextFull: String {
        switch activationStatus {
        case .none:
            return appText("ios.you_dont_have_an_esim_yet", languageCode: appLanguage)
        case .readyToInstall:
            return appText("ios.your_esim_is_ready_to_install", languageCode: appLanguage)
        case .active:
            return appText("ios.your_esim_is_active", languageCode: appLanguage)
        }
    }

    private var buttonTextFull: String {
        switch activationStatus {
        case .none:
            return appText("esim.setup", languageCode: appLanguage)
        case .readyToInstall:
            return appText("esim.activate", languageCode: appLanguage)
        case .active:
            return appText("esim.manage", languageCode: appLanguage)
        }
    }

    private func openActivation() {
        guard activationPayload != nil else { return }
        showActivation = true
    }

    private func handleActivationTapped() {
        switch activationStatus {
        case .none:
            print("User should pick a pack first")
        case .readyToInstall, .active:
            openActivation()
        }
    }

    private var disclaimerSection: some View {
        Text(
            appText(
                "ios.esim_data_packs_require_an_esim_compatible_and_unlocked_device",
                languageCode: appLanguage
            )
        )
        .font(.caption)
        .foregroundStyle(themeManager.palette.secondaryText)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
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

    private func loadQuotes() async {
        let products = pricingProducts(for: selectedScope)
        quotes = await PricingQuoteService.shared.getQuotes(products: products)
    }

    private func loadActivationIfExists() async {
        do {
            if let payload = try await ESIMService.shared.fetchCurrentActivation() {
                activationPayload = payload

                let status = payload.status.lowercased()

                if status == "active" {
                    activationStatus = .active
                } else {
                    activationStatus = .readyToInstall
                }
            } else {
                activationPayload = nil
                activationStatus = .none
            }
        } catch {
            print("Failed to load activation:", error)
            activationPayload = nil
            activationStatus = .none
        }
    }

    private func handleCheckoutConfirmed(_ pack: DataPackOption) async {
        isPurchasingPack = true
        purchaseErrorMessage = nil

        defer { isPurchasingPack = false }

        do {
            let payload = try await ESIMService.shared.purchaseAndProvision(pack: pack)

            activationPayload = payload
            activationStatus = .readyToInstall

            await loadWirelessStatus()

            showCheckout = false
            showActivation = true

        } catch {
            purchaseErrorMessage = appText(
                "ios.we_couldnt_start_your_esim_activation",
                languageCode: appLanguage
            )
            print("Purchase/provision failed for product \(pack.product): \(error)")
        }
    }

    private func pricingProducts(for scope: EsimScope) -> [PricingProduct] {
        switch scope {
        case .local:
            return [
                .esimLocal3,
                .esimLocal5,
                .esimLocal10,
                .esimLocal20,
                .esimLocalUnlimited
            ]

        case .europe:
            return [
                .esimEurope3,
                .esimEurope5,
                .esimEurope10,
                .esimEurope20,
                .esimEuropeUnlimited
            ]

        case .global:
            return [
                .esimGlobal3,
                .esimGlobal5,
                .esimGlobal10,
                .esimGlobalUnlimited
            ]
        }
    }

    private func pricingProduct(for pack: DataPackOption) -> PricingProduct? {
        PricingProduct(rawValue: pack.product)
    }

    private func priceLabel(for pack: DataPackOption) -> String {
        guard let product = pricingProduct(for: pack) else {
            return appText("common.emptyDash", languageCode: appLanguage)
        }

        return PricingQuoteService.shared.formattedPrice(
            for: quotes[product],
            fallbackProduct: product
        ) ?? appText("common.emptyDash", languageCode: appLanguage)
    }

    private func handleGetPackTapped(_ pack: DataPackOption) {
        Task {
            isPurchasingPack = true
            purchaseErrorMessage = nil

            defer { isPurchasingPack = false }

            do {
                let payload = try await ESIMService.shared.purchaseAndProvision(pack: pack)

                activationPayload = payload
                activationStatus = .readyToInstall

                await loadWirelessStatus()

                showActivation = true

            } catch {
                purchaseErrorMessage = appText(
                    "ios.we_couldnt_start_your_esim_activation",
                    languageCode: appLanguage
                )
                print("Purchase/provision failed for product \(pack.product): \(error)")
            }
        }
    }

    private func handleManageWirelessTapped() {
        if activationPayload != nil {
            openActivation()
        } else {
            print("TODO: open wireless management")
        }
    }

    private func handlePortNumberTapped() {
        print("TODO: open port number flow")
    }
}

#Preview {
    NavigationStack {
        WirelessHomeView()
            .environmentObject(AuthStore())
            .environmentObject(ThemeManager())
    }
}
