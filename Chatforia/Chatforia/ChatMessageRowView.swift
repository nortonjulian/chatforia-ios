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

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMe {
                Spacer(minLength: 44)
            } else {
                avatarSlot
            }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                if showSenderName && !isMe {
                    Text(senderDisplayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 2)
                }

                MessageBubbleView(
                    msg: msg,
                    isMe: isMe,
                    isGroupedWithPrevious: groupPosition == .middle || groupPosition == .bottom,
                    isGroupedWithNext: groupPosition == .top || groupPosition == .middle
                )
                .frame(maxWidth: 300, alignment: isMe ? .trailing : .leading)
                .contextMenu {
                    if isEditable {
                        Button("Edit", systemImage: "pencil") {
                            onEdit?()
                        }

                        Button(role: .destructive) {
                            onDelete?()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                    if isMe, deliveryState == .failed {
                        Button("Retry", systemImage: "arrow.clockwise") {
                            onRetryTap?()
                        }
                    }
                }
                .onTapGesture {
                    if isMe, deliveryState == .failed {
                        onRetryTap?()
                    }
                }

                if hasReactions {
                    reactionsBar
                }

                metadataLine
            }
            .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)

            if !isMe {
                Spacer(minLength: 44)
            } else {
                Color.clear.frame(width: 28, height: 28)
            }
        }
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .animation(.easeInOut(duration: 0.15), value: msg.id)
    }

    private var avatarSlot: some View {
        Group {
            if showAvatar {
                avatarView
            } else {
                Color.clear.frame(width: 28, height: 28)
            }
        }
    }

    private var avatarView: some View {
        Group {
            if let avatarUrl = msg.senderAvatarURL {
                AsyncImage(url: avatarUrl) { phase in
                    switch phase {
                    case .empty:
                        avatarPlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        avatarPlaceholder
                    @unknown default:
                        avatarPlaceholder
                    }
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())
            } else {
                avatarPlaceholder
            }
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.gray.opacity(0.18))
            .frame(width: 28, height: 28)
            .overlay(
                Text(initials)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.primary)
            )
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
                .overlay(
                    Capsule()
                        .strokeBorder(myReactionsContains(pair.key) ? Color.blue.opacity(0.35) : Color.clear, lineWidth: 1)
                )
            }
        }
    }

    private var metadataLine: some View {
        HStack(spacing: 6) {
            Text(Self.timeFormatter.string(from: msg.createdAt))
                .font(.caption2)
                .foregroundColor(.secondary)

            if isMe, let deliveryText = deliveryStateText {
                Text("•")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(deliveryText)
                    .font(.caption2)
                    .foregroundColor(deliveryStateColor)
            }

            if readReceiptText != nil {
                Text("•")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(readReceiptText!)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 4)
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

    private var topPadding: CGFloat {
        switch groupPosition {
        case .single, .top: return 10
        case .middle, .bottom: return 2
        }
    }

    private var bottomPadding: CGFloat {
        switch groupPosition {
        case .single, .bottom: return 8
        case .top, .middle: return 1
        }
    }

    private var hasReactions: Bool {
        !(msg.reactionSummary ?? [:]).isEmpty
    }

    private var sortedReactionPairs: [(key: String, value: Int)] {
        (msg.reactionSummary ?? [:])
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
    }

    private func myReactionsContains(_ emoji: String) -> Bool {
        (msg.myReactions ?? []).contains(emoji)
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
        case .pending, .sending:
            return .secondary
        case .sent:
            return .secondary
        case .none:
            return .secondary
        }
    }
}

private extension MessageDTO {
    var senderAvatarURL: URL? {
        nil
    }
}
