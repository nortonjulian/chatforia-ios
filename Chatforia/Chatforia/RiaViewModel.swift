import Foundation
import Combine

@MainActor
final class RiaViewModel: ObservableObject {
    @Published var suggestions: [String] = []
    @Published var isLoadingSuggestions = false
    @Published var rewriteOptions: [String] = []
    @Published var isLoadingRewrite = false
    @Published var aiDisabledReason: String?
    @Published var lastError: String?

    private let service = RiaService()
    private var suggestTask: Task<Void, Never>?

    func clearSuggestions() {
        suggestions = []
    }

    func clearRewriteOptions() {
        rewriteOptions = []
    }

    func loadSuggestions(
        token: String?,
        enabled: Bool,
        filterProfanity: Bool,
        draft: String,
        messages: [RiaContextMessageDTO]
    ) {
        suggestTask?.cancel()

        guard enabled else {
            suggestions = []
            aiDisabledReason = nil
            isLoadingSuggestions = false
            return
        }

        guard let token, !token.isEmpty else {
            suggestions = []
            isLoadingSuggestions = false
            return
        }

        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messages.isEmpty || !trimmedDraft.isEmpty else {
            suggestions = []
            isLoadingSuggestions = false
            return
        }

        suggestTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                try Task.checkCancellation()

                await MainActor.run {
                    self.isLoadingSuggestions = true
                    self.lastError = nil
                    self.aiDisabledReason = nil
                }

                let result = try await self.service.suggestReplies(
                    token: token,
                    messages: messages,
                    draft: trimmedDraft,
                    filterProfanity: filterProfanity
                )

                try Task.checkCancellation()

                await MainActor.run {
                    self.suggestions = Array(result.prefix(3))
                    self.isLoadingSuggestions = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isLoadingSuggestions = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingSuggestions = false
                    self.suggestions = []

                    let message = error.localizedDescription.lowercased()
                    if message.contains("strict_e2ee") || message.contains("strict e2ee") {
                        self.aiDisabledReason = "Ria is unavailable while Strict E2EE is enabled."
                    } else if (error as? URLError)?.code == .timedOut {
                        // Quiet failure for slow suggestions
                        self.lastError = nil
                    } else {
                        self.lastError = error.localizedDescription
                    }
                }
            }
        }
    }

    func rewrite(
        token: String?,
        text: String,
        tone: String,
        filterProfanity: Bool
    ) async {
        guard let token, !token.isEmpty else { return }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        isLoadingRewrite = true
        rewriteOptions = []
        lastError = nil
        aiDisabledReason = nil

        do {
            let result = try await service.rewriteText(
                token: token,
                text: trimmedText,
                tone: tone,
                filterProfanity: filterProfanity
            )
            rewriteOptions = Array(result.prefix(3))
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("strict_e2ee") || message.contains("strict e2ee") {
                aiDisabledReason = "Ria is unavailable while Strict E2EE is enabled."
            } else {
                lastError = error.localizedDescription
            }
        }

        isLoadingRewrite = false
    }
}
