import SwiftUI

struct PickNumberSheet: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @StateObject var vm: PhoneNumberViewModel
    @State private var showUpgradeSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    modePicker
                    subtitleText
                    searchControls
                    lockInfo
                    availableHeader
                    resultsContent
                }
                .padding(16)
            }
            .background(themeManager.palette.screenBackground.ignoresSafeArea())
            .navigationTitle("Pick a Number")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(themeManager.palette.secondaryText)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showUpgradeSheet) {
            NavigationStack {
                UpgradeView(trigger: .keepNumber)
            }
            .environmentObject(auth)
            .environmentObject(themeManager)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 10) {
            ForEach(NumberPickMode.allCases) { mode in
                Button {
                    vm.mode = mode
                    vm.availableNumbers = []
                    vm.errorText = nil
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Capsule(style: .continuous)
                                .fill(vm.mode == mode ? themeManager.palette.accent : themeManager.palette.cardBackground)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var subtitleText: some View {
        Text(vm.mode.subtitle)
            .font(.subheadline)
            .foregroundStyle(themeManager.palette.secondaryText)
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Country")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                Picker("Country", selection: $vm.selectedCountry) {
                    ForEach(vm.countryOptions) { option in
                        Text(option.name).tag(option.code)
                    }
                }
                .pickerStyle(.menu)
                .tint(themeManager.palette.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(themeManager.palette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(themeManager.palette.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Area code")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    TextField("e.g., 415", text: $vm.areaCode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(themeManager.palette.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(themeManager.palette.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .frame(maxWidth: .infinity)

                Button {
                    print("🔎 Search tapped")
                    Task {
                        await MainActor.run {
                            print("🚀 calling vm.search()")
                        }
                        await vm.search(token: auth.currentToken)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text("Search")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(themeManager.palette.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(vm.isSearching)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Capability")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                Picker("Capability", selection: $vm.selectedCapability) {
                    Text("SMS").tag("sms")
                    Text("Voice").tag("voice")
                    Text("SMS + Voice").tag("both")
                }
                .pickerStyle(.menu)
                .tint(themeManager.palette.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(themeManager.palette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(themeManager.palette.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var lockInfo: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundStyle(themeManager.palette.secondaryText)

            Text("Premium numbers are protected from recycling while your Premium subscription is active.")
                .font(.footnote)
                .foregroundStyle(themeManager.palette.secondaryText)
        }
    }

    private var availableHeader: some View {
        VStack(spacing: 8) {
            Divider()
            Text("Available numbers")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(themeManager.palette.secondaryText)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if let error = vm.errorText, !error.isEmpty {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if vm.isSearching {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 16)
        } else if vm.availableNumbers.isEmpty {
            Text("Enter a 3-digit area code (US/CA only), or leave blank, then search.")
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        } else {
            VStack(spacing: 12) {
                ForEach(vm.availableNumbers) { number in
                    numberCard(number)
                }
            }
        }
    }

    private func numberCard(_ number: AvailableNumberDTO) -> some View {
        let e164 = number.e164 ?? number.number ?? "Unknown"
        let baseLocation = number.locality ?? number.local ?? number.display ?? ""

        let location =
            !baseLocation.isEmpty && !baseLocation.contains(",")
            ? [baseLocation, number.region].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            : baseLocation
        
        let caps = number.capabilities?.values ?? []

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "phone")
                    .foregroundStyle(themeManager.palette.accent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(e164)
                        .font(.system(size: 17, weight: .semibold)) // slightly bigger & clearer
                        .foregroundStyle(themeManager.palette.primaryText)
                    
                    if !location.isEmpty {
                        Text(location)
                            .font(.system(size: 14)) // was too small before
                            .foregroundStyle(themeManager.palette.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }

                    if !caps.isEmpty {
                        Text(caps.joined(separator: " • ").uppercased())
                            .font(.system(size: 13, weight: .medium)) // slightly stronger
                            .foregroundStyle(themeManager.palette.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                Spacer()

                Button(vm.mode == .premium ? "Keep" : "Select") {
                    if vm.mode == .premium && !auth.isPremium {
                        showUpgradeSheet = true
                        return
                    }

                    Task {
                        let ok = await vm.lease(number, token: auth.currentToken)

                        if !ok,
                           let error = vm.errorText?.lowercased(),
                           error.contains("premium") {
                            showUpgradeSheet = true
                            return
                        }

                        if ok { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isLeasing || vm.currentNumber != nil)
            }
        }
        .padding(14)
        .background(themeManager.palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(themeManager.palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
