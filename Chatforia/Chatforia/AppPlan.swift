import Foundation

enum AppPlan: String, CaseIterable {
    case free = "FREE"
    case plus = "PLUS"
    case premium = "PREMIUM"

    init(serverValue: String?) {
        switch (serverValue ?? "").uppercased() {
        case "PLUS": self = .plus
        case "PREMIUM": self = .premium
        default: self = .free
        }
    }

    var localizationKey: String {
        switch self {
        case .free: return "plan_free"
        case .plus: return "plan_plus"
        case .premium: return "plan_premium"
        }
    }

    var displayName: String {
        String(localized: String.LocalizationValue(localizationKey))
    }

    var rank: Int {
        switch self {
        case .free: return 0
        case .plus: return 1
        case .premium: return 2
        }
    }

    func canAccess(_ requiredPlan: AppPlan) -> Bool {
        rank >= requiredPlan.rank
    }

    var hasPremiumCustomization: Bool { canAccess(.premium) }
    var hasPremiumSounds: Bool { canAccess(.premium) }
    var canManageBilling: Bool { canAccess(.plus) }
    var canUseForwarding: Bool { canAccess(.plus) }
    var canUseAITools: Bool { canAccess(.premium) }
}