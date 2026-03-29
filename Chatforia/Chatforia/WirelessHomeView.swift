import SwiftUI

struct WirelessHomeView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var selectedScope: EsimScope = .local
    @State private var quotes: [PricingProduct: PricingQuote] = [:]

    @State private var activationStatus: ESIMStatus = .none
    @State private var activationPayload: ESIMActivationDTO?

    @State private var showActivation = false

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
        }
        .navigationDestination(isPresented: $showActivation) {
            if let payload = activationPayload {
                ESIMActivationView(
                    viewModel: ESIMActivationViewModel(payload: payload)
                )
            }
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

    @ViewBuilder
    private var activationSection: some View {
        if activationStatus != .none {
            SectionCardView(title: "Your eSIM") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(statusText)
                        .font(.headline)
                        .foregroundStyle(themeManager.palette.primaryText)

                    if let payload = activationPayload?.planName, !payload.isEmpty {
                        Text(payload)
                            .font(.footnote)
                            .foregroundStyle(themeManager.palette.secondaryText)
                    }

                    Button {
                        openActivation()
                    } label: {
                        Text(buttonText)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 8)
            }
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
                    handleGetPackTapped(pack)
                } label: {
                    Text("Get this data pack")
                        .font(.headline)
                        .foregroundStyle(themeManager.palette.buttonForeground)
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
            }
            .padding(.vertical, 8)
        }
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

    private var statusText: String {
        switch activationStatus {
        case .readyToInstall:
            return "Ready to install"
        case .active:
            return "Service active"
        case .none:
            return ""
        }
    }

    private var buttonText: String {
        switch activationStatus {
        case .readyToInstall:
            return "Activate eSIM"
        case .active:
            return "Manage eSIM"
        case .none:
            return ""
        }
    }

    private func loadQuotes() async {
        let products = pricingProducts(for: selectedScope)
        quotes = await PricingQuoteService.shared.getQuotes(products: products)
    }

    private func loadActivationIfExists() async {
        // TODO: Replace with a real backend call when ready.
        // Example future logic:
        // if let payload = try? await ESIMService.shared.fetchCurrentActivation() {
        //     activationPayload = payload
        //     activationStatus = payload.status.lowercased() == "active" ? .active : .readyToInstall
        // }

        // Temporary placeholder so the screen does not show stale state by accident.
        activationPayload = nil
        activationStatus = .none
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

    private func openActivation() {
        guard activationPayload != nil else { return }
        showActivation = true
    }

    private func handleGetPackTapped(_ pack: DataPackOption) {
        Task {
            do {
                let payload = try await ESIMService.shared.purchaseAndProvision(pack: pack)
                activationPayload = payload
                activationStatus = .readyToInstall
                showActivation = true
            } catch {
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
