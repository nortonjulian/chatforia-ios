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
        let number = externalPhone?.trimmingCharacters(in: .whitespacesAndNewlines)
        return number?.isEmpty == false ? number : nil
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
        guard externalNumber == nil else { return nil }
        return isOutgoing(for: currentUserId) ? callee : caller
    }
}
