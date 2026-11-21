import Foundation

struct RandomSession {
    let roomId: Int
    let myAlias: String
    let partnerAlias: String

    var iRequestedFriend: Bool = false
    var partnerRequestedFriend: Bool = false

    init(roomId: Int, myAlias: String, partnerAlias: String) {
        self.roomId = roomId
        self.myAlias = myAlias
        self.partnerAlias = partnerAlias
    }

    init?(socketPayload: [String: Any]) {
        guard let roomId = socketPayload["roomId"] as? Int, roomId > 0 else {
            return nil
        }
        self.init(
            roomId: roomId,
            myAlias: socketPayload["myAlias"] as? String ?? "You",
            partnerAlias: socketPayload["partnerAlias"] as? String ?? "Someone"
        )
        iRequestedFriend = socketPayload["iRequestedFriend"] as? Bool ?? false
    }

    var isFriendUnlocked: Bool {
        iRequestedFriend && partnerRequestedFriend
    }
}
