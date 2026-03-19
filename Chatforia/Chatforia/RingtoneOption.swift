import Foundation

struct RingtoneOption: Identifiable, Hashable {
    let code: String
    let name: String
    let tier: OptionTier

    var id: String { code }

    var isPremium: Bool {
        tier == .premium
    }
}

enum AppRingtones {
    static let all: [RingtoneOption] = [
        .init(code: "classic", name: "Classic", tier: .free),
        .init(code: "urgency", name: "Urgency", tier: .free),

        .init(code: "bells", name: "Bells", tier: .premium),
        .init(code: "chimes", name: "Chimes", tier: .premium),
        .init(code: "digital_phone", name: "Digital Phone", tier: .premium),
        .init(code: "melodic", name: "Melodic", tier: .premium),
        .init(code: "organ_notes", name: "Organ Notes", tier: .premium),
        .init(code: "sound_reality", name: "Sound Reality", tier: .premium),
        .init(code: "street", name: "Street", tier: .premium),
        .init(code: "universfield", name: "Universfield", tier: .premium)
    ]

    static func freeOptions() -> [RingtoneOption] {
        all.filter { $0.tier == .free }
    }

    static func premiumOptions() -> [RingtoneOption] {
        all.filter { $0.tier == .premium }
    }

    static func available(for plan: AppPlan) -> [RingtoneOption] {
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
