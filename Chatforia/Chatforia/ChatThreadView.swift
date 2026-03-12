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

            Divider()

            composer
        }
        .navigationTitle(roomDisplayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task(id: room.id) {
            vm.configureRoom(roomId: room.id)
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
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
        }
    }

    private var messagesSection: some View {
        Group {
            if vm.isLoading && vm.messages.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Loading messages…")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()

            } else if vm.messages.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No messages yet")
                        .foregroundColor(.secondary)
                    Text("Start the conversation.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()

            } else {
                MessagesListView(
                    messages: vm.messages,
                    currentUserId: currentUserId,
                    deliveryStateForMessage: { msg in
                        deliveryState(for: msg)
                    },
                    onLoadOlder: {
                        await vm.loadOlderMessagesIfNeeded()
                    },
                    onRetryTap: { msg in
                        guard let cid = msg.clientMessageId else { return }
                        NotificationCenter.default.post(
                            name: Notification.Name("ChatforiaRetrySend"),
                            object: cid
                        )
                    },
                    onEdit: { _ in
                        // wire later
                    },
                    onDelete: { _ in
                        // wire later
                    },
                    lastMessageId: $lastMessageId
                )
            }
        }
    }

    private var typingBanner: some View {
        Group {
            if !vm.typingUsernames.isEmpty {
                Text(typingIndicatorText(vm.typingUsernames))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .systemBackground))
            }
        }
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
        ToolbarItem(placement: .navigationBarTrailing) {
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
        return "Chat"
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
