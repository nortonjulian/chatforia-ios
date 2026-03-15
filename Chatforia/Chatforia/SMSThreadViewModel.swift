import Foundation
import Combine

@MainActor
final class SMSThreadViewModel: ObservableObject {
    @Published var thread: SMSThreadDTO?
    @Published var messages: [SMSMessageDTO] = []
    @Published var isLoading: Bool = false
    @Published var isSending: Bool = false
    @Published var errorText: String?

    func loadThread(threadId: Int, token: String?) async {
        guard let token else {
            errorText = "Missing auth token."
            return
        }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let fetched: SMSThreadDTO = try await APIClient.shared.send(
                APIRequest(path: "sms/threads/\(threadId)", method: .GET, requiresAuth: true),
                token: token
            )

            thread = fetched
            messages = fetched.sortedMessages
        } catch {
            errorText = error.localizedDescription
            #if DEBUG
            print("❌ loadThread error:", error)
            #endif
        }
    }

    func sendTextMessage(threadId: Int, to: String, text: String, token: String?) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        guard let token else {
            errorText = "Missing auth token."
            return false
        }

        isSending = true
        errorText = nil

        let optimistic = SMSMessageDTO.optimisticOutgoing(
            threadId: threadId,
            to: to,
            body: trimmed
        )
        messages.append(optimistic)
        messages.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }

        struct SendSMSRequest: Encodable {
            let to: String
            let body: String
        }

        do {
            let body = try JSONEncoder().encode(
                SendSMSRequest(to: to, body: trimmed)
            )

            let _: EmptyResponse = try await APIClient.shared.send(
                APIRequest(path: "sms/send", method: .POST, body: body, requiresAuth: true),
                token: token
            )

            isSending = false
            await loadThread(threadId: threadId, token: token)
            return true
        } catch {
            isSending = false
            messages.removeAll { $0.id == optimistic.id }
            errorText = error.localizedDescription

            #if DEBUG
            print("❌ sendTextMessage error:", error)
            #endif

            return false
        }
    }

    func sendMediaMessage(
        threadId: Int,
        to: String,
        mediaUrls: [String],
        token: String?
    ) async -> Bool {
        guard !mediaUrls.isEmpty else { return false }

        guard let token else {
            errorText = "Missing auth token."
            return false
        }

        isSending = true
        errorText = nil

        struct SendSMSMediaRequest: Encodable {
            let to: String
            let body: String?
            let mediaUrls: [String]
        }

        do {
            let body = try JSONEncoder().encode(
                SendSMSMediaRequest(to: to, body: nil, mediaUrls: mediaUrls)
            )

            let _: EmptyResponse = try await APIClient.shared.send(
                APIRequest(path: "sms/send", method: .POST, body: body, requiresAuth: true),
                token: token
            )

            isSending = false
            await loadThread(threadId: threadId, token: token)
            return true
        } catch {
            isSending = false
            errorText = error.localizedDescription

            #if DEBUG
            print("❌ sendMediaMessage error:", error)
            #endif

            return false
        }
    }

    func resolvedTitle(fallback conversationTitle: String, fallbackPhone: String?) -> String {
        if let preferred = thread?.resolvedTitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            return preferred
        }

        if let title = conversationTitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            return title
        }

        if let phone = fallbackPhone?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            return phone
        }

        if let id = thread?.id {
            return "SMS #\(id)"
        }

        return "SMS"
    }

    func resolvedPhone(fallback conversationPhone: String?) -> String? {
        thread?.contactPhone?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        ?? conversationPhone?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
