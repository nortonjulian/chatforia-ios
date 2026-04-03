import SwiftUI

struct MessageBubbleView: View {
    let msg: MessageDTO
    let isMe: Bool
    let isGroupedWithPrevious: Bool
    let isGroupedWithNext: Bool
    
    @EnvironmentObject private var themeManager: ThemeManager
    @StateObject private var decryptedStore = DecryptedMessageTextStore.shared
    
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
    
    private var gifAttachment: AttachmentDTO? {
        msg.attachments?.first(where: { att in
            let kind = (att.kind ?? "").uppercased()
            let mime = (att.mimeType ?? "").lowercased()
            return kind == "GIF" || mime == "image/gif"
        })
    }
    
    private var gifURL: URL? {
        guard let urlString = gifAttachment?.url else { return nil }
        return URL(string: urlString)
    }
    
    private var hasRenderableGIF: Bool {
        gifURL != nil
    }
    
    private var decryptedText: String? {
        let text = decryptedStore
            .text(for: msg.id)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let text, !text.isEmpty {
            return text
        }

        return nil
    }
    
    private var contentRenderKey: String {
        let edited = msg.editedAt?.timeIntervalSince1970 ?? 0
        let revision = msg.revision ?? 0
        let raw = msg.rawContent ?? ""
        let translated = msg.translatedForMe ?? ""
        let decrypted = decryptedText ?? ""
        let deleted = (msg.deletedForAll == true || msg.deletedBySender == true) ? "deleted" : "live"
        return "\(msg.id)|\(revision)|\(edited)|\(raw)|\(translated)|\(decrypted)|\(deleted)"
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
        let decrypted = decryptedText
        
        let hasDecrypted: Bool = {
            guard let decrypted else { return false }
            return !decrypted.isEmpty
        }()
        
        let attachments = msg.attachments ?? []
        let hasAttachments = !attachments.isEmpty

        let raw = msg.rawContent?.trimmingCharacters(in: .whitespacesAndNewlines)
        let translated = msg.translatedForMe?.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentCaption = attachments
            .compactMap { $0.caption?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        let placeholderTexts: Set<String> = [
            "[image]",
            "[video]",
            "[audio]",
            "[file]",
            "[attachment]",
            "attachment"
        ]

        let normalizedRaw = raw?.lowercased()
        let normalizedTranslated = translated?.lowercased()
        let normalizedAttachmentCaption = attachmentCaption?.lowercased()

        let hasRenderableRaw: Bool = {
            guard let normalizedRaw else { return false }
            return !normalizedRaw.isEmpty && !placeholderTexts.contains(normalizedRaw)
        }()

        let hasRenderableTranslated: Bool = {
            guard let normalizedTranslated else { return false }
            return !normalizedTranslated.isEmpty && !placeholderTexts.contains(normalizedTranslated)
        }()

        let hasRenderableAttachmentCaption: Bool = {
            guard let normalizedAttachmentCaption else { return false }
            return !normalizedAttachmentCaption.isEmpty && !placeholderTexts.contains(normalizedAttachmentCaption)
        }()

        if msg.deletedForAll == true || msg.deletedBySender == true {
            Text("This message was deleted")
                .italic()
                .foregroundStyle(
                    isMe
                    ? themeManager.palette.bubbleOutgoingText.opacity(0.82)
                    : themeManager.palette.secondaryText
                )
        } else if hasDecrypted, let decrypted {
            Text(decrypted)

        } else if hasRenderableRaw, let raw {
            Text(raw)

        } else if hasRenderableTranslated, let translated {
            Text(translated)

        } else if hasRenderableAttachmentCaption, let attachmentCaption {
            Text(attachmentCaption)

        } else if msg.contentCiphertext != nil, msg.encryptedKeyForMe != nil {
            DecryptMessageTextView(
                msg: msg,
                fallbackColor: isMe
                    ? themeManager.palette.bubbleOutgoingText.opacity(0.82)
                    : themeManager.palette.secondaryText
            )

        } else if msg.contentCiphertext != nil, !hasAttachments {
            Text("🔒 Encrypted message")

        } else if hasAttachments {
            EmptyView()

        } else {
            Text("—")
        }
    }
}
