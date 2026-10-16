import Foundation

final class CreatorReferralStore {
    static let shared = CreatorReferralStore()

    private let defaults: UserDefaults
    private let now: () -> Date
    private let key = "chatforia.creatorReferral"
    private let lifetime: TimeInterval = 30 * 24 * 60 * 60

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    static func code(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              url.scheme?.lowercased() == "https",
              ["chatforia.com", "www.chatforia.com"].contains(host) else {
            return nil
        }

        let path = url.pathComponents.filter { $0 != "/" }
        let rawCode: String?
        if path.count == 2 && path[0].lowercased() == "ref" {
            rawCode = path[1]
        } else if path.count == 1 && path[0].lowercased() == "register" {
            rawCode = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name.lowercased() == "ref" })?.value
        } else {
            return nil
        }

        guard let code = rawCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              (3...40).contains(code.count),
              code.unicodeScalars.allSatisfy({
                  (65...90).contains(Int($0.value)) ||
                  (48...57).contains(Int($0.value)) ||
                  $0.value == 95 || $0.value == 45
              }) else { return nil }
        return code
    }

    @discardableResult
    func capture(from url: URL) -> String? {
        guard let code = Self.code(from: url) else { return nil }
        if let existing = currentCode() { return existing }
        defaults.set(["code": code, "savedAt": now().timeIntervalSince1970], forKey: key)
        return code
    }

    func currentCode() -> String? {
        guard let saved = defaults.dictionary(forKey: key),
              let code = saved["code"] as? String,
              let timestamp = saved["savedAt"] as? TimeInterval,
              timestamp <= now().timeIntervalSince1970,
              now().timeIntervalSince1970 - timestamp < lifetime else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return code
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
