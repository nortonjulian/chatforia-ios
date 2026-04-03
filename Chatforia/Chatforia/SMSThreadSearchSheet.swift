import SwiftUI

struct SMSThreadSearchSheet: View {
    let messages: [SMSMessageDTO]
    @Binding var searchText: String
    let onSelect: (SMSMessageDTO) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(filteredMessages) { message in
                Button {
                    onSelect(message)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(timestampText(for: message))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(message.isOutgoing ? "Sent" : "Received")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        Text(snippet(for: message))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "Search messages")
            .navigationTitle("Search in thread")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var filteredMessages: [SMSMessageDTO] {
        let q = normalize(searchText)
        guard !q.isEmpty else { return [] }

        return messages.filter { message in
            searchableText(for: message).contains(q)
        }
    }

    private func searchableText(for message: SMSMessageDTO) -> String {
        let body = message.body ?? ""

        let mediaText = message.media
            .map { item in
                [item.displayLabel, item.contentType ?? ""].joined(separator: " ")
            }
            .joined(separator: " ")

        return normalize("\(body) \(mediaText)")
    }

    private func snippet(for message: SMSMessageDTO) -> String {
        let body = (message.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !body.isEmpty {
            return String(body.prefix(240))
        }

        if !message.media.isEmpty {
            return message.media
                .map(\.displayLabel)
                .joined(separator: ", ")
        }

        return "[No text]"
    }

    private func timestampText(for message: SMSMessageDTO) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: message.createdAt)
    }

    private func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
