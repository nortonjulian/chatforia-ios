import SwiftUI

struct MessageBubbleView: View {
    let msg: MessageDTO
    let isMe: Bool
    let isGroupedWithPrevious: Bool
    let isGroupedWithNext: Bool

    var body: some View {
        content
            .font(.body)
            .foregroundColor(isMe ? .white : .primary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                bubbleShape
                    .fill(isMe ? Color.blue : Color(uiColor: .systemGray5))
            )
            .overlay(
                bubbleShape
                    .stroke(borderColor, lineWidth: isMe ? 0 : 0.5)
            )
            .shadow(color: Color.black.opacity(isMe ? 0.0 : 0.04), radius: 1, x: 0, y: 1)
    }

    private var bubbleShape: ChatBubbleShape {
        ChatBubbleShape(
            isMe: isMe,
            groupedWithPrevious: isGroupedWithPrevious,
            groupedWithNext: isGroupedWithNext
        )
    }

    private var borderColor: Color {
        Color.black.opacity(0.06)
    }

    @ViewBuilder
    private var content: some View {
        if msg.deletedForAll == true {
            Text("This message was deleted")
                .italic()
                .foregroundColor(isMe ? .white.opacity(0.78) : .secondary)
        } else if let translated = msg.translatedForMe,
                  !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(translated)
        } else if let raw = msg.rawContent,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(raw)
        } else if msg.contentCiphertext != nil {
            Text("🔒 Encrypted message")
        } else {
            Text("—")
        }
    }
}
