import SwiftUI

struct ChatThreadView: View {
    let room: ChatRoomDTO

    @EnvironmentObject var auth: AuthStore
    @StateObject private var vm = ChatThreadViewModel()
    @State private var draft = ""
    @State private var lastMessageId: Int? = nil

    @State private var editingMessage: MessageDTO?
    @State private var editDraft: String = ""

    @State private var deletingMessage: MessageDTO?
    @State private var showDeleteOptions = false

    @SwiftUI.Environment(\.scenePhase) private var scenePhase: ScenePhase

    var body: some View {
        baseContent
            .navigationTitle(roomDisplayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .task(id: room.id) {
                await onTaskLoad()
            }
            .onDisappear {
                onDisappearView()
            }
            .onChange(of: currentUserId) { _, _ in
                syncCurrentUser()
            }
            .onChange(of: currentUsername) { _, _ in
                syncCurrentUser()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            .onReceive(SocketManager.shared.$isConnected) { connected in
                handleSocketConnectionChange(connected)
            }
            .alert(
                "Edit Message",
                isPresented: Binding(
                    get: { editingMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            editingMessage = nil
                            editDraft = ""
                        }
                    }
                )
            ) {
                TextField("Message", text: $editDraft)

                Button("Cancel", role: .cancel) {
                    editingMessage = nil
                    editDraft = ""
                }

                Button("Save") {
                    Task {
                        await saveEdit()
                    }
                }
            } message: {
                Text("Update your message.")
            }
            .confirmationDialog(
                "Delete Message",
                isPresented: $showDeleteOptions,
                titleVisibility: .visible
            ) {
                if let msg = deletingMessage, msg.id > 0 {
                    Button("Delete for Me", role: .destructive) {
                        Task {
                            await performDelete(msg, scope: "me")
                        }
                    }

                    if msg.sender.id == currentUserId {
                        Button("Delete for Everyone", role: .destructive) {
                            Task {
                                await performDelete(msg, scope: "all")
                            }
                        }
                    }
                }

                Button("Cancel", role: .cancel) {
                    deletingMessage = nil
                }
            } message: {
                Text("Choose how you want to delete this message.")
            }
    }

    private var baseContent: some View {
        VStack(spacing: 0) {
            errorBanner

            messagesSection
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            typingBanner

            composer
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
        let retryHandler: (MessageDTO) -> Void = { msg in
            guard let cid = msg.clientMessageId, !cid.isEmpty else { return }
            SendQueueManager.shared.retryJob(clientMessageId: cid)
        }

        let editHandler: (MessageDTO) -> Void = { msg in
            editingMessage = msg
            editDraft = msg.rawContent ?? ""
        }

        let deleteHandler: (MessageDTO) -> Void = { msg in
            deletingMessage = msg
            showDeleteOptions = true
        }

        return Group {
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
                    onRetryTap: retryHandler,
                    onEdit: editHandler,
                    onDelete: deleteHandler,
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
                Task {
                    await send()
                }
            }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                Task {
                    await reload()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
    }

    private var currentUserId: Int? {
        if case .loggedIn(let user) = auth.state {
            return user.id
        }
        return nil
    }

    private var currentUsername: String? {
        if case .loggedIn(let user) = auth.state {
            return user.username
        }
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

    private func onTaskLoad() async {
        vm.configureRoom(roomId: room.id)
        syncCurrentUser()

        await reload()
        await vm.resyncIfNeeded(token: TokenStore.shared.read())

        vm.startSocket(
            roomId: room.id,
            token: TokenStore.shared.read(),
            myUsername: currentUsername
        )

        vm.startExpiryLoop()

        DispatchQueue.main.async {
            self.lastMessageId = vm.messages.sorted(by: { $0.id < $1.id }).last?.id
        }
    }

    private func onDisappearView() {
        vm.stopTypingNow(roomId: room.id)
        vm.stopSocket()
        vm.stopExpiryLoop()
    }

    private func syncCurrentUser() {
        vm.configureCurrentUser(
            id: currentUserId,
            username: currentUsername,
            publicKey: nil
        )
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        if newPhase == .active {
            Task {
                await vm.resyncIfNeeded(token: TokenStore.shared.read())
            }
            vm.startExpiryLoop()
        } else {
            vm.stopTypingNow(roomId: room.id)
            vm.stopExpiryLoop()
        }
    }

    private func handleSocketConnectionChange(_ connected: Bool) {
        guard connected else { return }

        Task {
            await vm.resyncIfNeeded(token: TokenStore.shared.read())
        }
    }

    private func reload() async {
        let token = TokenStore.shared.read()

        await vm.loadMessages(
            roomId: room.id,
            token: token
        )

        DispatchQueue.main.async {
            self.lastMessageId = vm.messages
                .sorted(by: { $0.id < $1.id })
                .last?.id
        }
    }

    private func send() async {
        let token = TokenStore.shared.read()
        let text = draft
        draft = ""

        await vm.sendMessage(
            roomId: room.id,
            token: token,
            text: text
        )
    }

    private func saveEdit() async {
        guard editingMessage != nil else { return }

        let trimmed = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await MainActor.run {
            editingMessage = nil
            editDraft = ""
        }

        // TODO: wire to your real ChatThreadViewModel edit/update method
    }

    private func performDelete(_ msg: MessageDTO, scope: String) async {
        _ = msg
        _ = scope

        await MainActor.run {
            deletingMessage = nil
        }

        // TODO: wire to your real ChatThreadViewModel delete method
    }

    private func typingIndicatorText(_ names: [String]) -> String {
        if names.count == 1 { return "\(names[0]) is typing…" }
        if names.count == 2 { return "\(names[0]) and \(names[1]) are typing…" }
        return "\(names.count) people are typing…"
    }

    private func deliveryState(for msg: MessageDTO) -> DeliveryState? {
        guard let clientMessageId = msg.clientMessageId,
              !clientMessageId.isEmpty else { return nil }

        return MessageStore.shared.getDeliveryState(clientMessageId: clientMessageId)
    }
}
