import Foundation
import Combine

@MainActor
final class RiaChatViewModel: ObservableObject {
    @Published var messages: [RiaChatMessage] = []
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var aiDisabledReason: String?

    private let service = RiaService()

    func sendMessage(
        token: String?,
        text: String,
        memoryEnabled: Bool,
        filterProfanity: Bool = false
    ) async {
        guard let token, !token.isEmpty else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMsg = RiaChatMessage(
            role: "user",
            content: trimmed
        )
        messages.append(userMsg)

        isLoading = true
        lastError = nil
        aiDisabledReason = nil

        do {
            let context = messages.map {
                RiaContextMessageDTO(role: $0.role, content: $0.content)
            }

            let reply = try await service.chat(
                token: token,
                messages: context,
                memoryEnabled: memoryEnabled,
                filterProfanity: filterProfanity
            )

            let aiMsg = RiaChatMessage(
                role: "assistant",
                content: reply
            )
            messages.append(aiMsg)
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("strict_e2ee") || message.contains("strict e2ee") {
                aiDisabledReason = String(localized: "ios.ria_unavailable_strict_e2ee")
            } else if (error as? URLError)?.code == .timedOut {
                lastError = String(localized: "ios.ria_took_too_long")
            } else {
                let message = error.localizedDescription.lowercased()

                if message.contains("strict_e2ee") || message.contains("strict e2ee") {
                    aiDisabledReason = String(localized: "ios.ria_unavailable_strict_e2ee")
                } else if message.contains("429") || message.contains("quota") || message.contains("billing") {
                    lastError = String(localized: "ios.ria_billing_not_set_up")
                } else {
                    lastError = error.localizedDescription
                }
            }
        }

        isLoading = false
    }

    func seedWelcomeIfNeeded() {
    }

    func clearConversation() {
        messages.removeAll()
        lastError = nil
        aiDisabledReason = nil
    }
}
