import Foundation

struct RingtoneOption: Identifiable, Hashable {
    let code: String
    let name: String
    let requiredPlan: AppPlan

    var id: String { code }
}

enum AppRingtones {
    static let all: [RingtoneOption] = [
        .init(code: "Classic.mp3", name: "Classic", requiredPlan: .free),
        .init(code: "Urgency.mp3", name: "Urgency", requiredPlan: .free),

        .init(code: "Bells.mp3", name: "Bells", requiredPlan: .premium),
        .init(code: "Chimes.mp3", name: "Chimes", requiredPlan: .premium),
        .init(code: "Digital Phone.mp3", name: "Digital Phone", requiredPlan: .premium),
        .init(code: "Melodic.mp3", name: "Melodic", requiredPlan: .premium),
        .init(code: "Organ Notes.mp3", name: "Organ Notes", requiredPlan: .premium),
        .init(code: "Sound Reality.mp3", name: "Sound Reality", requiredPlan: .premium),
        .init(code: "Street.mp3", name: "Street", requiredPlan: .premium),
        .init(code: "Universfield.mp3", name: "Universfield", requiredPlan: .premium)
    ]

    static func isAvailable(_ code: String, for plan: AppPlan) -> Bool {
        guard let option = all.first(where: { $0.code == code }) else { return false }
        return plan.canAccess(option.requiredPlan)
    }

    static func requiredPlan(for code: String) -> AppPlan {
        all.first(where: { $0.code == code })?.requiredPlan ?? .free
    }

    static func name(for code: String) -> String {
        all.first(where: { $0.code == code })?.name ?? code
    }
}
