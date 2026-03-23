import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var preferredLanguage: String = "en"
    @Published var autoTranslate: Bool = false
    @Published var showOriginalWithTranslation: Bool = false
    @Published var theme: String = "dawn"
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

    @Published var messageTone: String = "Default.mp3"
    @Published var ringtone: String = "Classic.mp3"
    @Published var soundVolume: Int = 70

    @Published var enableSmartReplies: Bool = true
    @Published var maskAIProfanity: Bool = false

    private let maskAIProfanityKey = "chatforia.maskAIProfanity"

    func load(from user: UserDTO) {
        preferredLanguage = user.preferredLanguage ?? "en"
        autoTranslate = user.autoTranslate ?? false
        showOriginalWithTranslation = user.showOriginalWithTranslation ?? false
        theme = user.theme ?? "dawn"
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

        messageTone = normalizedMessageTone(user.messageTone)
        ringtone = normalizedRingtone(user.ringtone)
        soundVolume = user.soundVolume ?? 70

        enableSmartReplies = user.enableSmartReplies ?? true
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
            enableSmartReplies: enableSmartReplies,
            maskAIProfanity: maskAIProfanity
        )
    }

    private func normalizedMessageTone(_ value: String?) -> String {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "default", "default.mp3":
            return "Default.mp3"
        case "vibrate", "vibrate.mp3":
            return "Vibrate.mp3"
        case "dreamer", "dreamer.mp3":
            return "Dreamer.mp3"
        case "happy_message", "happy_message.mp3", "happy message.mp3":
            return "Happy Message.mp3"
        case "notify", "notify.mp3":
            return "Notify.mp3"
        case "pop", "pop.mp3":
            return "Pop.mp3"
        case "pulsating_sound", "pulsating_sound.mp3", "pulsating sound.mp3":
            return "Pulsating Sound.mp3"
        case "text_message", "text_message.mp3", "text message.mp3":
            return "Text Message.mp3"
        case "xylophone", "xylophone.mp3":
            return "Xylophone.mp3"
        case .none:
            return "Default.mp3"
        default:
            return "Default.mp3"
        }
    }

    private func normalizedRingtone(_ value: String?) -> String {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "classic", "classic.mp3":
            return "Classic.mp3"
        case "urgency", "urgency.mp3":
            return "Urgency.mp3"
        case "bells", "bells.mp3":
            return "Bells.mp3"
        case "chimes", "chimes.mp3":
            return "Chimes.mp3"
        case "digital_phone", "digital_phone.mp3", "digital phone.mp3":
            return "Digital Phone.mp3"
        case "melodic", "melodic.mp3":
            return "Melodic.mp3"
        case "organ_notes", "organ_notes.mp3", "organ notes.mp3":
            return "Organ Notes.mp3"
        case "sound_reality", "sound_reality.mp3", "sound reality.mp3":
            return "Sound Reality.mp3"
        case "street", "street.mp3":
            return "Street.mp3"
        case "universfield", "universfield.mp3":
            return "Universfield.mp3"
        case .none:
            return "Classic.mp3"
        default:
            return "Classic.mp3"
        }
    }

    func loadLocalAISettings() {
        maskAIProfanity = UserDefaults.standard.bool(forKey: maskAIProfanityKey)
    }

    func setMaskAIProfanity(_ value: Bool) {
        maskAIProfanity = value
        UserDefaults.standard.set(value, forKey: maskAIProfanityKey)
    }
}
