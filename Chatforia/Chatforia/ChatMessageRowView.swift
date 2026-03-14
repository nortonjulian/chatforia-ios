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
    let isTimestampVisible: Bool
    let onBubbleTap: () -> Void
    let bubbleMaxWidth: CGFloat

    @State private var didAppear = false

    var body: some View {
        let canEdit = isEditable
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

            VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
                if showSenderName && !isMe {
                    Text(senderDisplayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 2)
                }

                if isTimestampVisible {
                    timestampView
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                MessageBubbleView(
                    msg: msg,
                    isMe: isMe,
                    isGroupedWithPrevious: groupPosition == .middle || groupPosition == .bottom,
                    isGroupedWithNext: groupPosition == .top || groupPosition == .middle
                )
                .frame(maxWidth: bubbleMaxWidth, alignment: isMe ? .trailing : .leading)
                .contentShape(Rectangle())
                .contextMenu {
                    if canEdit {
                        Button("Edit", systemImage: "pencil") {
                            editAction?()
                        }

                        Button(role: .destructive) {
                            deleteAction?()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                    if canRetry {
                        Button("Retry", systemImage: "arrow.clockwise") {
                            retryAction?()
                        }
                    }
                }
                .onTapGesture {
                    onBubbleTap()
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
    
    private var avatarBackgroundColor: Color {
        Color(uiColor: .systemGray5)
    }

    private var senderInitials: String {
        let cleaned = senderDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "U" }

        let parts = cleaned
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }

        if !parts.isEmpty {
            return parts.joined()
        }

        return String(cleaned.prefix(1)).uppercased()
    }

    private var timestampView: some View {
        Text(timestampText)
            .font(.caption2)
            .foregroundColor(.secondary)
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
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(uiColor: .tertiarySystemBackground))
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
                            .foregroundColor(resolvedReceiptColor)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(text)
                        .font(.caption2)
                        .foregroundColor(resolvedReceiptColor)
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

    private var otherReaders: [UserSummaryDTO] {
        guard let readBy = msg.readBy else { return [] }
        return readBy.filter { $0.id != msg.sender.id }
    }

    private var resolvedReceiptText: String? {
        guard isMe else { return nil }

        if deliveryState == .failed {
            return "Failed · Tap to retry"
        }

        if let readersText = groupAwareReadText {
            return readersText
        }

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
            return .secondary
        }
    }
}
