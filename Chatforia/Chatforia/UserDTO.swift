import Foundation

struct UserDTO: Codable, Identifiable {
    let id: Int
    let email: String?
    let username: String
    let publicKey: String?
    let plan: String?
    let role: String?
    let preferredLanguage: String?
    let theme: String?
    let avatarUrl: String?

    let autoTranslate: Bool?
    let showOriginalWithTranslation: Bool?
    let allowExplicitContent: Bool?
    let showReadReceipts: Bool?
    let autoDeleteSeconds: Int?

    let privacyBlurEnabled: Bool?
    let privacyBlurOnUnfocus: Bool?
    let privacyHoldToReveal: Bool?
    let notifyOnCopy: Bool?

    let ageBand: String?
    let wantsAgeFilter: Bool?
    let randomChatAllowedBands: [String]?
    let foriaRemember: Bool?

    let voicemailEnabled: Bool?
    let voicemailAutoDeleteDays: Int?
    let voicemailForwardEmail: String?
    let voicemailGreetingText: String?
    let voicemailGreetingUrl: String?

    let messageTone: String?
    let ringtone: String?
    let soundVolume: Int?

    let enableSmartReplies: Bool?

    init(
        id: Int,
        email: String?,
        username: String,
        publicKey: String?,
        plan: String?,
        role: String?,
        preferredLanguage: String?,
        theme: String?,
        avatarUrl: String?,
        autoTranslate: Bool? = nil,
        showOriginalWithTranslation: Bool? = nil,
        allowExplicitContent: Bool? = nil,
        showReadReceipts: Bool? = nil,
        autoDeleteSeconds: Int? = nil,
        privacyBlurEnabled: Bool? = nil,
        privacyBlurOnUnfocus: Bool? = nil,
        privacyHoldToReveal: Bool? = nil,
        notifyOnCopy: Bool? = nil,
        ageBand: String? = nil,
        wantsAgeFilter: Bool? = nil,
        randomChatAllowedBands: [String]? = nil,
        foriaRemember: Bool? = nil,
        voicemailEnabled: Bool? = nil,
        voicemailAutoDeleteDays: Int? = nil,
        voicemailForwardEmail: String? = nil,
        voicemailGreetingText: String? = nil,
        voicemailGreetingUrl: String? = nil,
        messageTone: String? = nil,
        ringtone: String? = nil,
        soundVolume: Int? = nil,
        enableSmartReplies: Bool? = nil
    ) {
        self.id = id
        self.email = email
        self.username = username
        self.publicKey = publicKey
        self.plan = plan
        self.role = role
        self.preferredLanguage = preferredLanguage
        self.theme = theme
        self.avatarUrl = avatarUrl

        self.autoTranslate = autoTranslate
        self.showOriginalWithTranslation = showOriginalWithTranslation
        self.allowExplicitContent = allowExplicitContent
        self.showReadReceipts = showReadReceipts
        self.autoDeleteSeconds = autoDeleteSeconds

        self.privacyBlurEnabled = privacyBlurEnabled
        self.privacyBlurOnUnfocus = privacyBlurOnUnfocus
        self.privacyHoldToReveal = privacyHoldToReveal
        self.notifyOnCopy = notifyOnCopy

        self.ageBand = ageBand
        self.wantsAgeFilter = wantsAgeFilter
        self.randomChatAllowedBands = randomChatAllowedBands
        self.foriaRemember = foriaRemember

        self.voicemailEnabled = voicemailEnabled
        self.voicemailAutoDeleteDays = voicemailAutoDeleteDays
        self.voicemailForwardEmail = voicemailForwardEmail
        self.voicemailGreetingText = voicemailGreetingText
        self.voicemailGreetingUrl = voicemailGreetingUrl

        self.messageTone = messageTone
        self.ringtone = ringtone
        self.soundVolume = soundVolume

        self.enableSmartReplies = enableSmartReplies
    }
}
