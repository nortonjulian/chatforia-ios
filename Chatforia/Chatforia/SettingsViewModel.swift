import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var preferredLanguage: String = "en"
    @Published var autoTranslate: Bool = false
    @Published var showOriginalWithTranslation: Bool = false
    @Published var theme: String = "midnight"
    @Published var allowExplicitContent: Bool = false
    @Published var showReadReceipts: Bool = false
    @Published var autoDeleteSeconds: Int = 0

    @Published var privacyBlurEnabled: Bool = false
    @Published var privacyBlurOnUnfocus: Bool = false
    @Published var privacyHoldToReveal: Bool = false
    @Published var notifyOnCopy: Bool = false

    @Published var ageBand: String? = nil
    @Published var wantsAgeFilter: Bool = true
    @Published var randomChatAllowedBands: [String] = []
    @Published var foriaRemember: Bool = true

    @Published var voicemailEnabled: Bool = true
    @Published var voicemailAutoDeleteDays: Int? = nil
    @Published var voicemailForwardEmail: String = ""
    @Published var voicemailGreetingText: String = ""

    @Published var isSaving = false
    @Published var saveError: String?
    @Published var saveSuccessMessage: String?
    
    @Published var messageTone: String = "default"
    @Published var ringtone: String = "classic"
    @Published var soundVolume: Int = 70

    func load(from user: UserDTO) {
        preferredLanguage = user.preferredLanguage ?? "en"
        autoTranslate = user.autoTranslate ?? false
        showOriginalWithTranslation = user.showOriginalWithTranslation ?? false
        theme = user.theme ?? "midnight"
        allowExplicitContent = user.allowExplicitContent ?? false
        showReadReceipts = user.showReadReceipts ?? false
        autoDeleteSeconds = user.autoDeleteSeconds ?? 0

        privacyBlurEnabled = user.privacyBlurEnabled ?? false
        privacyBlurOnUnfocus = user.privacyBlurOnUnfocus ?? false
        privacyHoldToReveal = user.privacyHoldToReveal ?? false
        notifyOnCopy = user.notifyOnCopy ?? false

        ageBand = user.ageBand
        wantsAgeFilter = user.wantsAgeFilter ?? true
        randomChatAllowedBands = user.randomChatAllowedBands ?? []
        foriaRemember = user.foriaRemember ?? true

        voicemailEnabled = user.voicemailEnabled ?? true
        voicemailAutoDeleteDays = user.voicemailAutoDeleteDays
        voicemailForwardEmail = user.voicemailForwardEmail ?? (user.email ?? "")
        voicemailGreetingText = user.voicemailGreetingText ?? ""

        messageTone = user.messageTone ?? "default"
        ringtone = user.ringtone ?? "classic"
        soundVolume = user.soundVolume ?? 70
    }
    func makeRequest() -> UserSettingsUpdateRequest {
        UserSettingsUpdateRequest(
            preferredLanguage: preferredLanguage,
            autoTranslate: autoTranslate,
            showOriginalWithTranslation: showOriginalWithTranslation,
            theme: theme,
            allowExplicitContent: allowExplicitContent,
            showReadReceipts: showReadReceipts,
            autoDeleteSeconds: autoDeleteSeconds,
            privacyBlurEnabled: privacyBlurEnabled,
            privacyBlurOnUnfocus: privacyBlurOnUnfocus,
            privacyHoldToReveal: privacyHoldToReveal,
            notifyOnCopy: notifyOnCopy,
            ageBand: ageBand,
            wantsAgeFilter: wantsAgeFilter,
            randomChatAllowedBands: randomChatAllowedBands,
            foriaRemember: foriaRemember,
            voicemailEnabled: voicemailEnabled,
            voicemailAutoDeleteDays: voicemailAutoDeleteDays,
            voicemailForwardEmail: voicemailForwardEmail,
            voicemailGreetingText: voicemailGreetingText,
            messageTone: messageTone,
            ringtone: ringtone,
            soundVolume: soundVolume
        )
    }
}
