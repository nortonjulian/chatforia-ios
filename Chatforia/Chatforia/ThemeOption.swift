import Foundation

struct ThemeOption: Identifiable, Hashable {
    let code: String
    let name: String
    let requiredPlan: AppPlan

    var id: String { code }

    var isLockedForFree: Bool {
        requiredPlan != .free
    }
}

enum AppThemes {
    static let all: [ThemeOption] = [
        .init(code: "dawn", name: "Dawn", requiredPlan: .free),
        .init(code: "midnight", name: "Midnight", requiredPlan: .free),

        .init(code: "amoled", name: "AMOLED", requiredPlan: .premium),
        .init(code: "aurora", name: "Aurora", requiredPlan: .premium),
        .init(code: "neon", name: "Neon", requiredPlan: .premium),
        .init(code: "sunset", name: "Sunset", requiredPlan: .premium),
        .init(code: "solarized", name: "Solarized", requiredPlan: .premium),
        .init(code: "velvet", name: "Velvet", requiredPlan: .premium)
    ]

    static func available(for plan: AppPlan) -> [ThemeOption] {
        all.filter { plan.canAccess($0.requiredPlan) }
    }

    static func isAvailable(_ code: String, for plan: AppPlan) -> Bool {
        guard let option = all.first(where: { $0.code == code }) else { return false }
        return plan.canAccess(option.requiredPlan)
    }

    static func name(for code: String) -> String {
        all.first(where: { $0.code == code })?.name ?? code.capitalized
    }

    static func requiredPlan(for code: String) -> AppPlan {
        all.first(where: { $0.code == code })?.requiredPlan ?? .free
    }
}
