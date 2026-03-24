import Foundation

enum CallDestination: Equatable {
    case phoneNumber(String, displayName: String?)
    case appUser(userId: Int, username: String?)

    var displayName: String {
        switch self {
        case .phoneNumber(let phone, let displayName):
            return displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? displayName!
                : phone
        case .appUser(_, let username):
            return username?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? username!
                : "Call"
        }
    }
}
