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

                            Button(
                                appText(
                                    "button_message_inviter",
                                    languageCode: appLanguage
                                )
                            ) {
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
                                    Text(
                                        appText(
                                            "button_upgrade",
                                            languageCode: appLanguage
                                        )
                                    )
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(themeManager.palette.primaryText)

                                    Text(
                                        appText(
                                            "upgrade_choose_plus_or_premium",
                                            languageCode: appLanguage
                                        )
                                    )
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
                    accessibilitySection
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
            .navigationTitle(
                appText("screen_profile", languageCode: appLanguage)
            )
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
                    title: appText("sheet_theme_title", languageCode: appLanguage),
                    subtitle: appText("sheet_theme_subtitle", languageCode: appLanguage),
                    selectedCode: vm.theme,
                    currentPlan: currentPlan,
                    options: AppThemes.all.map {
                        PremiumSelectableOption(
                            id: $0.code,
                            code: $0.code,
                            name: $0.localizedName(languageCode: appLanguage),
                            requiredPlan: $0.requiredPlan
                        )
                    },
                    onSelect: { code in
                        attemptApplyTheme(code)
                    },
                    onLockedTap: { option in
                        presentUpgrade(
                            title: appText(
                                "premium_theme_title",
                                languageCode: appLanguage
                            ),
                            message: String(
                                format: appText(
                                    "premium_feature_available_on_format",
                                    languageCode: appLanguage
                                ),
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
                    title: appText("sheet_message_tone_title", languageCode: appLanguage),
                    subtitle: appText("sheet_message_tone_title", languageCode: appLanguage),
                    selectedCode: vm.messageTone,
                    currentPlan: currentPlan,
                    options: AppMessageTones.all.map {
                        PremiumSelectableOption(
                            id: $0.code,
                            code: $0.code,
                            name: $0.localizedName(languageCode: appLanguage),
                            requiredPlan: $0.requiredPlan
                        )
                    },
                    onSelect: { code in
                        attemptApplyMessageTone(code)
                    },
                    onLockedTap: { option in
                        presentUpgrade(
                            title: appText(
                                "premium_message_tone_title",
                                languageCode: appLanguage
                            ),
                            message: String(
                                format: appText(
                                    "premium_feature_available_on_format",
                                    languageCode: appLanguage
                                ),
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
                    title: appText("sheet_ringtone_title", languageCode: appLanguage),
                    subtitle: appText("sheet_ringtone_subtitle", languageCode: appLanguage),
                    selectedCode: vm.ringtone,
                    currentPlan: currentPlan,
                    options: AppRingtones.all.map {
                        PremiumSelectableOption(
                            id: $0.code,
                            code: $0.code,
                            name: $0.localizedName(languageCode: appLanguage),
                            requiredPlan: $0.requiredPlan
                        )
                    },
                    onSelect: { code in
                        attemptApplyRingtone(code)
                    },
                    onLockedTap: { option in
                        presentUpgrade(
                            title: appText(
                                "premium_ringtone_title",
                                languageCode: appLanguage
                            ),
                            message: String(
                                format: appText(
                                    "premium_feature_available_on_format",
                                    languageCode: appLanguage
                                ),
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
                Label(
                    appText(
                        "button_change_photo",
                        languageCode: appLanguage
                    ),
                    systemImage: "photo"
                )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(accent)
            }
            
            if (auth.currentUser?.avatarUrl ?? user.avatarUrl) != nil {
                Button(role: .destructive) {
                    Task {
                        await removeAvatar()
                    }
                } label: {
                    Label(
                        appText(
                            "button_remove_photo",
                            languageCode: appLanguage
                        ),
                        systemImage: "trash"
                    )
                        .font(.subheadline.weight(.medium))
                }
                .disabled(isUploadingAvatar)
            }

            if isUploadingAvatar {
                ProgressView(
                    appText(
                        "status_uploading",
                        languageCode: appLanguage
                    )
                )
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
        SectionCardView(
            title: appText("section_account", languageCode: appLanguage)
        ) {
            SettingsRowView(
                systemImage: "person.crop.circle",
                title: appText("label_username", languageCode: appLanguage),
                value: auth.currentUser?.username ?? user.username
            )

            Divider()

            SettingsRowView(
                systemImage: "envelope",
                title: appText("label_email", languageCode: appLanguage),
                value: displayValue(auth.currentUser?.email ?? user.email)
            )

            if let role = auth.currentUser?.role ?? user.role, !role.isEmpty {
                Divider()
                SettingsRowView(
                    systemImage: "briefcase",
                    title: appText("label_role", languageCode: appLanguage),
                    value: appText("role_\(role.lowercased())", languageCode: appLanguage)
                )
            }

            if let plan = auth.currentUser?.plan ?? user.plan, !plan.isEmpty {
                Divider()
                SettingsRowView(
                    systemImage: "star",
                    title: appText("label_plan", languageCode: appLanguage),
                    value: AppPlan(serverValue: plan).displayName.uppercased()
                )
            }
        }
    }
    
    private var legalSection: some View {
        SectionCardView(
            title: appText(
                "section_legal_support",
                languageCode: appLanguage
            )
        ) {
            VStack(spacing: 0) {

                Button {
                    openURL("https://chatforia.com/privacy")
                } label: {
                    legalRow(
                        appText(
                            "legal_privacy_policy",
                            languageCode: appLanguage
                        )
                    )
                }
                .buttonStyle(.plain)

                Divider()

                Button {
                    openURL("https://chatforia.com/legal/terms")
                } label: {
                    legalRow(
                        appText(
                            "legal_terms_of_service",
                            languageCode: appLanguage
                        )
                    )
                }
                .buttonStyle(.plain)

                Divider()

                Button {
                    openURL("https://chatforia.com/legal/sms")
                } label: {
                    legalRow(
                        appText(
                            "legal_sms_policy",
                            languageCode: appLanguage
                        )
                    )
                }
                .buttonStyle(.plain)

                Divider()

                Button {
                    openURL("mailto:support@chatforia.com")
                } label: {
                    legalRow(
                        appText(
                            "legal_contact_support",
                            languageCode: appLanguage
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var planSection: some View {
        SectionCardView(title: appText("section_plan", languageCode: appLanguage)) {
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
                            Text(appText("plan_billing", languageCode: appLanguage))
                                .font(.body)
                                .foregroundStyle(themeManager.palette.primaryText)

                            Text(
                                appText("current_plan_format", languageCode: appLanguage)
                                    .replacingOccurrences(of: "{plan}", with: currentPlanDisplayName)
                            )
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
                            Text(appText("manage_billing", languageCode: appLanguage))
                                .font(.body)
                                .foregroundStyle(themeManager.palette.primaryText)

                            Text(appText("available_on_current_plan", languageCode: appLanguage))
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
        SectionCardView(title: appText("section_wireless", languageCode: appLanguage)) {
            NavigationLink {
                WirelessHomeView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(themeManager.palette.accent)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(appText("wireless_chatforia_mobile", languageCode: appLanguage))
                            .font(.body)
                            .foregroundStyle(themeManager.palette.primaryText)

                        Text(appText("wireless_esim_description", languageCode: appLanguage))
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
                        Text(appText("wireless_phone_number", languageCode: appLanguage))
                            .font(.body)
                            .foregroundStyle(themeManager.palette.primaryText)

                        Text(appText("wireless_phone_number_description", languageCode: appLanguage))
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
        SectionCardView(
            title: appText(
                "section_profile",
                languageCode: appLanguage
            )
        ) {
            VStack(alignment: .leading, spacing: 14) {
                LanguageSelectionView(selectedLanguage: $vm.preferredLanguage)

                Divider()

                ThemedToggleRow(
                    title: appText("setting_auto_translate_messages", languageCode: appLanguage),
                    isOn: $vm.autoTranslate
                )

                ThemedToggleRow(
                    title: appText("setting_show_original_with_translation", languageCode: appLanguage),
                    isOn: $vm.showOriginalWithTranslation
                )

                ThemedToggleRow(
                    title: appText("setting_enable_read_receipts", languageCode: appLanguage),
                    isOn: $vm.showReadReceipts
                )
                
                VStack(alignment: .leading, spacing: 6) {
                    ThemedToggleRow(
                        title: appText("setting_smart_reply_suggestions", languageCode: appLanguage),
                        isOn: Binding(
                            get: { vm.enableSmartReplies },
                            set: { vm.setEnableSmartReplies($0) }
                        )
                    )

                    Text(appText("setting_smart_reply_description", languageCode: appLanguage))
                        .font(.caption)
                        .foregroundStyle(themeManager.palette.secondaryText)
                }
            }
        }
    }

    private var appearanceSection: some View {
        SectionCardView(title: appText("section_appearance", languageCode: appLanguage)) {
            VStack(alignment: .leading, spacing: 14) {
                if !currentPlan.hasPremiumCustomization {
                    Text(appText("appearance_free_theme_notice", languageCode: appLanguage))
                        .font(.footnote)
                        .foregroundStyle(themeManager.palette.secondaryText)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(appText("label_theme", languageCode: appLanguage))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    Button {
                        showingThemeSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(AppThemes.name(for: vm.theme, languageCode: appLanguage))
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(themeManager.palette.primaryText)

                                Text(
                                    appText(
                                        AppThemes.requiredPlan(for: vm.theme) == .free ? "plan_free" : "plan_premium",
                                        languageCode: appLanguage
                                    )
                                )
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
    
    private var accessibilitySection: some View {
        SectionCardView(title: appText("accessibility_title", languageCode: appLanguage)) {
            NavigationLink {
                AccessibilitySettingsView(vm: vm)
                    .environmentObject(auth)
                    .environmentObject(themeManager)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "accessibility")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(themeManager.palette.accent)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(appText("accessibility_title", languageCode: appLanguage))
                            .font(.body)
                            .foregroundStyle(themeManager.palette.primaryText)

                        Text(appText("accessibility_description", languageCode: appLanguage))
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

    private var soundsSection: some View {
        SectionCardView(title: appText("section_sounds", languageCode: appLanguage)) {
            VStack(alignment: .leading, spacing: 14) {
                if !currentPlan.hasPremiumSounds {
                    Text(appText("sounds_free_notice", languageCode: appLanguage))
                        .font(.footnote)
                        .foregroundStyle(themeManager.palette.secondaryText)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(appText("label_message_tone", languageCode: appLanguage))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    Button {
                        showingMessageToneSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(AppMessageTones.name(for: vm.messageTone, languageCode: appLanguage))
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(themeManager.palette.primaryText)

                                Text(
                                    appText(
                                        AppMessageTones.requiredPlan(for: vm.messageTone) == .free ? "plan_free" : "plan_premium",
                                        languageCode: appLanguage
                                    )
                                )
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
                    Text(appText("label_ringtone", languageCode: appLanguage))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    Button {
                        showingRingtoneSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(AppRingtones.name(for: vm.ringtone, languageCode: appLanguage))
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(themeManager.palette.primaryText)

                                Text(
                                    appText(
                                        AppRingtones.requiredPlan(for: vm.ringtone) == .free ? "plan_free" : "plan_premium",
                                        languageCode: appLanguage
                                    )
                                )
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
                        Text(appText("label_volume", languageCode: appLanguage))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(themeManager.palette.primaryText)

                        Spacer()

                        Text("\(vm.soundVolume)%")
                            .foregroundStyle(themeManager.palette.secondaryText)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(vm.soundVolume) },
                            set: {
                                vm.soundVolume = Int($0.rounded())

                                AudioPlayerService.shared.save(
                                    messageTone: vm.messageTone,
                                    ringtone: vm.ringtone,
                                    soundVolume: vm.soundVolume
                                )
                            }
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
            title: appText(
                "section_disappearing_messages",
                languageCode: appLanguage
            )
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ThemedToggleRow(
                    title: appText(
                        "setting_enable_disappearing_messages",
                        languageCode: appLanguage
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
                                format: appText(
                                    "delete_after_seconds_format",
                                    languageCode: appLanguage
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
            title: appText(
                "section_privacy",
                languageCode: appLanguage
            )
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ThemedToggleRow(
                    title: appText(
                        "setting_allow_explicit_content",
                        languageCode: appLanguage
                    ),
                    isOn: $vm.allowExplicitContent
                )

                ThemedToggleRow(
                    title: appText(
                        "setting_blur_messages_default",
                        languageCode: appLanguage
                    ),
                    isOn: $vm.privacyBlurEnabled
                )

                ThemedToggleRow(
                    title: appText(
                        "setting_blur_when_unfocused",
                        languageCode: appLanguage
                    ),
                    isOn: $vm.privacyBlurOnUnfocus
                )

                ThemedToggleRow(
                    title: appText(
                        "setting_hold_to_reveal",
                        languageCode: appLanguage
                    ),
                    isOn: $vm.privacyHoldToReveal
                )

                ThemedToggleRow(
                    title: appText(
                        "setting_notify_on_copy",
                        languageCode: appLanguage
                    ),
                    isOn: $vm.notifyOnCopy
                )
            }
        }
    }

    private var randomChatSection: some View {
        SectionCardView(title: appText(
            "section_random_chat",
            languageCode: appLanguage
        )) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appText(
                        "label_your_age_range",
                        languageCode: appLanguage
                    ))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    Picker(
                        appText(
                                "label_your_age_range",
                                languageCode: appLanguage
                            ),
                        selection: Binding(
                            get: { vm.ageBand ?? "" },
                            set: { vm.ageBand = $0.isEmpty ? nil : $0 }
                        )
                    ) {
                        Text(appText(
                            "select_age_range",
                            languageCode: appLanguage
                        )).tag("")
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
                    title: appText(
                        "setting_use_age_based_matching",
                        languageCode: appLanguage
                    ),
                    isOn: $vm.wantsAgeFilter
                )
                .opacity(vm.ageBand == nil ? 0.55 : 1.0)
                .disabled(vm.ageBand == nil)

                ThemedToggleRow(
                    title: appText(
                        "setting_foria_remember",
                        languageCode: appLanguage
                    ),
                    isOn: $vm.foriaRemember
                )
            }
        }
    }

    private var voicemailSection: some View {
        SectionCardView(title: appText(
            "section_voicemail",
            languageCode: appLanguage
        )) {
            VStack(alignment: .leading, spacing: 14) {
                ThemedToggleRow(
                    title: appText(
                        "setting_forward_voicemail_email",
                        languageCode: appLanguage
                    ),
                    isOn: $vm.voicemailEnabled
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(appText(
                        "setting_auto_delete_voicemails_days",
                        languageCode: appLanguage
                    ))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    TextField(
                        appText(
                            "placeholder_keep_voicemails_forever",
                            languageCode: appLanguage
                        ),
                        text: Binding(
                            get: { vm.voicemailAutoDeleteDays.map(String.init) ?? "" },
                            set: { vm.voicemailAutoDeleteDays = Int($0) }
                        )
                    )
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(appText("setting_forward_voicemail_email", languageCode: appLanguage))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    TextField(
                        appText(
                            "placeholder_email_address",
                            languageCode: appLanguage
                        ),
                        text: $vm.voicemailForwardEmail
                    )
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(appText(
                        "setting_text_fallback_greeting",
                        languageCode: appLanguage
                    ))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    TextField(
                        appText(
                            "placeholder_greeting",
                            languageCode: appLanguage
                        ),
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
            title: appText(
                "section_forwarding",
                languageCode: appLanguage
            )
        ) {
            if currentPlan.canUseForwarding {
                NavigationLink {
                    ForwardingSettingsView()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appText(
                                "forwarding_manage",
                                languageCode: appLanguage
                            ))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(themeManager.palette.primaryText)

                            Text(
                                appText(
                                    "forwarding_description",
                                    languageCode: appLanguage
                                )
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
                        title: appText(
                            "forwarding_requires_plus_title",
                            languageCode: appLanguage
                        ),
                        message: appText(
                            "forwarding_requires_plus_message",
                            languageCode: appLanguage
                        ),
                        requiredPlan: .plus
                    )
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(
                                    appText(
                                        "forwarding_manage",
                                        languageCode: appLanguage
                                    )
                                )
                                Image(systemName: "lock.fill")
                            }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(themeManager.palette.primaryText)

                            Text(
                                appText(
                                    "forwarding_upgrade_prompt",
                                    languageCode: appLanguage
                                )
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
                    title: appText(
                            "button_save_settings",
                            languageCode: appLanguage
                        ),
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
                        Text(
                            appText(
                                "button_delete_account",
                                languageCode: appLanguage
                            )
                        )
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
            appText(
                    "alert_delete_account_title",
                    languageCode: appLanguage
                ),
            isPresented: $showingDeleteAccountAlert
        ) {
            Button(
                appText(
                    "button_cancel",
                    languageCode: appLanguage
                ),
                role: .cancel
            ) {}

            Button(
                appText(
                    "button_delete",
                    languageCode: appLanguage
                ),
                role: .destructive
            ) {
                Task {
                    await deleteAccount()
                }
            }
        } message: {
            Text(
                appText(
                    "delete_account_warning",
                    languageCode: appLanguage
                )
            )
        }
    }

    private var logoutButtonSection: some View {
        ThemedOutlineButton(
            title: appText(
                    "button_log_out",
                    languageCode: appLanguage
                ),
            action: {
                auth.logout()
            }
        )
        .padding(.top, 4)
    }

    private var currentPlan: AppPlan {
        AppPlan(serverValue: auth.currentUser?.plan ?? user.plan)
    }

    private var currentPlanDisplayName: String {
        switch currentPlan {
        case .free:
            return appText("plan_free", languageCode: appLanguage)
        case .plus:
            return appText("plan_plus", languageCode: appLanguage)
        case .premium:
            return appText("plan_premium", languageCode: appLanguage)
        }
    }
    
    private var currentUserId: Int {
        auth.currentUser?.id ?? user.id
    }
    
    private var encryptionStatusText: String {
        if !AccountKeyManager.shared.hasAccountKeys(userId: currentUserId) {
            return appText("security_status_recovery_needed", languageCode: appLanguage)
        }

        if isCheckingBackup {
            return appText("security_status_protected", languageCode: appLanguage)
        }

        if let hasRemoteBackup {
            return hasRemoteBackup
                ? appText("security_status_backup_saved", languageCode: appLanguage)
                : appText("security_status_no_backup", languageCode: appLanguage)
        }

        return appText(
            "security_status_protected",
            languageCode: appLanguage
        )
    }

    private var encryptionStatusColor: Color {
        if !AccountKeyManager.shared.hasAccountKeys(userId: currentUserId) {
            return .red
        }
        return themeManager.palette.secondaryText
    }
    
    private var securitySection: some View {
        SectionCardView(
            title: appText(
                "section_security",
                languageCode: appLanguage
            )
        ) {
            VStack(alignment: .leading, spacing: 8) {

                Text(
                    appText(
                        "security_backup_description",
                        languageCode: appLanguage
                    )
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
                            Text(
                                appText(
                                    "security_encryption_key",
                                    languageCode: appLanguage
                                )
                            )
                                .font(.body)
                                .foregroundStyle(themeManager.palette.primaryText)

                            Text(encryptionStatusText)
                                .font(.subheadline)
                                .foregroundStyle(encryptionStatusColor)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 10)

                    if AccountKeyManager.shared.hasAccountKeys(userId: currentUserId),
                       hasRemoteBackup == false,
                       !isCheckingBackup {
                        Text(
                            appText(
                                "security_backup_recommended",
                                languageCode: appLanguage
                            )
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
                            title: appText(
                                "security_backup_key_title",
                                languageCode: appLanguage
                            ),
                            subtitle: appText(
                                "security_backup_key_subtitle",
                                languageCode: appLanguage
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    Divider()
                    
                    NavigationLink {
                        LinkedDevicesView()
                            .environmentObject(auth)
                            .environmentObject(themeManager)
                    } label: {
                        rowLabel(
                            icon: "iphone.gen3.radiowaves.left.and.right",
                            title: "Linked Devices",
                            subtitle: "Manage trusted devices and approvals"
                        )
                    }
                    .buttonStyle(.plain)

                    Divider()

                    if !AccountKeyManager.shared.hasAccountKeys(userId: currentUserId) {
                        Divider()

                        Button {
                            showingRestoreSheet = true
                        } label: {
                            rowLabel(
                                icon: "icloud.and.arrow.down",
                                title: appText(
                                    "security_restore_key_title",
                                    languageCode: appLanguage
                                ),
                                subtitle: appText(
                                    "security_restore_key_subtitle",
                                    languageCode: appLanguage
                                )
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
                            title: appText(
                                "security_rotate_key_title",
                                languageCode: appLanguage
                            ),
                            subtitle: hasRemoteBackup == true
                                ? appText(
                                    "security_rotate_key_ready",
                                    languageCode: appLanguage
                                )
                                : appText(
                                    "security_rotate_key_backup_required",
                                    languageCode: appLanguage
                                )
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
        let themeName = AppThemes.name(for: code, languageCode: appLanguage)

        guard AppThemes.isAvailable(code, for: currentPlan) else {
            presentUpgrade(
                title: appText("premium_theme_title", languageCode: appLanguage),
                message: String(
                    format: appText(
                        "premium_feature_available_on_format",
                        languageCode: appLanguage
                    ),
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
        let toneName = AppMessageTones.name(for: code, languageCode: appLanguage)

        guard AppMessageTones.isAvailable(code, for: currentPlan) else {
            presentUpgrade(
                title: appText("premium_message_tone_title", languageCode: appLanguage),
                message: String(
                    format: appText(
                        "premium_feature_available_on_format",
                        languageCode: appLanguage
                    ),
                    toneName,
                    requiredPlan.displayName
                ),
                requiredPlan: requiredPlan
            )
            return
        }

        vm.messageTone = code

        AudioPlayerService.shared.save(
            messageTone: vm.messageTone,
            ringtone: vm.ringtone,
            soundVolume: vm.soundVolume
        )

        AudioPlayerService.shared.previewMessageTone(
            filename: code,
            volume: vm.soundVolume
        )
    }

    private func attemptApplyRingtone(_ code: String) {
        let requiredPlan = AppRingtones.requiredPlan(for: code)
        let ringtoneName = AppRingtones.name(for: code, languageCode: appLanguage)

        guard AppRingtones.isAvailable(code, for: currentPlan) else {
            presentUpgrade(
                title: appText("premium_ringtone_title", languageCode: appLanguage),
                message: String(
                    format: appText(
                        "premium_feature_available_on_format",
                        languageCode: appLanguage
                    ),
                    ringtoneName,
                    requiredPlan.displayName
                ),
                requiredPlan: requiredPlan
            )
            return
        }

        vm.ringtone = code

        AudioPlayerService.shared.save(
            messageTone: vm.messageTone,
            ringtone: vm.ringtone,
            soundVolume: vm.soundVolume
        )

        AudioPlayerService.shared.previewRingtone(
            filename: code,
            volume: vm.soundVolume
        )
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
            appText("error_missing_auth_token", languageCode: appLanguage)
            auth.handleInvalidSession()
            return
        }

        do {
            isUploadingAvatar = true

            guard let data = try await item.loadTransferable(type: Data.self) else {
                avatarUploadError =
                appText("error_could_not_read_image", languageCode: appLanguage)
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
            appText(
                "error_missing_auth_token",
                languageCode: appLanguage
            )
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
                appText("settings_saved", languageCode: appLanguage)
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
