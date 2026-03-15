import SwiftUI

struct MessageBubbleView: View {
    let msg: MessageDTO
    let isMe: Bool
    let isGroupedWithPrevious: Bool
    let isGroupedWithNext: Bool

    var body: some View {
        content
            .font(.body)
            .foregroundStyle(isMe ? .white : .primary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                bubbleShape
                    .fill(bubbleColor)
            )
            .overlay {
                if isMe {
                    bubbleShape
                        .stroke(Color(red: 0.03, green: 0.45, blue: 0.90).opacity(0.22), lineWidth: 0.35)
                } else {
                    bubbleShape
                        .stroke(borderColor, lineWidth: 0.5)
                }
            }
            .shadow(
                color: isMe ? .clear : Color.black.opacity(0.03),
                radius: isMe ? 0 : 1,
                x: 0,
                y: 1
            )
    }

    private var bubbleShape: ChatBubbleShape {
        ChatBubbleShape(
            isMe: isMe,
            groupedWithPrevious: isGroupedWithPrevious,
            groupedWithNext: isGroupedWithNext
        )
    }

    private var bubbleColor: Color {
        isMe
            ? Color(red: 0.05, green: 0.52, blue: 0.98)
            : Color(uiColor: .systemGray6)
    }

    private var borderColor: Color {
        Color.black.opacity(0.055)
    }

    @ViewBuilder
    private var content: some View {
        if msg.deletedForAll == true {
            Text("This message was deleted")
                .italic()
                .foregroundStyle(isMe ? Color.white.opacity(0.82) : .secondary)
        } else if let translated = msg.translatedForMe,
                  !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(translated)
        } else if let raw = msg.rawContent,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(raw)
        } else if msg.contentCiphertext != nil, msg.encryptedKeyForMe != nil {
            DecryptMessageTextView(
                msg: msg,
                fallbackColor: isMe ? Color.white.opacity(0.82) : .secondary
            )
        } else if msg.contentCiphertext != nil {
            Text("🔒 Encrypted message")
        } else if let attachments = msg.attachments, !attachments.isEmpty {
            EmptyView()
        } else {
            Text("—")
        }
    }
}
