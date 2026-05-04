import Foundation

struct RandomSession {
    let roomId: Int
    let myAlias: String
    let partnerAlias: String

    var iRequestedFriend: Bool = false
    var partnerRequestedFriend: Bool = false

    var isFriendUnlocked: Bool {
        iRequestedFriend && partnerRequestedFriend
    }
}
