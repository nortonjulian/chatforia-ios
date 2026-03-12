import SwiftUI

struct MessagesListView: View {
    let messages: [MessageDTO]
    let currentUserId: Int?
    let deliveryStateForMessage: (MessageDTO) -> DeliveryState?
    let onLoadOlder: () async -> Void
    let onRetryTap: (MessageDTO) -> Void
    let onEdit: (MessageDTO) -> Void
    let onDelete: (MessageDTO) -> Void

    @Binding var lastMessageId: Int?

    var body: some View {
        let sortedMessages = messages.sorted { a, b in
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id < b.id
        }

        let newestId = sortedMessages.last?.id

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sortedMessages.enumerated()), id: \.element.id) { index, msg in
                        let rowState = rowStateForMessage(at: index, in: sortedMessages)

                        ChatMessageRowView(
                            msg: msg,
                            isMe: (msg.sender.id == (currentUserId ?? -1)),
                            groupPosition: rowState.groupPosition,
                            showAvatar: rowState.showAvatar,
                            showSenderName: rowState.showSenderName,
                            deliveryState: deliveryStateForMessage(msg),
                            onRetryTap: { onRetryTap(msg) },
                            onEdit: { onEdit(msg) },
                            onDelete: { onDelete(msg) }
                        )
                        .id(msg.id)
                        .onAppear {
                            if msg.id == sortedMessages.first?.id {
                                Task { await onLoadOlder() }
                            }
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("BOTTOM")
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
            .background(Color(uiColor: .systemBackground))
            .onAppear {
                scrollToBottom(proxy)
            }
            .onChange(of: messages.count) { _, _ in
                let newNewest = newestId
                if newNewest != lastMessageId {
                    scrollToBottom(proxy)
                    lastMessageId = newNewest
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo("BOTTOM", anchor: .bottom)
        }
    }

    private func rowStateForMessage(at index: Int, in messages: [MessageDTO]) -> RowState {
        let current = messages[index]
        let previous = index > 0 ? messages[index - 1] : nil
        let next = index < (messages.count - 1) ? messages[index + 1] : nil

        let groupedWithPrevious = shouldGroup(previous: previous, current: current)
        let groupedWithNext = shouldGroup(previous: current, current: next)

        let groupPosition: ChatMessageRowView.GroupPosition
        switch (groupedWithPrevious, groupedWithNext) {
        case (false, false): groupPosition = .single
        case (false, true): groupPosition = .top
        case (true, true): groupPosition = .middle
        case (true, false): groupPosition = .bottom
        }

        let isMe = current.sender.id == (currentUserId ?? -1)

        return RowState(
            groupPosition: groupPosition,
            showAvatar: !isMe && (groupPosition == .single || groupPosition == .bottom),
            showSenderName: !isMe && (groupPosition == .single || groupPosition == .top)
        )
    }

    private func shouldGroup(previous: MessageDTO?, current: MessageDTO?) -> Bool {
        guard let previous, let current else { return false }
        guard previous.sender.id == current.sender.id else { return false }
        guard previous.deletedForAll != true, current.deletedForAll != true else { return false }
        guard previous.imageUrl == nil, current.imageUrl == nil else { return false }
        guard previous.audioUrl == nil, current.audioUrl == nil else { return false }

        let delta = current.createdAt.timeIntervalSince(previous.createdAt)
        return delta >= 0 && delta <= 5 * 60
    }

    private struct RowState {
        let groupPosition: ChatMessageRowView.GroupPosition
        let showAvatar: Bool
        let showSenderName: Bool
    }
}
