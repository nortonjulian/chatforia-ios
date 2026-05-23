import SwiftUI
import PhotosUI

struct ProfileRootView: View {
    let user: UserDTO

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject private var inviteFlow: InviteFlowManager

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
    
    @StateObject private var contactsVM = ContactsViewModel()
    @State private var inviterRoom: ChatRoomDTO?
    @State private var showInviterChat = false
    
    @State private var showingBackupSheet = false
    @State private var showingRestoreSheet = false
    @State private var showingRotateSheet = false
    
    @State private var hasRemoteBackup: Bool?
    @State private var isCheckingBackup = false
    @State private var showUpgradeView = false
    
    @State private var showingDeleteAccountAlert = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    
    @AppStorage("chatforia_language")
    private var appLanguage = "en"
    

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    if let message = inviteFlow.redemptionMessage {
                        VStack(spacing: 12) {
                            InviteAttributionBannerView(text: message)

                            Button(String(localized: "button_message_inviter")) {
                                Task {
                                    if let room = await inviteFlow.openChatWithInviterIfPossible(
                                        auth: auth,
                                        contactsViewModel: contactsVM
                                    ) {
                                        inviterRoom = room
                                        showInviterChat = true
                                    }
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(themeManager.palette.accent)
                        }
                    }

                    headerSection
                    
                    if !auth.isPaid {
                        Button {
                            showUpgradeView = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(themeManager.palette.accent)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(String(localized: "button_upgrade"))
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(themeManager.palette.primaryText)

                                    Text(String(localized: "upgrade_choose_plus_or_premium"))
                                        .font(.subheadline)
                                        .foregroundStyle(themeManager.palette.secondaryText)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding()
                            .background(themeManager.palette.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    accountSection
                    planSection
                    wirelessSection
                    profileSettingsSection
                    securitySection
                    appearanceSection
                    soundsSection
                    disappearingMessagesSection
                    privacySection
                    randomChatSection
                    voicemailSection
                    forwardingSection
                    feedbackSection
                    legalSection
                    saveButtonSection
                    deleteAccountSection
                    logoutButtonSection
                }
                .padding()
            }
            .background(themeManager.palette.screenBackground)
            .navigationTitle(String(localized: "screen_profile"))
            .navigationBarTitleDisplayMode(.inline)
            
            .navigationDestination(isPresented: $showInviterChat) {
                if let room = inviterRoom {
                    ChatThreadView(room: room, randomSession: nil)
                }
            }
            .navigationDestination(isPresented: $showUpgradeView) {
                UpgradeView()
                    .environmentObject(auth)
                    .environmentObject(themeManager)
            }
            
            .task {
                let sourceUser = auth.currentUser ?? user
                vm.load(from: sourceUser)

                let plan = AppPlan(serverValue: sourceUser.plan)
                let savedTheme = sourceUser.theme ?? "dawn"
                let themeToApply = AppThemes.isAvailable(savedTheme, for: plan) ? savedTheme : "dawn"
                themeManager.apply(code: themeToApply)
                
                if let token = auth.currentToken, !token.isEmpty {
                    await loadBackupStatus(token: token)
                }
            }
            .sheet(isPresented: $showingUpgradeSheet) {
                UpgradePromptSheet(
                    title: lockedFeatureTitle,
                    message: lockedFeatureMessage,
                    requiredPlan: lockedRequiredPlan,
                    onUpgradeTapped: {
                        showingUpgradeSheet = false

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            showUpgradeView = true
                        }
                    }
                )
                .environmentObject(themeManager)
            }
            .sheet(isPresented: $showingThemeSheet) {
                PremiumPickerSheet(
                    title: String(localized: "sheet_theme_title"),
                    subtitle: String(localized: "sheet_theme_subtitle"),
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
                            title: String(localized: "premium_theme_title"),
                            message: String(
                                format: String(localized: "premium_feature_available_on_format"),
                                option.name,
                                option.requiredPlan.displayName
                            ),
                            requiredPlan: option.requiredPlan
                        )
                    }
                )
                .environmentObject(themeManager)
            }
            .sheet(isPresented: $showingMessageToneSheet) {
                PremiumPickerSheet(
                    title: String(localized: "sheet_message_tone_title"),
                    subtitle: String(localized: "sheet_message_tone_subtitle"),
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
                            title: String(localized: "premium_message_tone_title"),
                            message: String(
                                format: String(localized: "premium_feature_available_on_format"),
                                option.name,
                                option.requiredPlan.displayName
                            ),
                            requiredPlan: option.requiredPlan
                        )
                    }
                )
                .environmentObject(themeManager)
            }
            .sheet(isPresented: $showingRingtoneSheet) {
                PremiumPickerSheet(
                    title: String(localized: "sheet_ringtone_title"),
                    subtitle: String(localized: "sheet_ringtone_subtitle"),
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
                            title: String(localized: "premium_ringtone_title"),
                            message: String(
                                format: String(localized: "premium_feature_available_on_format"),
                                option.name,
                                option.requiredPlan.displayName
                            ),
                            requiredPlan: option.requiredPlan
                        )
                    }
                )
                .environmentObject(themeManager)
            }
            .sheet(isPresented: $showingBackupSheet) {
                BackupEncryptionKeyView()
                    .environmentObject(auth)
                    .environmentObject(themeManager)
            }

            .sheet(isPresented: $showingRestoreSheet) {
                RestoreEncryptionKeyView()
                    .environmentObject(auth)
                    .environmentObject(themeManager)
            }

            .sheet(isPresented: $showingRotateSheet) {
                RotateEncryptionKeyView()
                    .environmentObject(auth)
                    .environmentObject(themeManager)
            }
        }
    }
    
    struct AvatarRemoveResponse: Decodable {
        let avatarUrl: String?
    }

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
                Label(String(localized: "button_change_photo"), systemImage: "photo")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(accent)
            }
            
            if (auth.currentUser?.avatarUrl ?? user.avatarUrl) != nil {
                Button(role: .destructive) {
                    Task {
                        await removeAvatar()
                    }
                } label: {
                    Label(String(localized: "button_remove_photo"), systemImage: "trash")
                        .font(.subheadline.weight(.medium))
                }
                .disabled(isUploadingAvatar)
            }

            if isUploadingAvatar {
                ProgressView(String(localized: "status_uploading"))
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
        SectionCardView(title: String(localized: "section_account")) {
            SettingsRowView(
                systemImage: "person.crop.circle",
                title: String(localized: "label_username"),
                value: auth.currentUser?.username ?? user.username
            )

            Divider()

            SettingsRowView(
                systemImage: "envelope",
                title: String(localized: "label_email"),
                value: displayValue(auth.currentUser?.email ?? user.email)
            )

            if let role = auth.currentUser?.role ?? user.role, !role.isEmpty {
                Divider()
                SettingsRowView(
                    systemImage: "briefcase",
                    title: String(localized: "label_role"),
                    value: role
                )
            }

            if let plan = auth.currentUser?.plan ?? user.plan, !plan.isEmpty {
                Divider()
                SettingsRowView(
                    systemImage: "star",
                    title: String(localized: "label_plan"),
                    value: plan
                )
            }
        }
    }
    
    private var legalSection: some View {
        SectionCardView(
            title: String(localized: "section_legal_support")
        ) {
            VStack(spacing: 0) {

                Button {
                    openURL("https://chatforia.com/privacy")
                } label: {
                    legalRow(
                        String(localized: "legal_privacy_policy")
                    )
                }
                .buttonStyle(.plain)

                Divider()

                Button {
                    openURL("https://chatforia.com/legal/terms")
                } label: {
                    legalRow(
                        String(localized: "legal_terms_of_service")
                    )
                }
                .buttonStyle(.plain)

                Divider()

                Button {
                    openURL("https://chatforia.com/legal/sms")
                } label: {
                    legalRow(
                        String(localized: "legal_sms_policy")
                    )
                }
                .buttonStyle(.plain)

                Divider()

                Button {
                    openURL("mailto:support@chatforia.com")
                } label: {
                    legalRow(
                        String(localized: "legal_contact_support")
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var planSection: some View {
        SectionCardView(title: String(localized: "section_plan")) {
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
                            Text(String(localized: "plan_billing"))
                                .font(.body)
                                .foregroundStyle(themeManager.palette.primaryText)

                            Text(String(format: String(localized: "current_plan_format"), currentPlan.displayName))
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
                            Text(String(localized: "manage_billing"))
                                .font(.body)
                                .foregroundStyle(themeManager.palette.primaryText)

                            Text(String(localized: "available_on_current_plan"))
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
        SectionCardView(title: String(localized: "section_wireless")) {
            NavigationLink {
                WirelessHomeView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(themeManager.palette.accent)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "wireless_chatforia_mobile"))
                            .font(.body)
                            .foregroundStyle(themeManager.palette.primaryText)

                        Text(String(localized: "wireless_esim_description"))
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

            Divider()

            NavigationLink {
                PhoneNumberManagementView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "phone")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(themeManager.palette.accent)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "wireless_phone_number"))
                            .font(.body)
                            .foregroundStyle(themeManager.palette.primaryText)

                        Text(String(localized: "wireless_phone_number_description"))
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
        SectionCardView(title: String(localized: "section_profile")) {
            VStack(alignment: .leading, spacing: 14) {
                LanguageSelectionView(selectedLanguage: $vm.preferredLanguage)

                Divider()

                ThemedToggleRow(
                    title: String(localized: "setting_auto_translate_messages"),
                    isOn: $vm.autoTranslate
                )

                ThemedToggleRow(
                    title: String(localized: "setting_show_original_with_translation"),
                    isOn: $vm.showOriginalWithTranslation
                )

                ThemedToggleRow(
                    title: String(localized: "setting_enable_read_receipts"),
                    isOn: $vm.showReadReceipts
                )
                
                VStack(alignment: .leading, spacing: 6) {
                    ThemedToggleRow(
                        title: String(localized: "setting_smart_reply_suggestions"),
                        isOn: Binding(
                            get: { vm.enableSmartReplies },
                            set: { vm.setEnableSmartReplies($0) }
                        )
                    )

                    Text(String(localized: "setting_smart_reply_description"))
                        .font(.caption)
                        .foregroundStyle(themeManager.palette.secondaryText)
                }
            }
        }
    }

    private var appearanceSection: some View {
        SectionCardView(title: String(localized: "section_appearance")) {
            VStack(alignment: .leading, spacing: 14) {
                if !currentPlan.hasPremiumCustomization {
                    Text(String(localized: "appearance_free_theme_notice"))
                        .font(.footnote)
                        .foregroundStyle(themeManager.palette.secondaryText)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "label_theme"))
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

                                Text(String(localized: AppThemes.requiredPlan(for: vm.theme) == .free ? "plan_free" : "plan_premium"))
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
        SectionCardView(title: String(localized: "section_sounds")) {
            VStack(alignment: .leading, spacing: 14) {
                if !currentPlan.hasPremiumSounds {
                    Text(String(localized: "sounds_free_notice"))
                        .font(.footnote)
                        .foregroundStyle(themeManager.palette.secondaryText)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "label_message_tone"))
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

                                Text(String(localized: AppMessageTones.requiredPlan(for: vm.messageTone) == .free ? "plan_free" : "plan_premium"))
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
                    Text(String(localized: "label_ringtone"))
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

                                Text(String(localized: AppRingtones.requiredPlan(for: vm.ringtone) == .free ? "plan_free" : "plan_premium"))
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
                        Text(String(localized: "label_volume"))
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
        SectionCardView(
            title: String(localized: "section_disappearing_messages")
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ThemedToggleRow(
                    title: String(
                        localized: "setting_enable_disappearing_messages"
                    ),
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
                        Text(
                            String(
                                format: String(
                                    localized: "delete_after_seconds_format"
                                ),
                                vm.autoDeleteSeconds
                            )
                        )
                            .foregroundStyle(themeManager.palette.primaryText)
                    }
                    .tint(themeManager.palette.accent)
                }
            }
        }
    }

    private var privacySection: some View {
        SectionCardView(
            title: String(localized: "section_privacy")
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ThemedToggleRow(
                    title: String(
                        localized: "setting_allow_explicit_content"
                    ),
                    isOn: $vm.allowExplicitContent
                )

                ThemedToggleRow(
                    title: String(
                        localized: "setting_blur_messages_default"
                    ),
                    isOn: $vm.privacyBlurEnabled
                )

                ThemedToggleRow(
                    title: String(
                        localized: "setting_blur_when_unfocused"
                    ),
                    isOn: $vm.privacyBlurOnUnfocus
                )

                ThemedToggleRow(
                    title: String(
                        localized: "setting_hold_to_reveal"
                    ),
                    isOn: $vm.privacyHoldToReveal
                )

                ThemedToggleRow(
                    title: String(
                        localized: "setting_notify_on_copy"
                    ),
                    isOn: $vm.notifyOnCopy
                )
            }
        }
    }

    private var randomChatSection: some View {
        SectionCardView(title: String(localized: "section_random_chat")) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "label_your_age_range"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    Picker(
                        String(localized: "label_your_age_range"),
                        selection: Binding(
                            get: { vm.ageBand ?? "" },
                            set: { vm.ageBand = $0.isEmpty ? nil : $0 }
                        )
                    ) {
                        Text(String(localized: "select_age_range")).tag("")
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
                    title: String(localized: "setting_use_age_based_matching"),
                    isOn: $vm.wantsAgeFilter
                )
                .opacity(vm.ageBand == nil ? 0.55 : 1.0)
                .disabled(vm.ageBand == nil)

                ThemedToggleRow(
                    title: String(localized: "setting_foria_remember"),
                    isOn: $vm.foriaRemember
                )
            }
        }
    }

    private var voicemailSection: some View {
        SectionCardView(title: String(localized: "section_voicemail")) {
            VStack(alignment: .leading, spacing: 14) {
                ThemedToggleRow(
                    title: String(localized: "setting_enable_voicemail"),
                    isOn: $vm.voicemailEnabled
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "setting_auto_delete_voicemails_days"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    TextField(
                        String(localized: "placeholder_keep_voicemails_forever"),
                        text: Binding(
                            get: { vm.voicemailAutoDeleteDays.map(String.init) ?? "" },
                            set: { vm.voicemailAutoDeleteDays = Int($0) }
                        )
                    )
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "setting_forward_voicemail_email"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    TextField(
                        String(localized: "placeholder_email_address"),
                        text: $vm.voicemailForwardEmail
                    )
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "setting_text_fallback_greeting"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    TextField(
                        String(localized: "placeholder_greeting"),
                        text: $vm.voicemailGreetingText,
                        axis: .vertical
                    )
                    .lineLimit(3...5)
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var forwardingSection: some View {
        SectionCardView(
            title: String(localized: "section_forwarding")
        ) {
            if currentPlan.canUseForwarding {
                NavigationLink {
                    ForwardingSettingsView()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "forwarding_manage"))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(themeManager.palette.primaryText)

                            Text(
                                String(localized: "forwarding_description")
                            )
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
                        title: String(localized: "forwarding_requires_plus_title"),
                        message: String(localized: "forwarding_requires_plus_message"),
                        requiredPlan: .plus
                    )
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(String(localized: "forwarding_manage"))
                                Image(systemName: "lock.fill")
                            }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(themeManager.palette.primaryText)

                            Text(
                                String(localized: "forwarding_upgrade_prompt")
                            )
                                .font(.footnote)
                                .foregroundStyle(themeManager.palette.secondaryText)
                        }

                        Spacer()
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
                    title: String(localized: "button_save_settings"),
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
    
    private func loadBackupStatus(token: String) async {
        isCheckingBackup = true
        defer { isCheckingBackup = false }

        hasRemoteBackup = await RemoteKeyBackupService.shared.hasRemoteBackup(token: token)
    }
    
    private var deleteAccountSection: some View {
        VStack(spacing: 10) {

            if let deleteAccountError, !deleteAccountError.isEmpty {
                Text(deleteAccountError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button(role: .destructive) {
                showingDeleteAccountAlert = true
            } label: {
                HStack {
                    if isDeletingAccount {
                        ProgressView()
                            .tint(.red)
                    } else {
                        Image(systemName: "trash")
                        Text(String(localized: "button_delete_account"))
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .disabled(isDeletingAccount)
            .background(Color.red.opacity(0.08))
            .foregroundStyle(.red)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .alert(
            String(localized: "alert_delete_account_title"),
            isPresented: $showingDeleteAccountAlert
        ) {
            Button(
                String(localized: "button_cancel"),
                role: .cancel
            ) {}

            Button(
                String(localized: "button_delete"),
                role: .destructive
            ) {
                Task {
                    await deleteAccount()
                }
            }
        } message: {
            Text(
                String(localized: "delete_account_warning")
            )
        }
    }

    private var logoutButtonSection: some View {
        ThemedOutlineButton(
            title: String(localized: "button_log_out"),
            action: {
                auth.logout()
            }
        )
        .padding(.top, 4)
    }

    private var currentPlan: AppPlan {
        AppPlan(serverValue: auth.currentUser?.plan ?? user.plan)
    }
    
    private var encryptionStatusText: String {
        if !AccountKeyManager.shared.hasAccountKeys() {
            return String(localized: "security_status_recovery_needed")
        }

        if isCheckingBackup {
            return String(localized: "security_status_protected")
        }

        if let hasRemoteBackup {
            return hasRemoteBackup
                ? String(localized: "security_status_backup_saved")
                : String(localized: "security_status_no_backup")
        }

        return String(localized: "security_status_protected")
    }

    private var encryptionStatusColor: Color {
        if !AccountKeyManager.shared.hasAccountKeys() {
            return .red
        }
        return themeManager.palette.secondaryText
    }
    
    private var securitySection: some View {
        SectionCardView(
            title: String(localized: "section_security")
        ) {
            VStack(alignment: .leading, spacing: 8) {

                Text(
                    String(localized: "security_backup_description")
                )
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .padding(.bottom, 4)

                VStack(spacing: 0) {

                    // Encryption status
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(themeManager.palette.accent)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "security_encryption_key"))
                                .font(.body)
                                .foregroundStyle(themeManager.palette.primaryText)

                            Text(encryptionStatusText)
                                .font(.subheadline)
                                .foregroundStyle(encryptionStatusColor)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 10)

                    if AccountKeyManager.shared.hasAccountKeys(),
                       hasRemoteBackup == false,
                       !isCheckingBackup {
                        Text(
                            String(localized: "security_backup_recommended")
                        )
                            .font(.caption)
                            .foregroundStyle(themeManager.palette.secondaryText)
                            .padding(.bottom, 6)
                    }

                    Divider()

                    Button {
                        showingBackupSheet = true
                    } label: {
                        rowLabel(
                            icon: "icloud.and.arrow.up",
                            title: String(localized: "security_backup_key_title"),
                            subtitle: String(localized: "security_backup_key_subtitle")
                        )
                    }
                    .buttonStyle(.plain)

                    Divider()

                    if !AccountKeyManager.shared.hasAccountKeys() {
                        Divider()

                        Button {
                            showingRestoreSheet = true
                        } label: {
                            rowLabel(
                                icon: "icloud.and.arrow.down",
                                title: String(localized: "security_restore_key_title"),
                                subtitle: String(localized: "security_restore_key_subtitle")
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()

                    Button {
                        showingRotateSheet = true
                    } label: {
                        rowLabel(
                            icon: "arrow.triangle.2.circlepath",
                            title: String(localized: "security_rotate_key_title"),
                            subtitle: hasRemoteBackup == true
                                ? String(localized: "security_rotate_key_ready")
                                : String(localized: "security_rotate_key_backup_required")
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(hasRemoteBackup != true)
                    .opacity(hasRemoteBackup == true ? 1 : 0.5)
                }
            }
        }
    }
    
    private func rowLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(themeManager.palette.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(themeManager.palette.primaryText)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
    }

    private func presentUpgrade(title: String, message: String, requiredPlan: AppPlan) {
        lockedFeatureTitle = title
        lockedFeatureMessage = message
        lockedRequiredPlan = requiredPlan
        showingUpgradeSheet = true
    }

    private func attemptApplyTheme(_ code: String) {
        let requiredPlan = AppThemes.requiredPlan(for: code)
        let themeName = AppThemes.name(for: code)

        guard AppThemes.isAvailable(code, for: currentPlan) else {
            presentUpgrade(
                title: String(localized: "premium_theme_title"),
                message: String(
                    format: String(localized: "premium_feature_available_on_format"),
                    themeName,
                    requiredPlan.displayName
                ),
                requiredPlan: requiredPlan
            )
            return
        }

        vm.theme = code
        themeManager.apply(code: code)

        Task {
            await saveTheme(code)
        }
    }
    
    private func saveTheme(_ code: String) async {
        guard let token = auth.currentToken, !token.isEmpty else {
            auth.handleInvalidSession()
            return
        }

        do {
            let updatedUser = try await SettingsService.shared.updateTheme(code, token: token)

            auth.replaceCurrentUser(updatedUser)
            vm.load(from: updatedUser)
            themeManager.apply(code: updatedUser.theme ?? code)
        } catch {
            vm.saveError = error.localizedDescription
        }
    }
    
    private func attemptApplyMessageTone(_ code: String) {
        let requiredPlan = AppMessageTones.requiredPlan(for: code)
        let toneName = AppMessageTones.name(for: code)

        guard AppMessageTones.isAvailable(code, for: currentPlan) else {
            presentUpgrade(
                title: String(localized: "premium_message_tone_title"),
                message: String(
                    format: String(localized: "premium_feature_available_on_format"),
                    toneName,
                    requiredPlan.displayName
                ),
                requiredPlan: requiredPlan
            )
            return
        }

        vm.messageTone = code
    }

    private func attemptApplyRingtone(_ code: String) {
        let requiredPlan = AppRingtones.requiredPlan(for: code)
        let ringtoneName = AppRingtones.name(for: code)

        guard AppRingtones.isAvailable(code, for: currentPlan) else {
            presentUpgrade(
                title: String(localized: "premium_ringtone_title"),
                message: String(
                    format: String(localized: "premium_feature_available_on_format"),
                    ringtoneName,
                    requiredPlan.displayName
                ),
                requiredPlan: requiredPlan
            )
            return
        }

        vm.ringtone = code
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
            avatarUploadError =
            String(localized: "error_missing_auth_token")
            auth.handleInvalidSession()
            return
        }

        do {
            isUploadingAvatar = true

            guard let data = try await item.loadTransferable(type: Data.self) else {
                avatarUploadError =
                    String(localized: "error_could_not_read_image")
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
    
    private func removeAvatar() async {
        avatarUploadError = nil

        guard let token = auth.currentToken, !token.isEmpty else {
            avatarUploadError =
                String(localized: "error_missing_auth_token")
            auth.handleInvalidSession()
            return
        }

        do {
            isUploadingAvatar = true

            let _: AvatarRemoveResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "users/me/avatar",
                    method: .DELETE,
                    requiresAuth: true
                ),
                token: token
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
            
            appLanguage = updatedUser.uiLanguage ?? "en"
            
            let updatedPlan = AppPlan(serverValue: updatedUser.plan)
            let updatedTheme = updatedUser.theme ?? "dawn"
            let themeToApply = AppThemes.isAvailable(updatedTheme, for: updatedPlan) ? updatedTheme : "dawn"
            themeManager.apply(code: themeToApply)

            vm.saveSuccessMessage =
                String(localized: "settings_saved")
        } catch {
            vm.saveError = error.localizedDescription
        }

        vm.isSaving = false
    }
    
    private func legalRow(_ title: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(themeManager.palette.primaryText)

            Spacer()

            Image(systemName: "arrow.up.right.square")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
    }
    
    private func deleteAccount() async {
        guard let token = auth.currentToken, !token.isEmpty else {
            auth.handleInvalidSession()
            return
        }

        do {
            isDeletingAccount = true
            deleteAccountError = nil

            try await SettingsService.shared.deleteAccount(token: token)

            TokenStore.shared.clear()

            await MainActor.run {
                auth.logout()
            }

        } catch {
            deleteAccountError = error.localizedDescription
        }

        isDeletingAccount = false
    }
    
    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }
    
    struct InviteAttributionBannerView: View {
            let text: String

            var body: some View {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                    Text(text)
                        .font(.subheadline)
                    Spacer()
                }
                .padding(12)
                .background(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.15), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
    }

}
