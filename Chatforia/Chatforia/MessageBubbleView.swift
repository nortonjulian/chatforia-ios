import SwiftUI

struct MessageBubbleView: View {
    let msg: MessageDTO
    let isMe: Bool
    let isGroupedWithPrevious: Bool
    let isGroupedWithNext: Bool

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        content
            .id(contentRenderKey)
            .font(.body)
            .foregroundStyle(isMe ? themeManager.palette.bubbleOutgoingText : themeManager.palette.bubbleIncomingText)
            .multilineTextAlignment(.leading)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.18), value: contentRenderKey)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                bubbleShape
                    .fill(bubbleFill)
            )
            .overlay {
                bubbleShape
                    .stroke(
                        isMe ? themeManager.palette.bubbleOutgoingEnd.opacity(0.15) : themeManager.palette.border.opacity(0.85),
                        lineWidth: isMe ? 0.4 : 0.8
                    )
            }
            .shadow(
                color: isMe ? themeManager.palette.bubbleOutgoingEnd.opacity(0.18) : .clear,
                radius: isMe ? 6 : 0,
                x: 0,
                y: 3
            )
    }
    
    private var contentRenderKey: String {
        let edited = msg.editedAt?.timeIntervalSince1970 ?? 0
        let revision = msg.revision ?? 0
        let raw = msg.rawContent ?? ""
        let translated = msg.translatedForMe ?? ""
        let deleted = (msg.deletedForAll == true || msg.deletedBySender == true) ? "deleted" : "live"
        return "\(msg.id)|\(revision)|\(edited)|\(raw)|\(translated)|\(deleted)"
    }
    
    private var bubbleShape: ChatBubbleShape {
        ChatBubbleShape(
            isMe: isMe,
            groupedWithPrevious: isGroupedWithPrevious,
            groupedWithNext: isGroupedWithNext
        )
    }

    private var bubbleFill: LinearGradient {
        if isMe {
            return LinearGradient(
                colors: [
                    themeManager.palette.bubbleOutgoingStart,
                    themeManager.palette.bubbleOutgoingEnd
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    themeManager.palette.bubbleIncoming,
                    themeManager.palette.bubbleIncoming
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if msg.deletedForAll == true || msg.deletedBySender == true {
            Text("This message was deleted")
                .italic()
                .foregroundStyle(
                    isMe
                    ? themeManager.palette.bubbleOutgoingText.opacity(0.82)
                    : themeManager.palette.secondaryText
                )
        } else if msg.contentCiphertext != nil, msg.encryptedKeyForMe != nil {
            DecryptMessageTextView(
                msg: msg,
                fallbackColor: isMe
                    ? themeManager.palette.bubbleOutgoingText.opacity(0.82)
                    : themeManager.palette.secondaryText
            )
        } else if let raw = msg.rawContent,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(raw)
                .onAppear {
                    print("RAW:", raw)
                    print(
                        "SCALARS:",
                        raw.unicodeScalars
                            .map { String(format: "U+%04X", $0.value) }
                            .joined(separator: " ")
                    )
                }
        } else if let translated = msg.translatedForMe,
                  !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(translated)
        } else if msg.contentCiphertext != nil {
            Text("🔒 Encrypted message")
        } else if let attachments = msg.attachments, !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Attachment")
                    .font(.subheadline.weight(.semibold))
                Text("\(attachments.count) file\(attachments.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(
                        isMe
                        ? themeManager.palette.bubbleOutgoingText.opacity(0.82)
                        : themeManager.palette.secondaryText
                    )
            }
        } else {
            Text("—")
        }
    }
}
