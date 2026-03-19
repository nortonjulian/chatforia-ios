import SwiftUI
import PhotosUI


struct ProfileRootView: View {
    let user: UserDTO

    @EnvironmentObject var auth: AuthStore
    @StateObject private var vm = SettingsViewModel()

    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var avatarUploadError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    accountSection
                    planSection
                    wirelessSection
                    profileSettingsSection
                    appearanceSection
                    soundsSection
                    disappearingMessagesSection
                    privacySection
                    randomChatSection
                    voicemailSection
                    forwardingSection
                    feedbackSection
                    saveButtonSection
                    logoutButtonSection
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Profile")
            .task {
                if let current = auth.currentUser {
                    vm.load(from: current)
                } else {
                    vm.load(from: user)
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            ProfileHeaderView(
                username: auth.currentUser?.username ?? user.username,
                email: auth.currentUser?.email ?? user.email,
                plan: auth.currentUser?.plan ?? user.plan,
                avatarUrl: auth.currentUser?.avatarUrl ?? user.avatarUrl
            )

            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                Label("Change Photo", systemImage: "photo")
                    .font(.subheadline.weight(.medium))
            }

            if isUploadingAvatar {
                ProgressView("Uploading…")
                    .font(.caption)
            }

            if let avatarUploadError, !avatarUploadError.isEmpty {
                Text(avatarUploadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .onChange(of: selectedAvatarItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await uploadAvatar(from: newItem)
            }
        }
    }

    private var accountSection: some View {
        SectionCardView(title: "Account") {
            SettingsRowView(
                systemImage: "person.crop.circle",
                title: "Username",
                value: auth.currentUser?.username ?? user.username
            )

            Divider()

            SettingsRowView(
                systemImage: "envelope",
                title: "Email",
                value: displayValue(auth.currentUser?.email ?? user.email)
            )

            if let role = auth.currentUser?.role ?? user.role, !role.isEmpty {
                Divider()
                SettingsRowView(
                    systemImage: "briefcase",
                    title: "Role",
                    value: role
                )
            }

            if let plan = auth.currentUser?.plan ?? user.plan, !plan.isEmpty {
                Divider()
                SettingsRowView(
                    systemImage: "star",
                    title: "Plan",
                    value: plan
                )
            }
        }
    }

    private var profileSettingsSection: some View {
        SectionCardView(title: "Profile") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Preferred Language")
                        .font(.subheadline.weight(.semibold))

                    Picker("Preferred Language", selection: $vm.preferredLanguage) {
                        ForEach(AppLanguages.all) { language in
                            Text(language.name).tag(language.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                Toggle("Auto-translate messages", isOn: $vm.autoTranslate)
                Toggle("Show original alongside translation", isOn: $vm.showOriginalWithTranslation)
                Toggle("Enable read receipts", isOn: $vm.showReadReceipts)
            }
        }
    }

    private var appearanceSection: some View {
        let themes = AppThemes.available(for: currentPlan)

        return SectionCardView(title: "Appearance") {
            VStack(alignment: .leading, spacing: 14) {
                if !currentPlan.hasPremiumCustomization {
                    Text("You’re on Free—use the included themes below. Upgrade to unlock premium themes.")
                        .font(.footnote)
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Theme")
                        .font(.subheadline.weight(.semibold))

                    Picker("Theme", selection: $vm.theme) {
                        ForEach(themes) { theme in
                            Text(theme.name).tag(theme.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    
    private var soundsSection: some View {
        let messageTones = AppMessageTones.available(for: currentPlan)
        let ringtones = AppRingtones.available(for: currentPlan)

        return SectionCardView(title: "Sounds") {
            VStack(alignment: .leading, spacing: 14) {
                if !currentPlan.hasPremiumSounds {
                    Text("You’re on Free — premium tones are available with Premium.")
                        .font(.footnote)
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Message tone")
                        .font(.subheadline.weight(.semibold))

                    Picker("Message tone", selection: $vm.messageTone) {
                        ForEach(messageTones) { tone in
                            Text(tone.name).tag(tone.code)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ringtone")
                        .font(.subheadline.weight(.semibold))

                    Picker("Ringtone", selection: $vm.ringtone) {
                        ForEach(ringtones) { tone in
                            Text(tone.name).tag(tone.code)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Volume")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(vm.soundVolume)%")
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(vm.soundVolume) },
                            set: { vm.soundVolume = Int($0.rounded()) }
                        ),
                        in: 0...100,
                        step: 1
                    )
                }
            }
        }
    }

    private var disappearingMessagesSection: some View {
        SectionCardView(title: "Disappearing Messages") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(
                    "Enable disappearing messages",
                    isOn: Binding(
                        get: { vm.autoDeleteSeconds > 0 },
                        set: { isOn in
                            vm.autoDeleteSeconds = isOn ? max(vm.autoDeleteSeconds, 10) : 0
                        }
                    )
                )

                if vm.autoDeleteSeconds > 0 {
                    Stepper(
                        "Delete after \(vm.autoDeleteSeconds) seconds",
                        value: $vm.autoDeleteSeconds,
                        in: 1...604800,
                        step: 1
                    )
                }
            }
        }
    }

    private var privacySection: some View {
        SectionCardView(title: "Privacy") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Allow explicit content", isOn: $vm.allowExplicitContent)
                Toggle("Blur messages by default", isOn: $vm.privacyBlurEnabled)
                Toggle("Blur when app is unfocused", isOn: $vm.privacyBlurOnUnfocus)
                Toggle("Hold to reveal", isOn: $vm.privacyHoldToReveal)
                Toggle("Notify me if my message is copied", isOn: $vm.notifyOnCopy)
            }
        }
    }

    private var randomChatSection: some View {
        SectionCardView(title: "Random Chat") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your age range")
                        .font(.subheadline.weight(.semibold))

                    Picker(
                        "Your age range",
                        selection: Binding(
                            get: { vm.ageBand ?? "" },
                            set: { vm.ageBand = $0.isEmpty ? nil : $0 }
                        )
                    ) {
                        Text("Select age range").tag("")
                        Text("13–17").tag("TEEN_13_17")
                        Text("18–24").tag("ADULT_18_24")
                        Text("25–34").tag("ADULT_25_34")
                        Text("35–49").tag("ADULT_35_49")
                        Text("50+").tag("ADULT_50_PLUS")
                    }
                    .pickerStyle(.menu)
                }

                Toggle("Use age-based matching", isOn: $vm.wantsAgeFilter)
                    .disabled(vm.ageBand == nil)

                Toggle("Let Foria remember things you tell it", isOn: $vm.foriaRemember)
            }
        }
    }

    private var voicemailSection: some View {
        SectionCardView(title: "Voicemail") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Enable voicemail", isOn: $vm.voicemailEnabled)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Auto-delete voicemails after (days)")
                        .font(.subheadline.weight(.semibold))

                    TextField(
                        "Leave empty to keep forever",
                        text: Binding(
                            get: { vm.voicemailAutoDeleteDays.map(String.init) ?? "" },
                            set: { vm.voicemailAutoDeleteDays = Int($0) }
                        )
                    )
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Forward voicemail to email")
                        .font(.subheadline.weight(.semibold))

                    TextField("Email address", text: $vm.voicemailForwardEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Text fallback greeting")
                        .font(.subheadline.weight(.semibold))

                    TextField("Greeting", text: $vm.voicemailGreetingText, axis: .vertical)
                        .lineLimit(3...5)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    @ViewBuilder
    private var feedbackSection: some View {
        if let error = vm.saveError, !error.isEmpty {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }

        if let success = vm.saveSuccessMessage, !success.isEmpty {
            Text(success)
                .font(.caption)
                .foregroundStyle(.green)
                .multilineTextAlignment(.center)
        }
    }

    private var saveButtonSection: some View {
        Button {
            Task {
                await saveSettings()
            }
        } label: {
            if vm.isSaving {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                Text("Save Settings")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
        }
        .buttonStyle(.borderedProminent)
    }

    private var logoutButtonSection: some View {
        Button(role: .destructive) {
            auth.logout()
        } label: {
            Text("Log out")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .padding(.top, 4)
    }
    
    private var planSection: some View {
        SectionCardView(title: "Plan") {
            NavigationLink {
                PlanView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "creditcard")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Manage Plan")
                            .font(.body)
                            .foregroundStyle(.primary)

                        Text("Current: \(currentPlan.displayName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var forwardingSection: some View {
        SectionCardView(title: "Call & Text Forwarding") {
            NavigationLink {
                ForwardingSettingsView()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Manage Forwarding")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("Forward incoming calls and texts to your verified phone or email.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var wirelessSection: some View {
        SectionCardView(title: "Wireless") {
            NavigationLink {
                WirelessHomeView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chatforia Mobile")
                            .font(.body)
                            .foregroundStyle(.primary)

                        Text("Browse eSIM data packs and manage wireless features.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func displayValue(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "—"
        }
        return value
    }

    private func uploadAvatar(from item: PhotosPickerItem) async {
        avatarUploadError = nil

        guard let token = auth.currentToken, !token.isEmpty else {
            avatarUploadError = "Missing auth token."
            auth.handleInvalidSession()
            return
        }

        do {
            isUploadingAvatar = true

            guard let data = try await item.loadTransferable(type: Data.self) else {
                avatarUploadError = "Could not read selected image."
                isUploadingAvatar = false
                return
            }

            _ = try await APIClient.shared.uploadMultipart(
                path: "users/me/avatar",
                token: token,
                fieldName: "avatar",
                fileData: data,
                fileName: "avatar.jpg",
                mimeType: "image/jpeg"
            )

            await auth.refreshCurrentUser()
            isUploadingAvatar = false
        } catch {
            isUploadingAvatar = false
            avatarUploadError = error.localizedDescription
        }
    }

    private func saveSettings() async {
        guard let token = auth.currentToken, !token.isEmpty else {
            auth.handleInvalidSession()
            return
        }

        do {
            vm.isSaving = true
            vm.saveError = nil
            vm.saveSuccessMessage = nil

            let updatedUser = try await SettingsService.shared.updateSettings(
                vm.makeRequest(),
                token: token
            )

            auth.replaceCurrentUser(updatedUser)
            vm.load(from: updatedUser)
            vm.saveSuccessMessage = "Settings saved."
        } catch {
            vm.saveError = error.localizedDescription
        }

        vm.isSaving = false
    }
    
    private var currentPlan: AppPlan {
        AppPlan(serverValue: auth.currentUser?.plan ?? user.plan)
    }
}
