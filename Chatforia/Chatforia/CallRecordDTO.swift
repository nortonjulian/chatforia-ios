import Foundation

struct CallRecordDTO: Decodable, Identifiable, Equatable {
    let id: Int
    let roomId: Int?
    let callerId: Int
    let calleeId: Int?
    let mode: String
    let status: String
    let direction: String?
    let externalPhone: String?
    let twilioCallSid: String?
    let durationSec: Int?
    let endReason: String?
    let createdAt: Date
    let startedAt: Date?
    let endedAt: Date?
    let caller: CallUserSummaryDTO?
    let callee: CallUserSummaryDTO?
    let hasVoicemail: Bool?
    let voicemailId: String?

    // Older history responses may provide the number through these fields.
    var phoneNumber: String? = nil
    var fromLabel: String? = nil
    var toLabel: String? = nil
}

struct CallUserSummaryDTO: Decodable, Equatable {
    let id: Int
    let username: String?
    let displayName: String?
    let avatarUrl: String?
}


extension CallRecordDTO {
    func isOutgoing(for currentUserId: Int?) -> Bool {
        switch direction?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() {
        case "OUTGOING":
            return true

        case "INCOMING":
            return false

        default:
            // Compatibility with older server responses.
            return callerId == currentUserId
        }
    }

    var externalNumber: String? {
        var candidates = [externalPhone, phoneNumber]

        // Only use endpoint labels for a one-account phone-call record.
        // App-to-app calls can also have Twilio SIDs, so a SID is not a type check.
        if calleeId == nil || calleeId == callerId {
            switch direction?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
            case "INCOMING": candidates.append(fromLabel)
            case "OUTGOING": candidates.append(toLabel)
            default: break
            }
        }

        for candidate in candidates {
            guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  PhoneContactsService.normalizePhone(value) != nil
            else { continue }
            return value
        }
        return nil
    }

    func matchedExternalContactName(in contacts: [ContactDTO]) -> String? {
        guard let externalNumber,
              let normalized = PhoneContactsService.normalizePhone(externalNumber)
        else { return nil }

        guard let contact = contacts.first(where: {
            guard let number = $0.externalPhone else { return false }
            return PhoneContactsService.normalizePhone(number) == normalized
        }) else { return nil }

        for candidate in [contact.alias, contact.user?.username, contact.externalName] {
            if let name = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                return name
            }
        }

        return nil
    }

    func otherPartyName(for currentUserId: Int?, contacts: [ContactDTO]) -> String? {
        if let externalNumber {
            return matchedExternalContactName(in: contacts) ?? externalNumber
        }

        let user = otherUser(for: currentUserId)
        for candidate in [user?.displayName, user?.username] {
            if let name = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                return name
            }
        }

        return nil
    }

    func otherUser(for currentUserId: Int?) -> CallUserSummaryDTO? {
        // PSTN call records may store the account owner as caller.
        // The actual other party is the external number.
        guard externalNumber == nil,
              externalPhone?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              let currentUserId,
              currentUserId > 0,
              let calleeId,
              callerId > 0,
              calleeId > 0,
              callerId != calleeId
        else { return nil }

        // User identity is independent of display direction. Never offer
        // app actions to the account owner or to someone outside this call.
        let expectedId: Int
        let user: CallUserSummaryDTO?
        if currentUserId == callerId {
            expectedId = calleeId
            user = callee
        } else if currentUserId == calleeId {
            expectedId = callerId
            user = caller
        } else {
            return nil
        }

        guard user?.id == expectedId else { return nil }
        return user
    }
}
