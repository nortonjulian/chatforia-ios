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
    let groupPosition: GroupPosition
    let showAvatar: Bool
    let showSenderName: Bool
    let deliveryState: DeliveryState?
    let onRetryTap: (() -> Void)?
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

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
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
            Circle()
                .fill(Color(uiColor: .systemGray4))
                .frame(width: 28, height: 28)
        } else {
            Color.clear
                .frame(width: 28, height: 28)
        }
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

    private var metadataLine: some View {
        HStack(spacing: 6) {
            if isMe, let deliveryText = deliveryStateText {
                Text(deliveryText)
                    .font(.caption2)
                    .foregroundColor(deliveryStateColor)
            }

            if let readReceiptText {
                if isMe, deliveryStateText != nil {
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(readReceiptText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 4)
    }

    private var shouldShowMetadataLine: Bool {
        (isMe && deliveryStateText != nil) || readReceiptText != nil
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
            return 8
        case .middle, .bottom:
            return 2
        }
    }

    private var bottomPadding: CGFloat {
        switch groupPosition {
        case .single, .bottom:
            return 6
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

    private var readReceiptText: String? {
        guard isMe else { return nil }
        guard let readBy = msg.readBy, !readBy.isEmpty else { return nil }

        if readBy.count == 1 {
            let name = readBy[0].username?.trimmingCharacters(in: .whitespacesAndNewlines)
            return name?.isEmpty == false ? "Read by \(name!)" : "Read"
        }

        return "Read by \(readBy.count)"
    }

    private var deliveryStateText: String? {
        switch deliveryState {
        case .pending:
            return "Pending"
        case .sending:
            return "Sending…"
        case .sent:
            return "Sent"
        case .failed:
            return "Failed"
        case .none:
            return nil
        }
    }

    private var deliveryStateColor: Color {
        switch deliveryState {
        case .failed:
            return .red
        case .pending, .sending, .sent, .none:
            return .secondary
        }
    }
}
