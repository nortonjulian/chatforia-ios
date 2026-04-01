import SwiftUI

struct ChatMessageRowView: View {
    enum GroupPosition {
        case single
        case top
        case middle
        case bottom
    }

    let msg: MessageDTO
    let isMe: Bool
    let isGroupRoom: Bool
    let groupPosition: GroupPosition
    let showAvatar: Bool
    let showSenderName: Bool
    let deliveryState: DeliveryState?
    let onRetryTap: (() -> Void)?
    let onReceiptTap: (() -> Void)?
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    let onReport: (() -> Void)?
    let isTimestampVisible: Bool
    let onBubbleTap: () -> Void
    let bubbleMaxWidth: CGFloat

    @EnvironmentObject private var themeManager: ThemeManager
    @State private var didAppear = false

    var body: some View {
        let canRetry = isMe && deliveryState == .failed
        let retryAction = onRetryTap
        let editAction = onEdit
        let deleteAction = onDelete


        return HStack(alignment: .bottom, spacing: 8) {
            if !isMe {
                avatarSlot
            }

            if isMe {
                Spacer(minLength: 50)
            }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                if showSenderName && !isMe {
                    Text(senderDisplayName)
                        .font(.caption)
                        .foregroundStyle(themeManager.palette.secondaryText)
                        .padding(.horizontal, 2)
                }

                if isTimestampVisible {
                    timestampView
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if hasVisibleAttachments {
                    MessageAttachmentsView(
                        attachments: visibleAttachments,
                        isMe: isMe,
                        maxWidth: bubbleMaxWidth
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .contentShape(Rectangle())
                    .contextMenu {
                        if isMe {
                            if canEditByRules {
                                Button("Edit", systemImage: "pencil") {
                                    onEdit?()
                                }
                            }

                            if canDeleteForEveryoneByRules || canDeleteForMeByRules {
                                Button(role: .destructive) {
                                    onDelete?()
                                } label: {
                                    Label(deleteMenuTitle, systemImage: "trash")
                                }
                            }

                            if isMe && deliveryState == .failed {
                                Button("Retry", systemImage: "arrow.clockwise") {
                                    onRetryTap?()
                                }
                            }
                        } else {
                            if onReport != nil {
                                Button("Report", systemImage: "flag") {
                                    onReport?()
                                }
                            }

                            if canDeleteForMeByRules {
                                Button(role: .destructive) {
                                    onDelete?()
                                } label: {
                                    Label("Delete for me", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                if shouldShowBubble {
                    MessageBubbleView(
                        msg: msg,
                        isMe: isMe,
                        isGroupedWithPrevious: groupPosition == .middle || groupPosition == .bottom,
                        isGroupedWithNext: groupPosition == .top || groupPosition == .middle
                    )
                    .frame(maxWidth: bubbleMaxWidth, alignment: isMe ? .trailing : .leading)
                    .contentShape(Rectangle())
                    .contextMenu {
                        if isMe {
                            if canEditByRules {
                                Button("Edit", systemImage: "pencil") {
                                    print("🟡 Edit tapped for message \(msg.id)")
                                    editAction?()
                                }
                            }

                            if canDeleteForEveryoneByRules || canDeleteForMeByRules {
                                Button(role: .destructive) {
                                    print("🟡 Delete tapped for message \(msg.id)")
                                    deleteAction?()
                                } label: {
                                    Label(deleteMenuTitle, systemImage: "trash")
                                }
                            }

                            if canRetry {
                                Button("Retry", systemImage: "arrow.clockwise") {
                                    retryAction?()
                                }
                            }
                        } else {
                            if onReport != nil {
                                Button("Report", systemImage: "flag") {
                                    onReport?()
                                }
                            }

                            if canDeleteForMeByRules {
                                Button(role: .destructive) {
                                    deleteAction?()
                                } label: {
                                    Label("Delete for me", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .onTapGesture {
                        onBubbleTap()
                    }
                }

                if hasReactions {
                    reactionsBar
                        .transition(.opacity)
                }

                if shouldShowMetadataLine {
                    metadataLine
                }
            }
            .frame(maxWidth: bubbleMaxWidth, alignment: isMe ? .trailing : .leading)

            if !isMe {
                Spacer(minLength: 50)
            }
        }
        .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
        .padding(.horizontal, 12)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .scaleEffect(didAppear ? 1 : 0.985)
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 4)
        .onAppear {
            guard !didAppear else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                didAppear = true
            }
        }
    }

    @ViewBuilder
    private var avatarSlot: some View {
        if showAvatar {
            UserAvatarView(
                avatarUrl: msg.sender.avatarUrl,
                displayName: senderDisplayName,
                size: 30,
                fallbackStyle: .initialsPreferred
            )
        } else {
            Color.clear
                .frame(width: 30, height: 30)
        }
    }

    private var timestampView: some View {
        Text(timestampText)
            .font(.caption2)
            .foregroundStyle(themeManager.palette.secondaryText)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var reactionsBar: some View {
        HStack(spacing: 6) {
            ForEach(sortedReactionPairs, id: \.key) { pair in
                HStack(spacing: 4) {
                    Text(pair.key)
                    Text("\(pair.value)")
                }
                .font(.caption)
                .foregroundStyle(themeManager.palette.primaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(themeManager.palette.cardBackground)
                .overlay(
                    Capsule()
                        .stroke(themeManager.palette.border.opacity(0.8), lineWidth: 1)
                )
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var metadataLine: some View {
        if let text = resolvedReceiptText {
            Group {
                if metadataIsTappable {
                    Button(action: {
                        if isMe && deliveryState == .failed {
                            onRetryTap?()
                        } else {
                            onReceiptTap?()
                        }
                    }) {
                        Text(text)
                            .font(.caption2)
                            .foregroundStyle(resolvedReceiptColor)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(text)
                        .font(.caption2)
                        .foregroundStyle(resolvedReceiptColor)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 1)
        }
    }

    private var shouldShowMetadataLine: Bool {
        guard isMe else { return false }
        guard resolvedReceiptText != nil else { return false }
        return groupPosition == .single || groupPosition == .bottom
    }

    private var metadataIsTappable: Bool {
        if isMe && deliveryState == .failed { return true }
        if isMe && hasReadableReceiptDetails { return true }
        return false
    }

    private var hasReadableReceiptDetails: Bool {
        guard isMe else { return false }
        guard let readBy = msg.readBy, !readBy.isEmpty else { return false }
        return true
    }

    private var senderDisplayName: String {
        let raw = msg.sender.username?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty { return raw }
        return "User \(msg.sender.id)"
    }

    private var timestampText: String {
        msg.createdAt.formatted(
            .dateTime
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute()
        )
    }
    
    private var deleteMenuTitle: String {
        if canDeleteForEveryoneByRules {
            return "Delete"
        } else {
            return "Delete for me"
        }
    }

    private var topPadding: CGFloat {
        switch groupPosition {
        case .single, .top:
            return 7
        case .middle, .bottom:
            return 1.5
        }
    }

    private var bottomPadding: CGFloat {
        switch groupPosition {
        case .single, .bottom:
            return 5
        case .top, .middle:
            return 0
        }
    }

    private var hasReactions: Bool {
        !(msg.reactionSummary ?? [:]).isEmpty
    }

    private var sortedReactionPairs: [(key: String, value: Int)] {
        (msg.reactionSummary ?? [:]).sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }
    }

    private var isEditable: Bool {
        isMe && !(msg.deletedForAll ?? false)
    }

    private var messageAge: TimeInterval {
        Date().timeIntervalSince(msg.createdAt)
    }

    private var withinEditWindow: Bool {
        messageAge <= 15 * 60
    }

    private var withinDeleteForEveryoneWindow: Bool {
        messageAge <= 15 * 60
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

    private var attachmentCaptionText: String? {
        visibleAttachments
            .compactMap { $0.caption?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private var hasAttachmentCaption: Bool {
        attachmentCaptionText != nil
    }

    private var shouldShowBubble: Bool {
        if msg.deletedForAll == true { return true }

        let mediaKinds = Set(
            visibleAttachments.map { ($0.kind ?? "").uppercased() }
        )

        let hasImageOrGIFAttachment =
            mediaKinds.contains("IMAGE") || mediaKinds.contains("GIF")

        if hasImageOrGIFAttachment {
            // For image/GIF messages, caption lives in MessageAttachmentsView
            return false
        }

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

    
    private var otherReaders: [UserSummaryDTO] {
        guard let readBy = msg.readBy else { return [] }
        return readBy.filter { $0.id != msg.sender.id }
    }

    private var isPendingOrSending: Bool {
        deliveryState == .pending || deliveryState == .sending
    }

    private var canEditByRules: Bool {
        let result =
            isMe &&
            msg.id > 0 &&
            isEditable &&
            !isPendingOrSending &&
            otherReaders.isEmpty &&
            withinEditWindow
        return result
    }
    
    private var canDeleteForEveryoneByRules: Bool {
        guard isMe else { return false }
        guard !isPendingOrSending else { return false }
        return withinDeleteForEveryoneWindow
    }

    private var canDeleteForMeByRules: Bool {
        true
    }

    private var resolvedReceiptText: String? {
        guard isMe else { return nil }

        if deliveryState == .failed {
            return editedText(prefix: "Failed · Tap to retry")
        }

        if let readersText = groupAwareReadText {
            return editedText(prefix: readersText)
        }

        let base: String? = {
            switch deliveryState {
            case .pending:
                return "Pending"
            case .sending:
                return "Sending…"
            case .sent:
                return "Sent"
            case .delivered:
                return "Delivered"
            case .read:
                return "Read"
            case .failed:
                return "Failed · Tap to retry"
            case .none:
                return nil
            }
        }()

        return editedText(prefix: base)
    }

    private func editedText(prefix: String?) -> String? {
        guard let prefix else {
            if msg.editedAt != nil { return "Edited" }
            return nil
        }

        if msg.editedAt != nil {
            return "\(prefix) · Edited"
        }
        return prefix
    }

    private var groupAwareReadText: String? {
        let readers = otherReaders
        guard !readers.isEmpty else { return nil }

        if !isGroupRoom {
            return "Read"
        }

        if readers.count == 1 {
            let raw = readers[0].username?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let raw, !raw.isEmpty {
                return "Read by \(raw)"
            }
            return "Read"
        }

        return "Read by \(readers.count)"
    }

    private var resolvedReceiptColor: Color {
        switch deliveryState {
        case .failed:
            return .red
        case .pending, .sending, .sent, .delivered, .read, .none:
            return themeManager.palette.secondaryText
        }
    }
}
