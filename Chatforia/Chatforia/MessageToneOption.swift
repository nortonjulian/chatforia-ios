import Foundation

struct MessageToneOption: Identifiable, Hashable {
    let code: String
    let name: String
    let tier: OptionTier

    var id: String { code }

    var isPremium: Bool {
        tier == .premium
    }
}

enum AppMessageTones {
    static let all: [MessageToneOption] = [
        .init(code: "default", name: "Default", tier: .free),
        .init(code: "vibrate", name: "Vibrate", tier: .free),

        .init(code: "dreamer", name: "Dreamer", tier: .premium),
        .init(code: "happy_message", name: "Happy Message", tier: .premium),
        .init(code: "notify", name: "Notify", tier: .premium),
        .init(code: "pop", name: "Pop", tier: .premium),
        .init(code: "pulsating_sound", name: "Pulsating Sound", tier: .premium),
        .init(code: "text_message", name: "Text Message", tier: .premium),
        .init(code: "xylophone", name: "Xylophone", tier: .premium)
    ]

    static func freeOptions() -> [MessageToneOption] {
        all.filter { $0.tier == .free }
    }

    static func premiumOptions() -> [MessageToneOption] {
        all.filter { $0.tier == .premium }
    }

    static func available(for plan: AppPlan) -> [MessageToneOption] {
        if plan.hasPremiumSounds {
            return all
        }
        return freeOptions()
    }

    static func name(for code: String) -> String {
        all.first(where: { $0.code == code })?.name ?? code.capitalized
    }

    static func tier(for code: String) -> OptionTier? {
        all.first(where: { $0.code == code })?.tier
    }
}
