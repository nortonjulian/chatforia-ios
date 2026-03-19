import Foundation

enum OptionTier: String, CaseIterable, Hashable {
    case free = "FREE"
    case premium = "PREMIUM"

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .premium: return "Premium"
        }
    }
}

struct ThemeOption: Identifiable, Hashable {
    let code: String
    let name: String
    let tier: OptionTier

    var id: String { code }

    var isPremium: Bool {
        tier == .premium
    }
}

enum AppThemes {
    static let all: [ThemeOption] = [
        .init(code: "dawn", name: "Dawn", tier: .free),
        .init(code: "midnight", name: "Midnight", tier: .free),

        .init(code: "amoled", name: "Amoled", tier: .premium),
        .init(code: "aurora", name: "Aurora", tier: .premium),
        .init(code: "neon", name: "Neon", tier: .premium),
        .init(code: "sunset", name: "Sunset", tier: .premium),
        .init(code: "solarized", name: "Solarized", tier: .premium),
        .init(code: "velvet", name: "Velvet", tier: .premium)
    ]

    static func freeOptions() -> [ThemeOption] {
        all.filter { $0.tier == .free }
    }

    static func premiumOptions() -> [ThemeOption] {
        all.filter { $0.tier == .premium }
    }

    static func available(for plan: AppPlan) -> [ThemeOption] {
        if plan.hasPremiumCustomization {
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
