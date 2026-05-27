import SwiftUI

struct ForwardingSettingsView: View {
    @EnvironmentObject var auth: AuthStore
    @AppStorage("chatforia_language") private var appLanguage = "en"
    @StateObject private var vm = ForwardingSettingsViewModel()

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
                            .foregroundStyle(.secondary)

                        if let banner = vm.banner, !banner.isEmpty {
                            Text(banner)
                                .font(.footnote)
                                .foregroundStyle(.green)
                        }

                        if let error = vm.errorMessage, !error.isEmpty {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        Divider()

                        Toggle(
                            appText("forwarding.enableTextForwarding", languageCode: appLanguage),
                            isOn: $vm.forwardingEnabledSms
                        )

                        if let smsError = vm.validationErrors["smsToggle"], vm.forwardingEnabledSms {
                            Text(smsError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Toggle(
                            appText("forwarding.forwardTextsToPhone", languageCode: appLanguage),
                            isOn: $vm.forwardSmsToPhone
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(appText("forwarding.destinationPhoneE164", languageCode: appLanguage))
                                .font(.subheadline.weight(.semibold))

                            TextField("+15551234567", text: $vm.forwardPhoneNumber)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.phonePad)
                                .disabled(!vm.forwardSmsToPhone)

                            if let err = vm.validationErrors["forwardPhoneNumber"] {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        Toggle(
                            appText("forwarding.forwardTextsToEmail", languageCode: appLanguage),
                            isOn: $vm.forwardSmsToEmail
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(appText("forwarding.destinationEmail", languageCode: appLanguage))
                                .font(.subheadline.weight(.semibold))

                            TextField("me@example.com", text: $vm.forwardEmail)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .disabled(!vm.forwardSmsToEmail)

                            if let err = vm.validationErrors["forwardEmail"] {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.red)
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

                        VStack(alignment: .leading, spacing: 6) {
                            Text(
                                appText(
                                    "forwarding.destinationCallsE164",
                                    languageCode: appLanguage
                                )
                            )
                                .font(.subheadline.weight(.semibold))

                            TextField("+15551234567", text: $vm.forwardToPhoneE164)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.phonePad)
                                .disabled(!vm.forwardingEnabledCalls)

                            if let err = vm.validationErrors["forwardToPhoneE164"] {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(appText("settings.startHour", languageCode: appLanguage))
                                    .font(.subheadline.weight(.semibold))

                                TextField(
                                    "0",
                                    text: Binding(
                                        get: { vm.forwardQuietHoursStart.map(String.init) ?? "" },
                                        set: { vm.forwardQuietHoursStart = Int($0) }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(appText("settings.endHour", languageCode: appLanguage))
                                    .font(.subheadline.weight(.semibold))

                                TextField(
                                    "23",
                                    text: Binding(
                                        get: { vm.forwardQuietHoursEnd.map(String.init) ?? "" },
                                        set: { vm.forwardQuietHoursEnd = Int($0) }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                            }
                        }

                        if let quietErr = vm.validationErrors["quiet"] {
                            Text(quietErr)
                                .font(.caption)
                                .foregroundStyle(.red)
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
                            .disabled(!vm.hasChanges || !vm.validationErrors.isEmpty)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(
            appText(
                "forwarding.title",
                languageCode: appLanguage
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
    }

    private func load() async {
        guard let token = auth.currentToken, !token.isEmpty else {
            auth.handleInvalidSession()
            return
        }

        do {
            vm.isLoading = true
            vm.errorMessage = nil
            let dto = try await ForwardingService.shared.fetchSettings(token: token)
            vm.load(from: dto)
        } catch {
            vm.errorMessage = error.localizedDescription
        }

        vm.isLoading = false
    }

    private func save() async {
        guard let token = auth.currentToken, !token.isEmpty else {
            auth.handleInvalidSession()
            return
        }

        do {
            vm.isSaving = true
            vm.banner = nil
            vm.errorMessage = nil

            let saved = try await ForwardingService.shared.saveSettings(
                vm.makeRequest(),
                token: token
            )
            vm.load(from: saved)
            vm.banner = appText(
                "forwarding.saved",
                languageCode: appLanguage
            )
        } catch {
            vm.errorMessage = error.localizedDescription
        }

        vm.isSaving = false
    }
}
