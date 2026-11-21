import SwiftUI

struct ForwardingSettingsView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"
    @StateObject private var vm = ForwardingSettingsViewModel()
    private let fetchSettings: (String) async throws -> ForwardingSettingsDTO
    private let saveSettings: (ForwardingSettingsDTO, String) async throws -> ForwardingSettingsDTO

    init(
        fetchSettings: @escaping (String) async throws -> ForwardingSettingsDTO = {
            try await ForwardingService.shared.fetchSettings(token: $0)
        },
        saveSettings: @escaping (ForwardingSettingsDTO, String) async throws -> ForwardingSettingsDTO = {
            try await ForwardingService.shared.saveSettings($0, token: $1)
        }
    ) {
        self.fetchSettings = fetchSettings
        self.saveSettings = saveSettings
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SectionCardView(
                    title: appText(
                        "forwarding.callTextForwarding",
                        languageCode: appLanguage
                    )
                    ) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(
                            appText(
                                "forwarding.description",
                                languageCode: appLanguage
                            )
                        )
                            .font(.footnote)
                            .foregroundStyle(themeManager.cardSecondaryText)

                        if let banner = vm.banner, !banner.isEmpty {
                            Text(banner)
                                .font(.footnote)
                                .foregroundStyle(themeManager.statusTextForeground(.green, on: themeManager.palette.cardBackground))
                        }

                        if let error = vm.errorMessage, !error.isEmpty {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(themeManager.statusTextForeground(.red, on: themeManager.palette.cardBackground))
                        }

                        Divider()

                        Toggle(
                            appText("forwarding.enableTextForwarding", languageCode: appLanguage),
                            isOn: $vm.forwardingEnabledSms
                        )
                        .foregroundStyle(themeManager.palette.primaryText)
                        .tint(themeManager.controlIconForeground(themeManager.palette.accent, on: themeManager.palette.cardBackground))

                        if let smsError = vm.validationErrors["smsToggle"], vm.forwardingEnabledSms {
                            Text(smsError)
                                .font(.caption)
                                .foregroundStyle(themeManager.statusTextForeground(.red, on: themeManager.palette.cardBackground))
                        }

                        Toggle(
                            appText("forwarding.forwardTextsToPhone", languageCode: appLanguage),
                            isOn: $vm.forwardSmsToPhone
                        )
                        .foregroundStyle(themeManager.palette.primaryText)
                        .tint(themeManager.controlIconForeground(themeManager.palette.accent, on: themeManager.palette.cardBackground))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(appText("forwarding.destinationPhoneE164", languageCode: appLanguage))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(themeManager.palette.primaryText)

                            TextField("", text: $vm.forwardPhoneNumber,
                                      prompt: Text("+15551234567").foregroundColor(themeManager.cardSecondaryText))
                                .textFieldStyle(.roundedBorder)
                                .foregroundStyle(themeManager.palette.primaryText)
                                .accessibilityLabel(appText("forwarding.destinationPhoneE164", languageCode: appLanguage))
                                .keyboardType(.phonePad)
                                .disabled(!vm.forwardSmsToPhone)

                            if let err = vm.validationErrors["forwardPhoneNumber"] {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(themeManager.statusTextForeground(.red, on: themeManager.palette.cardBackground))
                            }
                        }

                        Toggle(
                            appText("forwarding.forwardTextsToEmail", languageCode: appLanguage),
                            isOn: $vm.forwardSmsToEmail
                        )
                        .foregroundStyle(themeManager.palette.primaryText)
                        .tint(themeManager.controlIconForeground(themeManager.palette.accent, on: themeManager.palette.cardBackground))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(appText("forwarding.destinationEmail", languageCode: appLanguage))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(themeManager.palette.primaryText)

                            TextField("", text: $vm.forwardEmail,
                                      prompt: Text("me@example.com").foregroundColor(themeManager.cardSecondaryText))
                                .textFieldStyle(.roundedBorder)
                                .foregroundStyle(themeManager.palette.primaryText)
                                .accessibilityLabel(appText("forwarding.destinationEmail", languageCode: appLanguage))
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .disabled(!vm.forwardSmsToEmail)

                            if let err = vm.validationErrors["forwardEmail"] {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(themeManager.statusTextForeground(.red, on: themeManager.palette.cardBackground))
                            }
                        }

                        Divider()

                        Toggle(
                            appText(
                                "forwarding.enableCallForwarding",
                                languageCode: appLanguage
                            ),
                            isOn: $vm.forwardingEnabledCalls
                        )
                        .foregroundStyle(themeManager.palette.primaryText)
                        .tint(themeManager.controlIconForeground(themeManager.palette.accent, on: themeManager.palette.cardBackground))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(
                                appText(
                                    "forwarding.destinationCallsE164",
                                    languageCode: appLanguage
                                )
                            )
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(themeManager.palette.primaryText)

                            TextField("", text: $vm.forwardToPhoneE164,
                                      prompt: Text("+15551234567").foregroundColor(themeManager.cardSecondaryText))
                                .textFieldStyle(.roundedBorder)
                                .foregroundStyle(themeManager.palette.primaryText)
                                .accessibilityLabel(appText("forwarding.destinationCallsE164", languageCode: appLanguage))
                                .keyboardType(.phonePad)
                                .disabled(!vm.forwardingEnabledCalls)

                            if let err = vm.validationErrors["forwardToPhoneE164"] {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(themeManager.statusTextForeground(.red, on: themeManager.palette.cardBackground))
                            }
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(appText("settings.startHour", languageCode: appLanguage))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(themeManager.palette.primaryText)

                                TextField(
                                    "",
                                    text: Binding(
                                        get: { vm.forwardQuietHoursStart.map(String.init) ?? "" },
                                        set: { vm.forwardQuietHoursStart = Int($0) }
                                    ),
                                    prompt: Text("0").foregroundColor(themeManager.cardSecondaryText)
                                )
                                .textFieldStyle(.roundedBorder)
                                .foregroundStyle(themeManager.palette.primaryText)
                                .accessibilityLabel(appText("settings.startHour", languageCode: appLanguage))
                                .keyboardType(.numberPad)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(appText("settings.endHour", languageCode: appLanguage))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(themeManager.palette.primaryText)

                                TextField(
                                    "",
                                    text: Binding(
                                        get: { vm.forwardQuietHoursEnd.map(String.init) ?? "" },
                                        set: { vm.forwardQuietHoursEnd = Int($0) }
                                    ),
                                    prompt: Text("23").foregroundColor(themeManager.cardSecondaryText)
                                )
                                .textFieldStyle(.roundedBorder)
                                .foregroundStyle(themeManager.palette.primaryText)
                                .accessibilityLabel(appText("settings.endHour", languageCode: appLanguage))
                                .keyboardType(.numberPad)
                            }
                        }

                        if let quietErr = vm.validationErrors["quiet"] {
                            Text(quietErr)
                                .font(.caption)
                                .foregroundStyle(themeManager.statusTextForeground(.red, on: themeManager.palette.cardBackground))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Quiet-hours time zone (IANA)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(themeManager.palette.primaryText)
                            TextField("", text: $vm.forwardQuietHoursTimeZone,
                                      prompt: Text("America/Denver").foregroundColor(themeManager.cardSecondaryText))
                                .textFieldStyle(.roundedBorder)
                                .foregroundStyle(themeManager.palette.primaryText)
                                .accessibilityLabel("Quiet-hours time zone (IANA)")
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            if let error = vm.validationErrors["timeZone"] {
                                Text(error).font(.caption)
                                    .foregroundStyle(themeManager.statusTextForeground(.red, on: themeManager.palette.cardBackground))
                            }
                            Text(vm.initialState?.forwardQuietHoursTimeZone == nil
                                ? "Device time zone suggested. Save to use it across devices; existing quiet hours use the server time zone until saved."
                                : "Saved for this account across devices. Daylight-saving changes follow this zone.")
                                .font(.caption)
                                .foregroundStyle(themeManager.cardSecondaryText)
                        }

                        HStack {
                            Button(
                                appText(
                                    "common.reset",
                                    languageCode: appLanguage
                                )
                            ) {
                                vm.reset()
                            }
                            .buttonStyle(.bordered)
                            .tint(themeManager.cardActionText)
                            .disabled(!vm.hasChanges || vm.isSaving)

                            Spacer()

                            Button {
                                Task { await save() }
                            } label: {
                                if vm.isSaving {
                                    ProgressView()
                                } else {
                                    Text(appText("forwarding.saveForwarding", languageCode: appLanguage))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(themeManager.palette.accent)
                            .foregroundStyle(themeManager.textOnAccent)
                            .disabled(!vm.hasChanges || !vm.validationErrors.isEmpty)
                        }
                    }
                    .tint(themeManager.cardActionText)
                    .environment(\.colorScheme, themeManager.navigationColorScheme)
                }
            }
            .padding()
        }
        .background(themeManager.palette.screenBackground.ignoresSafeArea())
        .navigationTitle(
            appText(
                "forwarding.title",
                languageCode: appLanguage
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .modifier(ThemedNavigationBar())
        .task(id: auth.currentUser?.id) {
            await load()
#if DISAPPEARING_QA
            if ProcessInfo.processInfo.arguments.contains("--forwarding-qa-save-reopen"),
               auth.currentUser?.id == 1, vm.initialState?.forwardQuietHoursTimeZone == nil {
                vm.forwardQuietHoursTimeZone = "America/Denver"
                vm.forwardQuietHoursStart = 21
                await save()
                NotificationCenter.default.post(name: Notification.Name("ForwardingQASaved"), object: nil)
            }
#endif
        }
    }

    private func load() async {
        vm.clearForAccountChange()
        let accountID = auth.currentUser?.id
        guard let token = auth.currentToken, !token.isEmpty else {
            auth.handleInvalidSession()
            return
        }

        do {
            vm.isLoading = true
            vm.errorMessage = nil
            let dto = try await fetchSettings(token)
            guard auth.currentUser?.id == accountID, !Task.isCancelled else { return }
            vm.load(from: dto)
        } catch {
            guard auth.currentUser?.id == accountID, !Task.isCancelled else { return }
            vm.errorMessage = error.localizedDescription
        }

        if auth.currentUser?.id == accountID { vm.isLoading = false }
    }

    private func save() async {
        let accountID = auth.currentUser?.id
        guard let token = auth.currentToken, !token.isEmpty else {
            auth.handleInvalidSession()
            return
        }

        do {
            vm.isSaving = true
            vm.banner = nil
            vm.errorMessage = nil

            let saved = try await saveSettings(vm.makeRequest(), token)
            guard auth.currentUser?.id == accountID, !Task.isCancelled else { return }
            vm.load(from: saved)
            vm.banner = appText(
                "forwarding.saved",
                languageCode: appLanguage
            )
        } catch {
            guard auth.currentUser?.id == accountID, !Task.isCancelled else { return }
            vm.errorMessage = error.localizedDescription
        }

        if auth.currentUser?.id == accountID { vm.isSaving = false }
    }
}
