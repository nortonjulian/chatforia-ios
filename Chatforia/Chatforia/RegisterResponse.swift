import Foundation

struct RegistrationResponseDTO: Decodable {
    let message: String?
    let token: String?
    let user: UserDTO?
    let privateKey: String?

    // Optional fallback fields if backend ever returns top-level user-ish data
    let id: Int?
    let username: String?
    let email: String?
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

    var resolvedUser: UserDTO? {
        if let user { return user }

        if let id, let username {
            return UserDTO(
                id: id,
                email: email,
                username: username,
                publicKey: publicKey,
                plan: plan,
                role: role,
                preferredLanguage: preferredLanguage,
                theme: theme,
                avatarUrl: avatarUrl,
                autoTranslate: autoTranslate,
                showOriginalWithTranslation: showOriginalWithTranslation,
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
                voicemailGreetingUrl: voicemailGreetingUrl
            )
        }

        return nil
    }
}
