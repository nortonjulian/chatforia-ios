import SwiftUI

struct MessagesListView: View {
    let messages: [MessageDTO]
    let currentUserId: Int?
    let isGroupRoom: Bool
    let deliveryStateForMessage: (MessageDTO) -> DeliveryState?
    let onLoadOlder: () async -> Void
    let onRetryTap: (MessageDTO) -> Void
    let onEdit: (MessageDTO) -> Void
    let onDelete: (MessageDTO) -> Void

    @Binding var lastMessageId: Int?
    @State private var expandedTimestampMessageId: Int?

    // New: paging guards
    @State private var lastPagingTriggerOldestId: Int?
    @State private var isPagingTriggerInFlight = false
    @State private var lastPagingTriggerAt: Date = .distantPast

    private let pagingThrottleSeconds: TimeInterval = 0.8

    private var sortedMessages: [MessageDTO] {
        messages.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
    }

    private var sortedMessageIDs: [Int] {
        sortedMessages.map(\.id)
    }

    private var oldestMessageId: Int? {
        sortedMessages.first?.id
    }

    var body: some View {
        GeometryReader { geo in
            let bubbleMaxWidth = geo.size.width * 0.72

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Top paging sentinel
                        Color.clear
                            .frame(height: 1)
                            .id("TOP_SENTINEL")
                            .onAppear {
                                triggerLoadOlderIfNeeded()
                            }

                        ForEach(sortedMessages.indices, id: \.self) { index in
                            messageRow(at: index, bubbleMaxWidth: bubbleMaxWidth)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("BOTTOM")
                    }
                    .padding(.vertical, 14)
                    .animation(.spring(response: 0.28, dampingFraction: 0.88), value: sortedMessageIDs)
                }
                .onAppear {
                    scrollToBottom(proxy)
                }
                .onChange(of: sortedMessages.last?.id) { _, newNewest in
                    if newNewest != lastMessageId {
                        scrollToBottom(proxy)
                        lastMessageId = newNewest
                    }
                }
                .onChange(of: sortedMessageIDs) { _, ids in
                    if let expanded = expandedTimestampMessageId, !ids.contains(expanded) {
                        expandedTimestampMessageId = nil
                    }
                }
                .onChange(of: oldestMessageId) { _, _ in
                    // Reset in-flight once the oldest id changes after a successful page insert
                    isPagingTriggerInFlight = false
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(at index: Int, bubbleMaxWidth: CGFloat) -> some View {
        let msg = sortedMessages[index]
        let isMe =
            msg.sender.id == (currentUserId ?? -1) ||
            (msg.id < 0 && msg.clientMessageId != nil)

        let previous: MessageDTO? = index > 0 ? sortedMessages[index - 1] : nil
        let next: MessageDTO? = index < sortedMessages.count - 1 ? sortedMessages[index + 1] : nil

        let groupedWithPrevious = shouldGroup(previous: previous, current: msg)
        let groupedWithNext = shouldGroup(previous: msg, current: next)
        let groupPosition = makeGroupPosition(
            groupedWithPrevious: groupedWithPrevious,
            groupedWithNext: groupedWithNext
        )

        if shouldShowDateSeparator(previous: previous, current: msg) {
            DateSeparatorView(date: msg.createdAt)
                .padding(.top, index == 0 ? 16 : 44)
                .padding(.bottom, 14)
        }

        ChatMessageRowView(
            msg: msg,
            isMe: isMe,
            groupPosition: groupPosition,
            showAvatar: !isMe && (groupPosition == .single || groupPosition == .bottom),
            showSenderName: isGroupRoom && !isMe && (groupPosition == .single || groupPosition == .top),
            deliveryState: deliveryStateForMessage(msg),
            onRetryTap: { onRetryTap(msg) },
            onEdit: { onEdit(msg) },
            onDelete: { onDelete(msg) },
            isTimestampVisible: expandedTimestampMessageId == msg.id,
            onBubbleTap: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedTimestampMessageId = (expandedTimestampMessageId == msg.id) ? nil : msg.id
                }
            },
            bubbleMaxWidth: bubbleMaxWidth
        )
        .id(msg.id)
        .transition(
            .asymmetric(
                insertion: .move(edge: .bottom)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 0.98)),
                removal: .opacity
            )
        )
    }

    private func triggerLoadOlderIfNeeded() {
        guard let oldestId = oldestMessageId else { return }
        guard !isPagingTriggerInFlight else { return }

        let now = Date()
        guard now.timeIntervalSince(lastPagingTriggerAt) >= pagingThrottleSeconds else { return }

        // Only trigger if the oldest currently visible message is different
        guard lastPagingTriggerOldestId != oldestId else { return }

        isPagingTriggerInFlight = true
        lastPagingTriggerOldestId = oldestId
        lastPagingTriggerAt = now

        Task {
            await onLoadOlder()
            await MainActor.run {
                isPagingTriggerInFlight = false
            }
        }
    }

    private func makeGroupPosition(groupedWithPrevious: Bool, groupedWithNext: Bool) -> ChatMessageRowView.GroupPosition {
        switch (groupedWithPrevious, groupedWithNext) {
        case (false, false): return .single
        case (false, true): return .top
        case (true, true): return .middle
        case (true, false): return .bottom
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo("BOTTOM", anchor: .bottom)
        }
    }

    private func shouldGroup(previous: MessageDTO?, current: MessageDTO?) -> Bool {
        guard let previous, let current else { return false }
        guard previous.sender.id == current.sender.id else { return false }

        let delta = current.createdAt.timeIntervalSince(previous.createdAt)
        return delta >= 0 && delta <= 45
    }

    private func shouldShowDateSeparator(previous: MessageDTO?, current: MessageDTO) -> Bool {
        guard let previous else { return true }
        return !Calendar.current.isDate(previous.createdAt, inSameDayAs: current.createdAt)
    }
}
