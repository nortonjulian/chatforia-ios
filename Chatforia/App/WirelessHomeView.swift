import SwiftUI

struct WirelessHomeView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager

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
        .navigationTitle("Wireless")
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
        SectionCardView(title: "Current Usage") {
            VStack(alignment: .leading, spacing: 14) {
                if isLoadingStatus {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading usage…")
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

                                Text("remaining of \(formatGB(totalMb))")
                                    .font(.footnote)
                                    .foregroundStyle(themeManager.palette.secondaryText)
                            }

                            Spacer()

                            statusBadge(status.state)
                        }

                        ProgressView(value: progress)
                            .tint(statusColor(status.state))

                        HStack {
                            infoPill(title: "Used", value: formatGB(usedMb))
                            Spacer()
                            infoPill(title: "Left", value: formatGB(remainingMb))
                            Spacer()
                            infoPill(title: "Expires", value: expirationText(from: source))
                        }
                    }
                    .padding(.vertical, 8)

                } else if let status = wirelessStatus, status.mode == "NONE" {
                    Text("No active data pack yet. Buy a pack below to start tracking usage.")
                        .font(.footnote)
                        .foregroundStyle(themeManager.palette.secondaryText)
                        .padding(.vertical, 8)

                } else {
                    Text("Usage details will appear once your data pack is active.")
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
            statusErrorMessage = "We couldn’t load your usage right now."
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
            return "Low"
        case "EXHAUSTED":
            return "Out"
        case "EXPIRED":
            return "Expired"
        case "OK":
            return "Active"
        default:
            return state.capitalized
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
            if days <= 0 { return "Today" }
            if days == 1 { return "1 day" }
            return "\(days) days"
        }

        if let expiresAt = source.expiresAt {
            return expiresAt.formatted(date: .abbreviated, time: .omitted)
        }

        return "—"
    }

    private var actionsSection: some View {
        SectionCardView(title: "Manage") {
            VStack(spacing: 12) {
                ThemedOutlineButton(title: "Manage Wireless") {
                    handleManageWirelessTapped()
                }

                ThemedOutlineButton(title: "Port My Number") {
                    handlePortNumberTapped()
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var heroSection: some View {
        SectionCardView(title: "Chatforia Mobile") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Stay connected when you’re traveling or away from Wi-Fi.")
                    .font(.headline)
                    .foregroundStyle(themeManager.palette.primaryText)

                Text("Choose a one-time eSIM data pack for Local, Europe, or Global coverage.")
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }
            .padding(.vertical, 8)
        }
    }

    private var scopePickerSection: some View {
        SectionCardView(title: "Coverage") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Coverage", selection: $selectedScope) {
                    ForEach(EsimScope.allCases) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                Text(selectedScope.subtitle)
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)

                Text("We don’t sell data packs under 3 GB.")
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
        SectionCardView(title: pack.title) {
            VStack(alignment: .leading, spacing: 14) {
                Text(pack.displayDataAmount)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                Text(priceLabel(for: pack))
                    .font(.title3.bold())
                    .foregroundStyle(themeManager.palette.primaryText)

                Text(pack.description)
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)

                VStack(alignment: .leading, spacing: 10) {
                    featureRow("Instant eSIM activation on supported devices")
                    featureRow("One-time pack, no contract")
                    featureRow("Top up anytime with another pack")
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

                        Text(isPurchasingPack ? "Processing..." : "Choose this pack")
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
        SectionCardView(title: "Your eSIM") {
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
            return "You don’t have an eSIM yet. Set one up to use mobile data."
        case .readyToInstall:
            return "Your eSIM is ready to install."
        case .active:
            return "Your eSIM is active."
        }
    }

    private var buttonTextFull: String {
        switch activationStatus {
        case .none:
            return "Set up eSIM"
        case .readyToInstall:
            return "Activate eSIM"
        case .active:
            return "Manage eSIM"
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
        Text("eSIM data packs require an eSIM-compatible and unlocked device. Availability varies by phone model, carrier, and country. Coverage and speeds vary by region.")
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
            purchaseErrorMessage = "We couldn’t start your eSIM activation right now. Please try again."
            print("Purchase/provision failed for product \(pack.product): \(error)")
        }
    }

    private func pricingProducts(for scope: EsimScope) -> [PricingProduct] {
        switch scope {
        case .local:
            return [.esimLocal3, .esimLocal5, .esimLocal10, .esimLocal20]
        case .europe:
            return [.esimEurope3, .esimEurope5, .esimEurope10, .esimEurope20]
        case .global:
            return [.esimGlobal3, .esimGlobal5]
        }
    }

    private func pricingProduct(for pack: DataPackOption) -> PricingProduct? {
        PricingProduct(rawValue: pack.product)
    }

    private func priceLabel(for pack: DataPackOption) -> String {
        guard let product = pricingProduct(for: pack) else { return "—" }

        return PricingQuoteService.shared.formattedPrice(
            for: quotes[product],
            fallbackProduct: product
        ) ?? "—"
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
                purchaseErrorMessage = "We couldn’t start your eSIM activation right now. Please try again."
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
