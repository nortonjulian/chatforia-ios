import Foundation
import Combine

@MainActor
final class SMSThreadViewModel: ObservableObject {
    @Published var thread: SMSThreadDTO?
    @Published var messages: [SMSMessageDTO] = []
    @Published var isLoading: Bool = false
    @Published var isSending: Bool = false
    @Published var errorText: String?
    
    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
    }

    private var observers: [NSObjectProtocol] = []

    init() {
        let observer = NotificationCenter.default.addObserver(
            forName: .socketSMSMessageNew,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let threadId = notification.userInfo?["threadId"] as? Int
            let messagePayload = notification.userInfo?["message"] as? [String: Any]

            Task { @MainActor [weak self] in
                guard
                    let self,
                    let threadId,
                    let messagePayload,
                    let data = try? JSONSerialization.data(withJSONObject: messagePayload),
                    let message = try? JSONDecoder().decode(SMSMessageDTO.self, from: data)
                else { return }

                let currentThreadId = self.thread?.id ?? message.threadId
                guard threadId == currentThreadId else { return }

                if let index = self.messages.firstIndex(where: { $0.id == message.id }) {
                    self.messages[index] = message
                } else {
                    self.messages.append(message)
                }

                self.messages.sort {
                    if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                    return $0.id < $1.id
                }
            }
        }

        observers.append(observer)
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func loadThread(threadId: Int, token: String?) async {
        guard let token else {
            errorText = appText(
                "ios.missing_auth_token",
                languageCode: appLanguage
            )
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
            if messages.isEmpty {
                errorText = friendlyErrorMessage(error)
            } else {
                errorText = appText(
                    "sms.refreshFailed",
                    languageCode: appLanguage
                )
            }

            #if DEBUG
            print("❌ loadThread error:", error)
            #endif
        }
    }

    func sendTextMessage(
        existingThreadId: Int?,
        to: String,
        text: String,
        token: String?
    ) async -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let token else {
            errorText = appText(
                "ios.missing_auth_token",
                languageCode: appLanguage
            )
            return nil
        }

        isSending = true
        errorText = nil

        let optimisticThreadId = existingThreadId ?? -1
        let optimistic = SMSMessageDTO.optimisticOutgoing(
            threadId: optimisticThreadId,
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

            let response: SendSMSResponseDTO = try await APIClient.shared.send(
                APIRequest(path: "sms/send", method: .POST, body: body, requiresAuth: true),
                token: token
            )

            isSending = false
            
            AnalyticsManager.shared.capture("sms_sent", properties: [
                "type": "text"
            ])
            
            await loadThread(threadId: response.threadId, token: token)
            return response.threadId
        } catch {
            isSending = false
            messages.removeAll { $0.id == optimistic.id }
            errorText = friendlyErrorMessage(error)
            return nil
        }
    }

    func sendMediaMessage(
        existingThreadId: Int?,
        to: String,
        mediaUrls: [String],
        token: String?
    ) async -> Int? {
        guard !mediaUrls.isEmpty else { return nil }

        guard let token else {
            errorText = appText(
                "ios.missing_auth_token",
                languageCode: appLanguage
            )
            return nil
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

            let response: SendSMSResponseDTO = try await APIClient.shared.send(
                APIRequest(path: "sms/send", method: .POST, body: body, requiresAuth: true),
                token: token
            )

            isSending = false
            
            AnalyticsManager.shared.capture("sms_sent", properties: [
                "type": "media"
            ])
            
            await loadThread(threadId: response.threadId, token: token)
            return response.threadId
        } catch {
            isSending = false
            errorText = friendlyErrorMessage(error)
            return nil
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

    private func friendlyErrorMessage(_ error: Error) -> String {
    if let apiError = error as? APIError {
        switch apiError {
        case .server(let status, _):
            if status >= 500 {
                return "Server temporarily unavailable. Please try again."
            }

            return "Something went wrong. Please try again."

        case .network:
            return "Network connection issue. Please check your connection and try again."

        case .unauthorized:
            return appText(
                "api.notAuthorized",
                languageCode: appLanguage
            )

        default:
            return "Something went wrong. Please try again."
        }
    }

    return "Something went wrong. Please try again."
}
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
