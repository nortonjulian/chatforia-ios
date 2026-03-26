import Foundation

final class PendingInviteStore {
    static let shared = PendingInviteStore()
    private init() {}

    private let defaults = UserDefaults.standard

    private let codeKey = "chatforia.pendingInvite.code"
    private let inviterUserIdKey = "chatforia.pendingInvite.inviterUserId"
    private let inviterUsernameKey = "chatforia.pendingInvite.inviterUsername"

    func save(code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        defaults.set(trimmed, forKey: codeKey)
    }

    func savePreview(inviterUserId: Int?, inviterUsername: String?) {
        if let inviterUserId {
            defaults.set(inviterUserId, forKey: inviterUserIdKey)
        }
        if let inviterUsername {
            defaults.set(inviterUsername, forKey: inviterUsernameKey)
        }
    }

    func currentCode() -> String? {
        let code = defaults.string(forKey: codeKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (code?.isEmpty == false) ? code : nil
    }

    func inviterUserId() -> Int? {
        let value = defaults.object(forKey: inviterUserIdKey) as? Int
        return value
    }

    func inviterUsername() -> String? {
        defaults.string(forKey: inviterUsernameKey)
    }

    func clear() {
        defaults.removeObject(forKey: codeKey)
        defaults.removeObject(forKey: inviterUserIdKey)
        defaults.removeObject(forKey: inviterUsernameKey)
    }
}
