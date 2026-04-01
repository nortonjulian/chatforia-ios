import SwiftUI

private struct BottomSentinelMinYKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MessagesListView: View {
    @EnvironmentObject private var themeManager: ThemeManager

    let messages: [MessageDTO]
    let currentUserId: Int?
    let isGroupRoom: Bool
    let isLoadingOlder: Bool
    let deliveryStateForMessage: (MessageDTO) -> DeliveryState?
    let onLoadOlder: () async -> Void
    let onRetryTap: (MessageDTO) -> Void
    let onEdit: (MessageDTO) -> Void
    let onDelete: (MessageDTO) -> Void
    let onReport: (MessageDTO) -> Void

    @Binding var lastMessageId: Int?
    @State private var expandedTimestampMessageId: Int?
    @State private var selectedReceiptMessage: MessageDTO?

    @State private var lastPagingTriggerOldestId: Int?
    @State private var isPagingTriggerInFlight = false
    @State private var lastPagingTriggerAt: Date = .distantPast

    @State private var isNearBottom = true
    @State private var preservedAnchorMessageId: Int?
    @State private var isRestoringAfterPrepend = false
    @State private var viewportHeight: CGFloat = 0
    
    @State private var hasCompletedInitialBottomScroll = false

    private let pagingThrottleSeconds: TimeInterval = 0.8
    private let nearBottomThreshold: CGFloat = 140

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
                        Color.clear
                            .frame(height: 1)
                            .id("TOP_SENTINEL")
                            .onAppear {
                                guard hasCompletedInitialBottomScroll else { return }
                                triggerLoadOlderIfNeeded()
                            }

                        if isLoadingOlder {
                            ProgressView()
                                .padding(.vertical, 8)
                        }

                        ForEach(Array(sortedMessages.enumerated()), id: \.element.id) { index, _ in
                            messageRow(at: index, bubbleMaxWidth: bubbleMaxWidth)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("BOTTOM")
                            .background(
                                GeometryReader { bottomGeo in
                                    Color.clear
                                        .preference(
                                            key: BottomSentinelMinYKey.self,
                                            value: bottomGeo.frame(in: .named("MessagesScroll")).minY
                                        )
                                }
                            )
                    }
                    .padding(.vertical, 14)
                    .animation(.spring(response: 0.28, dampingFraction: 0.88), value: sortedMessageIDs)
                }
                .background(themeManager.palette.screenBackground)
                .coordinateSpace(name: "MessagesScroll")
                .background(
                    GeometryReader { scrollGeo in
                        Color.clear
                            .onAppear {
                                viewportHeight = scrollGeo.size.height
                            }
                            .onChange(of: scrollGeo.size.height) { _, newHeight in
                                viewportHeight = newHeight
                            }
                    }
                )
                .onPreferenceChange(BottomSentinelMinYKey.self) { bottomMinY in
                    isNearBottom = bottomMinY <= (viewportHeight + nearBottomThreshold)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        scrollToBottom(proxy, animated: false)
                        hasCompletedInitialBottomScroll = true
                    }
                }
                .onChange(of: sortedMessages.last?.id) { _, newNewest in
                    guard newNewest != lastMessageId else { return }

                    if !isRestoringAfterPrepend && isNearBottom {
                        scrollToBottom(proxy)
                    }

                    lastMessageId = newNewest
                }
                .onChange(of: sortedMessageIDs) { _, ids in
                    if let expanded = expandedTimestampMessageId, !ids.contains(expanded) {
                        expandedTimestampMessageId = nil
                    }
                    if let selected = selectedReceiptMessage, !ids.contains(selected.id) {
                        selectedReceiptMessage = nil
                    }

                    if isRestoringAfterPrepend,
                       let anchorId = preservedAnchorMessageId,
                       ids.contains(anchorId) {
                        DispatchQueue.main.async {
                            withAnimation(.none) {
                                proxy.scrollTo(anchorId, anchor: .top)
                            }
                            isRestoringAfterPrepend = false
                            preservedAnchorMessageId = nil
                        }
                    }
                }
                .onChange(of: oldestMessageId) { _, _ in
                    isPagingTriggerInFlight = false
                }
                .sheet(item: $selectedReceiptMessage) { msg in
                    MessageReceiptSheet(message: msg, isGroupRoom: isGroupRoom)
                }
            }
        }
        .background(themeManager.palette.screenBackground)
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

        let showAvatar = !isMe && !groupedWithNext
        let showSenderName = isGroupRoom && !isMe && !groupedWithPrevious
        let isTimestampVisible = expandedTimestampMessageId == msg.id

        if shouldShowDateSeparator(previous: previous, current: msg) {
            DateSeparatorView(date: msg.createdAt)
                .padding(.top, index == 0 ? 14 : 30)
                .padding(.bottom, 10)
        }

        ChatMessageRowView(
            msg: msg,
            isMe: isMe,
            isGroupRoom: isGroupRoom,
            groupPosition: groupPosition,
            showAvatar: showAvatar,
            showSenderName: showSenderName,
            deliveryState: deliveryStateForMessage(msg),
            onRetryTap: {
                onRetryTap(msg)
            },
            onReceiptTap: {
                selectedReceiptMessage = msg
            },
            onEdit: {
                onEdit(msg)
            },
            onDelete: {
                onDelete(msg)
            },
            onReport: !isMe ? {
                onReport(msg)
            } : nil,
            isTimestampVisible: isTimestampVisible,
            onBubbleTap: {
                expandedTimestampMessageId = expandedTimestampMessageId == msg.id ? nil : msg.id
            },
            bubbleMaxWidth: bubbleMaxWidth
        )
        .id(rowRenderKey(for: msg))
        .transition(
            .asymmetric(
                insertion: .move(edge: .bottom)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 0.98)),
                removal: .opacity
            )
        )
    }

    private func rowRenderKey(for msg: MessageDTO) -> String {
        let edited = msg.editedAt?.timeIntervalSince1970 ?? 0
        let revision = msg.revision ?? 0
        let raw = msg.rawContent ?? ""
        let translated = msg.translatedForMe ?? ""
        return "\(msg.id)|\(revision)|\(edited)|\(raw)|\(translated)"
    }

    private func triggerLoadOlderIfNeeded() {
        guard let oldestId = oldestMessageId else { return }
        guard !isPagingTriggerInFlight else { return }
        guard !isLoadingOlder else { return }

        let now = Date()
        guard now.timeIntervalSince(lastPagingTriggerAt) >= pagingThrottleSeconds else { return }
        guard lastPagingTriggerOldestId != oldestId else { return }

        preservedAnchorMessageId = oldestId
        isRestoringAfterPrepend = true

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

    private func makeGroupPosition(
        groupedWithPrevious: Bool,
        groupedWithNext: Bool
    ) -> ChatMessageRowView.GroupPosition {
        switch (groupedWithPrevious, groupedWithNext) {
        case (false, false): return .single
        case (false, true): return .top
        case (true, true): return .middle
        case (true, false): return .bottom
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo("BOTTOM", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("BOTTOM", anchor: .bottom)
            }
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
