import SwiftUI

struct SimpleMessageRowView: View {
    let msg: MessageDTO
    let isMe: Bool
    let isGroupChat: Bool
    let showSenderName: Bool
    let showAvatar: Bool
    let groupedWithPrevious: Bool
    let groupedWithNext: Bool

    private let avatarLaneWidth: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            let maxBubbleWidth = isMe ? geo.size.width * 0.54 : geo.size.width * 0.60

            HStack(alignment: .bottom, spacing: 10) {
                if isMe {
                    Spacer(minLength: 70)
                } else if isGroupChat {
                    avatarLane
                }

                VStack(alignment: isMe ? .trailing : .leading, spacing: 8) {
                    if showSenderName {
                        Text(senderDisplayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 2)
                            .padding(.bottom, 2)
                    }

                    if hasVisibleAttachments {
                        MessageAttachmentsView(
                            attachments: visibleAttachments,
                            isMe: isMe,
                            maxWidth: maxBubbleWidth
                        )
                    }

                    if shouldShowBubble {
                        Text(displayText)
                            .font(.body)
                            .foregroundColor(isMe ? .white : .primary)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, isMe ? 13 : 14)
                            .padding(.vertical, isMe ? 7 : 8)
                            .background(isMe ? outgoingBlue : Color(uiColor: .systemGray5))
                            .clipShape(
                                ChatBubbleShape(
                                    isMe: isMe,
                                    groupedWithPrevious: groupedWithPrevious,
                                    groupedWithNext: groupedWithNext
                                )
                            )
                            .frame(maxWidth: maxBubbleWidth, alignment: isMe ? .trailing : .leading)
                    }
                }

                if !isMe {
                    Spacer(minLength: 64)
                }
            }
            .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
        }
        .frame(minHeight: 1)
    }

    @ViewBuilder
    private var avatarLane: some View {
        if showAvatar {
            Circle()
                .fill(Color.gray.opacity(0.18))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(initials)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.primary)
                )
                .frame(width: avatarLaneWidth, alignment: .center)
        } else {
            Color.clear
                .frame(width: avatarLaneWidth, height: 28)
        }
    }

    private var outgoingBlue: Color {
        Color(red: 0.06, green: 0.52, blue: 0.96)
    }

    private var senderDisplayName: String {
        let raw = msg.sender.username?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty { return raw }
        return "User \(msg.sender.id)"
    }

    private var initials: String {
        let parts = senderDisplayName
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }

        if !parts.isEmpty {
            return parts.joined()
        }

        return String(senderDisplayName.prefix(1)).uppercased()
    }

    private var visibleAttachments: [AttachmentDTO] {
        (msg.attachments ?? []).filter { attachment in
            let hasURL = !(attachment.url?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasThumb = !(attachment.thumbUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            return hasURL || hasThumb
        }
    }

    private var hasVisibleAttachments: Bool {
        !visibleAttachments.isEmpty && msg.deletedForAll != true
    }

    private var shouldShowBubble: Bool {
        if msg.deletedForAll == true { return true }

        if let translated = msg.translatedForMe,
           !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        if let raw = msg.rawContent,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        if msg.contentCiphertext != nil {
            return true
        }

        return !hasVisibleAttachments
    }

    private var displayText: String {
        if msg.deletedForAll == true {
            return "This message was deleted"
        }

        if let translated = msg.translatedForMe,
           !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return translated
        }

        if let raw = msg.rawContent,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw
        }

        if msg.contentCiphertext != nil {
            return "🔒 Encrypted message"
        }

        return "—"
    }
}
