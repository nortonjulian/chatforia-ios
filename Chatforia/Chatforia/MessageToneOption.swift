import Foundation

struct MessageToneOption: Identifiable, Hashable {
    let code: String
    let name: String
    let requiredPlan: AppPlan

    var id: String { code }
}

enum AppMessageTones {
    static let all: [MessageToneOption] = [
        .init(code: "Default.mp3", name: "Default", requiredPlan: .free),
        .init(code: "Vibrate.mp3", name: "Vibrate", requiredPlan: .free),

        .init(code: "Dreamer.mp3", name: "Dreamer", requiredPlan: .premium),
        .init(code: "Happy Message.mp3", name: "Happy Message", requiredPlan: .premium),
        .init(code: "Notify.mp3", name: "Notify", requiredPlan: .premium),
        .init(code: "Pop.mp3", name: "Pop", requiredPlan: .premium),
        .init(code: "Pulsating Sound.mp3", name: "Pulsating Sound", requiredPlan: .premium),
        .init(code: "Text Message.mp3", name: "Text Message", requiredPlan: .premium),
        .init(code: "Xylophone.mp3", name: "Xylophone", requiredPlan: .premium)
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
