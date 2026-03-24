import Foundation

struct IncomingCallPayload: Equatable {
    let uuid: UUID
    let displayName: String
    let remoteIdentity: String?
    let hasVideo: Bool
}
