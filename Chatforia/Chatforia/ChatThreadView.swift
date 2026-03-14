import SwiftUI

struct ChatThreadView: View {
    let room: ChatRoomDTO

    @EnvironmentObject var auth: AuthStore
    @StateObject private var vm = ChatThreadViewModel()
    @State private var draft = ""
    @State private var lastMessageId: Int? = nil

    @SwiftUI.Environment(\.scenePhase) private var scenePhase: ScenePhase

    var body: some View {
        VStack(spacing: 0) {
            errorBanner

            messagesSection
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            typingBanner

            composer
        }
        .navigationTitle(roomDisplayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task(id: room.id) {
            vm.configureRoom(roomId: room.id)
            vm.configureCurrentUser(
                id: currentUserId,
                username: currentUsername,
                publicKey: nil
            )
            await reload()
            await vm.resyncIfNeeded(token: TokenStore().read())
            vm.startSocket(roomId: room.id, token: TokenStore().read(), myUsername: currentUsername)
            vm.startExpiryLoop()

            DispatchQueue.main.async {
                self.lastMessageId = vm.messages.sorted(by: { $0.id < $1.id }).last?.id
            }
        }
        .onDisappear {
            vm.stopTypingNow(roomId: room.id)
            vm.stopSocket()
            vm.stopExpiryLoop()
        }
        .onChange(of: currentUserId) { _, _ in
            vm.configureCurrentUser(
                id: currentUserId,
                username: currentUsername,
                publicKey: nil
            )
        }
        .onChange(of: currentUsername) { _, _ in
            vm.configureCurrentUser(
                id: currentUserId,
                username: currentUsername,
                publicKey: nil
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await vm.resyncIfNeeded(token: TokenStore().read()) }
                vm.startExpiryLoop()
            } else {
                vm.stopTypingNow(roomId: room.id)
                vm.stopExpiryLoop()
            }
        }
        .onReceive(SocketManager.shared.$isConnected) { connected in
            guard connected else { return }
            Task { await vm.resyncIfNeeded(token: TokenStore().read()) }
        }
    }

    private var errorBanner: some View {
        Group {
            if let err = vm.errorText, !err.isEmpty {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.errorText)
    }

    private var messagesSection: some View {
        Group {
            if vm.isLoading && vm.messages.isEmpty {
                LoadingStateView(
                    title: "Loading messages…",
                    subtitle: "Bringing your conversation up to date."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if vm.messages.isEmpty {
                EmptyStateView(
                    systemImage: "bubble.left.and.bubble.right",
                    title: "No messages yet",
                    subtitle: "Start the conversation."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                MessagesListView(
                    messages: vm.messages,
                    currentUserId: currentUserId,
                    isGroupRoom: room.isGroup == true,
                    isLoadingOlder: vm.isLoadingOlder,
                    deliveryStateForMessage: { msg in
                        deliveryState(for: msg)
                    },
                    onLoadOlder: {
                        await vm.loadOlderMessagesIfNeeded()
                    },
                    onRetryTap: { msg in
                        guard let cid = msg.clientMessageId, !cid.isEmpty else { return }
                        SendQueueManager.shared.retryJob(clientMessageId: cid)
                    },
                    onEdit: { _ in
                    },
                    onDelete: { _ in
                    },
                    lastMessageId: $lastMessageId
                )
            }
        }
    }

    private var typingBanner: some View {
        Group {
            if !vm.typingUsernames.isEmpty {
                TypingIndicatorView(text: typingIndicatorText(vm.typingUsernames))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                    .background(Color(uiColor: .systemBackground))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.typingUsernames)
    }

    private var composer: some View {
        MessageComposerView(
            draft: $draft,
            onDraftChanged: {
                vm.handleInputChanged(roomId: room.id)
            },
            onSend: {
                Task { await send() }
            }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
    }

    private var currentUserId: Int? {
        if case .loggedIn(let user) = auth.state { return user.id }
        return nil
    }

    private var currentUsername: String? {
        if case .loggedIn(let user) = auth.state { return user.username }
        return nil
    }

    private var roomDisplayTitle: String {
        if let n = room.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !n.isEmpty {
            return n
        }

        let names = (room.participants ?? [])
            .filter { $0.id != currentUserId }
            .compactMap { $0.username?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !names.isEmpty {
            return names.joined(separator: ", ")
        }

        return "Chat #\(room.id)"
    }

    private func reload() async {
        let token = TokenStore().read()
        await vm.loadMessages(roomId: room.id, token: token)
        DispatchQueue.main.async {
            self.lastMessageId = vm.messages.sorted(by: { $0.id < $1.id }).last?.id
        }
    }

    private func send() async {
        let token = TokenStore().read()
        let text = draft
        draft = ""
        await vm.sendMessage(roomId: room.id, token: token, text: text)
    }

    private func typingIndicatorText(_ names: [String]) -> String {
        if names.count == 1 { return "\(names[0]) is typing…" }
        if names.count == 2 { return "\(names[0]) and \(names[1]) are typing…" }
        return "\(names.count) people are typing…"
    }

    private func deliveryState(for msg: MessageDTO) -> DeliveryState? {
        guard let clientMessageId = msg.clientMessageId, !clientMessageId.isEmpty else {
            return nil
        }
        return MessageStore.shared.getDeliveryState(clientMessageId: clientMessageId)
    }
}
