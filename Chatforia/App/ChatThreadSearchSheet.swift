import SwiftUI

struct ChatThreadSearchSheet: View {
    let messages: [MessageDTO]
    @Binding var searchText: String
    let onSelect: (MessageDTO) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(filteredMessages) { message in
                Button {
                    onSelect(message)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(snippet(for: message))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)

                        Text(timestampText(for: message))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "Search messages")
            .navigationTitle("Search in chat")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var filteredMessages: [MessageDTO] {
        let q = normalize(searchText)
        guard !q.isEmpty else { return [] }

        return messages.filter { message in
            searchableText(for: message).contains(q)
        }
    }

    private func searchableText(for message: MessageDTO) -> String {
        let visibleText = resolvedVisibleText(for: message)

        let attachmentCaption = (message.attachments ?? [])
            .compactMap { $0.caption?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")

        return normalize("\(visibleText) \(attachmentCaption)")
    }

    private func snippet(for message: MessageDTO) -> String {
        let visibleText = resolvedVisibleText(for: message)

        if !visibleText.isEmpty {
            return String(visibleText.prefix(240))
        }

        if message.deletedForAll == true {
            return "This message was deleted"
        }

        if message.contentCiphertext != nil {
            return "Encrypted message"
        }

        return "—"
    }

    private func resolvedVisibleText(for message: MessageDTO) -> String {
        let placeholderTexts: Set<String> = [
            "[image]",
            "[video]",
            "[audio]",
            "[file]",
            "[attachment]",
            "attachment"
        ]

        // Most likely missing source for visible text in encrypted / edited messages
        let decrypted = DecryptedMessageTextStore.shared.text(for: message.id)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !decrypted.isEmpty && !placeholderTexts.contains(decrypted.lowercased()) {
            return decrypted
        }

        let translated = message.translatedForMe?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !translated.isEmpty && !placeholderTexts.contains(translated.lowercased()) {
            return translated
        }

        let raw = message.rawContent?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !raw.isEmpty && !placeholderTexts.contains(raw.lowercased()) {
            return raw
        }

        let attachmentCaption = (message.attachments ?? [])
            .compactMap { $0.caption?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && !placeholderTexts.contains($0.lowercased()) }) ?? ""

        if !attachmentCaption.isEmpty {
            return attachmentCaption
        }

        return ""
    }

    private func timestampText(for message: MessageDTO) -> String {
        message.createdAt.formatted(
            .dateTime
                .month(.defaultDigits)
                .day(.defaultDigits)
                .year()
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute()
        )
    }

    private func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
