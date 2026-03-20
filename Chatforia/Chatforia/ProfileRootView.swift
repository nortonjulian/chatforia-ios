import SwiftUI
import PhotosUI

struct ProfileRootView: View {
    let user: UserDTO

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var themeManager: ThemeManager

    @StateObject private var vm = SettingsViewModel()

    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var avatarUploadError: String?

    @State private var showingUpgradeSheet = false
    @State private var lockedFeatureTitle = ""
    @State private var lockedFeatureMessage = ""
    @State private var lockedRequiredPlan: AppPlan = .premium

    @State private var showingThemeSheet = false
    @State private var showingMessageToneSheet = false
    @State private var showingRingtoneSheet = false

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
            .background(themeManager.palette.screenBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ThemedNavigationTitle(title: "Profile")
                        .environmentObject(themeManager)
                }
            }
            .task {
                let sourceUser = auth.currentUser ?? user
                vm.load(from: sourceUser)

                let plan = AppPlan(serverValue: sourceUser.plan)
                let savedTheme = sourceUser.theme ?? "dawn"
                let themeToApply = AppThemes.isAvailable(savedTheme, for: plan) ? savedTheme : "dawn"
                themeManager.apply(code: themeToApply)
            }
            .sheet(isPresented: $showingUpgradeSheet) {
                UpgradePromptSheet(
                    title: lockedFeatureTitle,
                    message: lockedFeatureMessage,
                    requiredPlan: lockedRequiredPlan,
                    onUpgradeTapped: {
                        showingUpgradeSheet = false
                    }
                )
                .environmentObject(themeManager)
            }
            .sheet(isPresented: $showingThemeSheet) {
                PremiumPickerSheet(
                    title: "Theme",
                    subtitle: "Choose how Chatforia looks across the app.",
                    selectedCode: vm.theme,
                    currentPlan: currentPlan,
                    options: AppThemes.all.map {
                        PremiumSelectableOption(
                            id: $0.code,
                            code: $0.code,
                            name: $0.name,
                            requiredPlan: $0.requiredPlan
                        )
                    },
                    onSelect: { code in
                        attemptApplyTheme(code)
                    },
                    onLockedTap: { option in
                        presentUpgrade(
                            title: "Premium Theme",
                            message: "\(option.name) is available on \(option.requiredPlan.displayName).",
                            requiredPlan: option.requiredPlan
                        )
                    }
                )
                .environmentObject(themeManager)
            }
            .sheet(isPresented: $showingMessageToneSheet) {
                PremiumPickerSheet(
                    title: "Message Tone",
                    subtitle: "Pick the sound used for incoming Chatforia messages.",
                    selectedCode: vm.messageTone,
                    currentPlan: currentPlan,
                    options: AppMessageTones.all.map {
                        PremiumSelectableOption(
                            id: $0.code,
                            code: $0.code,
                            name: $0.name,
                            requiredPlan: $0.requiredPlan
                        )
                    },
                    onSelect: { code in
                        attemptApplyMessageTone(code)
                    },
                    onLockedTap: { option in
                        presentUpgrade(
                            title: "Premium Message Tone",
                            message: "\(option.name) is available on \(option.requiredPlan.displayName).",
                            requiredPlan: option.requiredPlan
                        )
                    }
                )
                .environmentObject(themeManager)
            }
            .sheet(isPresented: $showingRingtoneSheet) {
                PremiumPickerSheet(
                    title: "Ringtone",
                    subtitle: "Choose the ringtone used for Chatforia calling and alerts.",
                    selectedCode: vm.ringtone,
                    currentPlan: currentPlan,
                    options: AppRingtones.all.map {
                        PremiumSelectableOption(
                            id: $0.code,
                            code: $0.code,
                            name: $0.name,
                            requiredPlan: $0.requiredPlan
                        )
                    },
                    onSelect: { code in
                        attemptApplyRingtone(code)
                    },
                    onLockedTap: { option in
                        presentUpgrade(
                            title: "Premium Ringtone",
                            message: "\(option.name) is available on \(option.requiredPlan.displayName).",
                            requiredPlan: option.requiredPlan
                        )
                    }
                )
                .environmentObject(themeManager)
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

            let accent = themeManager.palette.accent

            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                Label("Change Photo", systemImage: "photo")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(accent)
            }

            if isUploadingAvatar {
                ProgressView("Uploading…")
                    .font(.caption)
                    .tint(themeManager.palette.accent)
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

    private var planSection: some View {
        SectionCardView(title: "Plan") {
            VStack(spacing: 0) {
                NavigationLink {
                    PlanView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "star.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(themeManager.palette.accent)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("View Plans")
                                .font(.body)
                                .foregroundStyle(themeManager.palette.primaryText)

                            Text("Current: \(currentPlan.displayName)")
                                .font(.subheadline)
                                .foregroundStyle(themeManager.palette.secondaryText)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if currentPlan.canManageBilling {
                    Divider()

                    HStack(spacing: 12) {
                        Image(systemName: "creditcard")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(themeManager.palette.accent)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Manage Billing")
                                .font(.body)
                                .foregroundStyle(themeManager.palette.primaryText)

                            Text("Available on your current plan.")
                                .font(.subheadline)
                                .foregroundStyle(themeManager.palette.secondaryText)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 10)
                }
            }
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
                        .foregroundStyle(themeManager.palette.accent)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chatforia Mobile")
                            .font(.body)
                            .foregroundStyle(themeManager.palette.primaryText)

                        Text("Browse eSIM data packs and manage wireless features.")
                            .font(.subheadline)
                            .foregroundStyle(themeManager.palette.secondaryText)
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

    private var profileSettingsSection: some View {
        SectionCardView(title: "Profile") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Preferred Language")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    Picker("Preferred Language", selection: $vm.preferredLanguage) {
                        ForEach(AppLanguages.all) { language in
                            Text(language.name).tag(language.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(themeManager.palette.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                ThemedToggleRow(
                    title: "Auto-translate messages",
                    isOn: $vm.autoTranslate
                )

                ThemedToggleRow(
                    title: "Show original alongside translation",
                    isOn: $vm.showOriginalWithTranslation
                )

                ThemedToggleRow(
                    title: "Enable read receipts",
                    isOn: $vm.showReadReceipts
                )
            }
        }
    }

    private var appearanceSection: some View {
        SectionCardView(title: "Appearance") {
            VStack(alignment: .leading, spacing: 14) {
                if !currentPlan.hasPremiumCustomization {
                    Text("You’re on Free — premium themes are shown below and can be unlocked with Premium.")
                        .font(.footnote)
                        .foregroundStyle(themeManager.palette.secondaryText)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Theme")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    Button {
                        showingThemeSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(AppThemes.name(for: vm.theme))
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(themeManager.palette.primaryText)

                                Text(AppThemes.requiredPlan(for: vm.theme) == .free ? "Free" : "Premium")
                                    .font(.caption)
                                    .foregroundStyle(themeManager.palette.secondaryText)
                            }

                            Spacer()

                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(themeManager.palette.secondaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(themeManager.palette.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(themeManager.palette.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var soundsSection: some View {
        SectionCardView(title: "Sounds") {
            VStack(alignment: .leading, spacing: 14) {
                if !currentPlan.hasPremiumSounds {
                    Text("You’re on Free — premium tones and ringtones are shown below and unlock with Premium.")
                        .font(.footnote)
                        .foregroundStyle(themeManager.palette.secondaryText)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Message tone")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    Button {
                        showingMessageToneSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(AppMessageTones.name(for: vm.messageTone))
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(themeManager.palette.primaryText)

                                Text(AppMessageTones.requiredPlan(for: vm.messageTone) == .free ? "Free" : "Premium")
                                    .font(.caption)
                                    .foregroundStyle(themeManager.palette.secondaryText)
                            }

                            Spacer()

                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(themeManager.palette.secondaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(themeManager.palette.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(themeManager.palette.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ringtone")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    Button {
                        showingRingtoneSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(AppRingtones.name(for: vm.ringtone))
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(themeManager.palette.primaryText)

                                Text(AppRingtones.requiredPlan(for: vm.ringtone) == .free ? "Free" : "Premium")
                                    .font(.caption)
                                    .foregroundStyle(themeManager.palette.secondaryText)
                            }

                            Spacer()

                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(themeManager.palette.secondaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(themeManager.palette.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(themeManager.palette.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Volume")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(themeManager.palette.primaryText)

                        Spacer()

                        Text("\(vm.soundVolume)%")
                            .foregroundStyle(themeManager.palette.secondaryText)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(vm.soundVolume) },
                            set: { vm.soundVolume = Int($0.rounded()) }
                        ),
                        in: 0...100,
                        step: 1
                    )
                    .tint(themeManager.palette.accent)
                }
            }
        }
    }

    private var disappearingMessagesSection: some View {
        SectionCardView(title: "Disappearing Messages") {
            VStack(alignment: .leading, spacing: 14) {
                ThemedToggleRow(
                    title: "Enable disappearing messages",
                    isOn: Binding(
                        get: { vm.autoDeleteSeconds > 0 },
                        set: { isOn in
                            vm.autoDeleteSeconds = isOn ? max(vm.autoDeleteSeconds, 10) : 0
                        }
                    )
                )

                if vm.autoDeleteSeconds > 0 {
                    Stepper(
                        value: $vm.autoDeleteSeconds,
                        in: 1...604800,
                        step: 1
                    ) {
                        Text("Delete after \(vm.autoDeleteSeconds) seconds")
                            .foregroundStyle(themeManager.palette.primaryText)
                    }
                    .tint(themeManager.palette.accent)
                }
            }
        }
    }

    private var privacySection: some View {
        SectionCardView(title: "Privacy") {
            VStack(alignment: .leading, spacing: 14) {
                ThemedToggleRow(
                    title: "Allow explicit content",
                    isOn: $vm.allowExplicitContent
                )

                ThemedToggleRow(
                    title: "Blur messages by default",
                    isOn: $vm.privacyBlurEnabled
                )

                ThemedToggleRow(
                    title: "Blur when app is unfocused",
                    isOn: $vm.privacyBlurOnUnfocus
                )

                ThemedToggleRow(
                    title: "Hold to reveal",
                    isOn: $vm.privacyHoldToReveal
                )

                ThemedToggleRow(
                    title: "Notify me if my message is copied",
                    isOn: $vm.notifyOnCopy
                )
            }
        }
    }

    private var randomChatSection: some View {
        SectionCardView(title: "Random Chat") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your age range")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

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
                    .tint(themeManager.palette.accent)
                }

                ThemedToggleRow(
                    title: "Use age-based matching",
                    isOn: $vm.wantsAgeFilter
                )
                .opacity(vm.ageBand == nil ? 0.55 : 1.0)
                .disabled(vm.ageBand == nil)

                ThemedToggleRow(
                    title: "Let Foria remember things you tell it",
                    isOn: $vm.foriaRemember
                )
            }
        }
    }

    private var voicemailSection: some View {
        SectionCardView(title: "Voicemail") {
            VStack(alignment: .leading, spacing: 14) {
                ThemedToggleRow(
                    title: "Enable voicemail",
                    isOn: $vm.voicemailEnabled
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Auto-delete voicemails after (days)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

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
                        .foregroundStyle(themeManager.palette.primaryText)

                    TextField("Email address", text: $vm.voicemailForwardEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Text fallback greeting")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    TextField("Greeting", text: $vm.voicemailGreetingText, axis: .vertical)
                        .lineLimit(3...5)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var forwardingSection: some View {
        SectionCardView(title: "Call & Text Forwarding") {
            if currentPlan.canUseForwarding {
                NavigationLink {
                    ForwardingSettingsView()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Manage Forwarding")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(themeManager.palette.primaryText)

                            Text("Forward incoming calls and texts to your verified phone or email.")
                                .font(.footnote)
                                .foregroundStyle(themeManager.palette.secondaryText)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    presentUpgrade(
                        title: "Forwarding Requires Plus",
                        message: "Call and text forwarding is available on Plus and Premium.",
                        requiredPlan: .plus
                    )
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Manage Forwarding 🔒")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(themeManager.palette.primaryText)

                            Text("Upgrade to Plus or Premium to enable forwarding.")
                                .font(.footnote)
                                .foregroundStyle(themeManager.palette.secondaryText)
                        }

                        Spacer()

                        Image(systemName: "lock.fill")
                            .foregroundStyle(themeManager.palette.secondaryText)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
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
        Group {
            if vm.isSaving {
                ProgressView()
                    .tint(themeManager.palette.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                ThemedGradientButton(
                    title: "Save Settings",
                    action: {
                        Task { await saveSettings() }
                    },
                    horizontalPadding: 20,
                    verticalPadding: 14,
                    font: .headline.weight(.semibold)
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var logoutButtonSection: some View {
        ThemedOutlineButton(
            title: "Log out",
            action: {
                auth.logout()
            }
        )
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private var currentPlan: AppPlan {
        AppPlan(serverValue: auth.currentUser?.plan ?? user.plan)
    }

    private func presentUpgrade(title: String, message: String, requiredPlan: AppPlan) {
        lockedFeatureTitle = title
        lockedFeatureMessage = message
        lockedRequiredPlan = requiredPlan
        showingUpgradeSheet = true
    }

    private func attemptApplyTheme(_ code: String) {
        if AppThemes.isAvailable(code, for: currentPlan) {
            vm.theme = code
            themeManager.apply(code: code)
        } else {
            presentUpgrade(
                title: "Premium Theme",
                message: "\(AppThemes.name(for: code)) is available on \(AppThemes.requiredPlan(for: code).displayName).",
                requiredPlan: AppThemes.requiredPlan(for: code)
            )
        }
    }

    private func attemptApplyMessageTone(_ code: String) {
        if AppMessageTones.isAvailable(code, for: currentPlan) {
            vm.messageTone = code
        } else {
            presentUpgrade(
                title: "Premium Message Tone",
                message: "\(AppMessageTones.name(for: code)) is available on \(AppMessageTones.requiredPlan(for: code).displayName).",
                requiredPlan: AppMessageTones.requiredPlan(for: code)
            )
        }
    }

    private func attemptApplyRingtone(_ code: String) {
        if AppRingtones.isAvailable(code, for: currentPlan) {
            vm.ringtone = code
        } else {
            presentUpgrade(
                title: "Premium Ringtone",
                message: "\(AppRingtones.name(for: code)) is available on \(AppRingtones.requiredPlan(for: code).displayName).",
                requiredPlan: AppRingtones.requiredPlan(for: code)
            )
        }
    }

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

        if !AppThemes.isAvailable(vm.theme, for: currentPlan) {
            vm.theme = "dawn"
        }

        if !AppMessageTones.isAvailable(vm.messageTone, for: currentPlan) {
            vm.messageTone = "Default.mp3"
        }

        if !AppRingtones.isAvailable(vm.ringtone, for: currentPlan) {
            vm.ringtone = "Classic.mp3"
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

            let updatedPlan = AppPlan(serverValue: updatedUser.plan)
            let updatedTheme = updatedUser.theme ?? "dawn"
            let themeToApply = AppThemes.isAvailable(updatedTheme, for: updatedPlan) ? updatedTheme : "dawn"
            themeManager.apply(code: themeToApply)

            vm.saveSuccessMessage = "Settings saved."
        } catch {
            vm.saveError = error.localizedDescription
        }

        vm.isSaving = false
    }
}
