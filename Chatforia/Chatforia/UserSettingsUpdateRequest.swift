import Foundation

struct UserSettingsUpdateRequest: Encodable {
    let preferredLanguage: String?
    let autoTranslate: Bool
    let showOriginalWithTranslation: Bool
    let theme: String?
    let allowExplicitContent: Bool
    let showReadReceipts: Bool
    let autoDeleteSeconds: Int

    let privacyBlurEnabled: Bool
    let privacyBlurOnUnfocus: Bool
    let privacyHoldToReveal: Bool
    let notifyOnCopy: Bool

    let ageBand: String?
    let wantsAgeFilter: Bool
    let randomChatAllowedBands: [String]
    let foriaRemember: Bool

    let voicemailEnabled: Bool
    let voicemailAutoDeleteDays: Int?
    let voicemailForwardEmail: String
    let voicemailGreetingText: String
    
    let messageTone: String?
    let ringtone: String?
    let soundVolume: Int?
}
