import SwiftUI

struct ChatsRootView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var vm = ChatsViewModel()

    @State private var showingStartChat = false
    @State private var selectedRoom: ChatRoomDTO? = nil
    @State private var showSelectedRoom = false
    @State private var selectedSMSConversation: ConversationDTO? = nil
    @State private var showSelectedSMS = false

    @State private var showDeleteConfirm = false
    @State private var pendingConversation: ConversationDTO?

    @State private var isMatching = false
    @State private var matchedRoom: ChatRoomDTO?
    @State private var selectedRandomSession: RandomSession? = nil
    @State private var didSetupRandomMatchListener = false
    @State private var showRiaChat = false
    @StateObject private var settingsVM = SettingsViewModel()

    private var shouldShowAds: Bool {
        !auth.isPremium
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.screenBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Group {
                        if vm.isLoading && vm.conversations.isEmpty {
                            LoadingStateView(
                                title: "Loading chats…",
                                subtitle: "Pulling in your latest conversations."
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        } else if let err = vm.errorText, !err.isEmpty, vm.conversations.isEmpty {
                            EmptyStateView(
                                systemImage: "exclamationmark.bubble",
                                title: "Couldn’t load chats",
                                subtitle: err,
                                buttonTitle: "Try Again",
                                buttonAction: {
                                    Task { await reload() }
                                }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        } else if vm.filteredConversations.isEmpty &&
                                    !vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            EmptyStateView(
                                systemImage: "magnifyingglass",
                                title: "No results",
                                subtitle: "Try searching for a different name or message."
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        } else if vm.conversations.isEmpty {
                            EmptyStateView(
                                systemImage: "bubble.left.and.bubble.right",
                                title: "No chats yet",
                                subtitle: "Tap the plus button to start your first conversation."
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        } else {
                            List {
                                if let err = vm.errorText, !err.isEmpty {
                                    Section {
                                        Text(err)
                                            .font(.footnote)
                                            .foregroundStyle(.red)
                                    }
                                    .listRowBackground(themeManager.palette.cardBackground)
                                }

                                ForEach(vm.filteredConversations, id: \.uniqueId) { conversation in
                                    NavigationLink {
                                        destinationView(for: conversation)
                                    } label: {
                                        ChatListRowView(
                                            title: conversationTitle(conversation),
                                            subtitle: conversationSubtitle(conversation),
                                            timestamp: conversationTimestamp(conversation),
                                            unreadCount: conversation.unreadCount ?? 0,
                                            avatarUsers: conversation.avatarUsers ?? [],
                                            isPinned: false
                                        )
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            Task {
                                                let token = TokenStore.shared.read()
                                                _ = await vm.archiveConversation(conversation, token: token)
                                            }
                                        } label: {
                                            Label("Archive", systemImage: "archivebox")
                                        }
                                        .tint(.blue)

                                        Button(role: .destructive) {
                                            pendingConversation = conversation
                                            showDeleteConfirm = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .listRowBackground(themeManager.palette.cardBackground)
                                }
                            }
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .listStyle(.insetGrouped)
                            .animation(.easeInOut(duration: 0.2), value: vm.filteredConversations.map { "\($0.kind)-\($0.id)" })
                        }
                    }

                    if shouldShowAds {
                        BannerAdView()
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(themeManager.palette.screenBackground)
                    }
                }
            }
            .navigationDestination(isPresented: $showSelectedRoom) {
                if let room = selectedRoom {
                    ChatThreadView(
                        room: room,
                        randomSession: selectedRandomSession
                    )
                }
            }
            .navigationDestination(isPresented: $showSelectedSMS) {
                if let conversation = selectedSMSConversation {
                    SMSThreadView(conversation: conversation)
                }
            }
            .navigationDestination(isPresented: $showRiaChat) {
                RiaChatView()
                    .environmentObject(auth)
                    .environmentObject(themeManager)
                    .environmentObject(settingsVM)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Chats")
            .searchable(text: $vm.searchText, prompt: "Search chats")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingStartChat = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .foregroundStyle(themeManager.palette.accent)

                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .foregroundStyle(themeManager.palette.accent)

                    Button {
                        showRiaChat = true
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .foregroundStyle(themeManager.palette.accent)

                    Button {
                        startRandomChat()
                    } label: {
                        Image(systemName: "shuffle")
                    }
                    .foregroundStyle(themeManager.palette.accent)
                }
            }
            .sheet(isPresented: $showingStartChat) {
                StartChatView { destination in
                    switch destination {
                    case .chat(let room):
                        selectedRoom = room
                        showSelectedRoom = true
                        InterstitialAdManager.shared.recordChatOpenAndMaybeShow()

                    case .sms(let conversation):
                        selectedSMSConversation = conversation
                        showSelectedSMS = true
                        InterstitialAdManager.shared.recordChatOpenAndMaybeShow()
                    }
                }
                .environmentObject(auth)
                .environmentObject(themeManager)
            }
            .sheet(isPresented: $isMatching) {
                RandomMatchingView(
                    onCancel: {
                        SocketManager.shared.leaveRandomQueue()
                        isMatching = false
                    }
                )
            }
            .alert("Delete Conversation?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let convo = pendingConversation {
                        Task {
                            let token = TokenStore.shared.read()
                            _ = await vm.deleteConversation(convo, token: token)
                            pendingConversation = nil
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingConversation = nil
                }
            } message: {
                Text("This will remove the conversation from your list.")
            }
            .task {
                if !didSetupRandomMatchListener {
                    setupRandomMatchListener()
                    didSetupRandomMatchListener = true
                }

                await reload()
            }
            .refreshable {
                await reload()
            }
            .onReceive(NotificationCoordinator.shared.$pendingChatRoomId) { roomId in
                guard let roomId else { return }

                Task {
                    await openChatFromNotification(roomId: roomId)
                }

                NotificationCoordinator.shared.pendingChatRoomId = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("randomNextPerson"))) { _ in
                startRandomChat()
            }
        }
    }

    private func reload() async {
        let token = TokenStore.shared.read()
        await vm.loadConversations(token: token)
    }

    @ViewBuilder
    private func destinationView(for conversation: ConversationDTO) -> some View {
        switch conversation.kind.lowercased() {
        case "chat":
            ChatThreadView(room: conversation.asChatRoomDTO, randomSession: nil)
        case "sms":
            SMSThreadView(conversation: conversation)
        default:
            UnsupportedConversationView(conversation: conversation)
        }
    }

    private func startRandomChat() {
        isMatching = true

        guard let token = TokenStore.shared.read(), !token.isEmpty else {
            isMatching = false
            return
        }

        SocketManager.shared.connect(token: token)

        // Default behavior: no topic required.
        // This supports users who just want to talk to anyone.
        SocketManager.shared.joinRandomQueue()
    }

    private func setupRandomMatchListener() {

        // 🔹 MATCH FOUND
        SocketManager.shared.on("random:matched") { data, _ in
            guard let dict = data.first as? [String: Any],
                  let roomId = dict["roomId"] as? Int else { return }

            let myAlias = dict["myAlias"] as? String ?? "You"
            let partnerAlias = dict["partnerAlias"] as? String ?? "Stranger"

            Task { @MainActor in
                await handleMatchFound(
                    roomId: roomId,
                    myAlias: myAlias,
                    partnerAlias: partnerAlias
                )
            }
        }

        // 🔹 FRIEND ACCEPTED (NEW)
        SocketManager.shared.on("random:friend_accepted") { data, _ in
            guard let dict = data.first as? [String: Any],
                  let roomId = dict["roomId"] as? Int else { return }

            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .init("randomFriendAccepted"),
                    object: roomId
                )
            }
        }
    }

    private func handleMatchFound(roomId: Int, myAlias: String, partnerAlias: String) async {
        isMatching = false

        guard let token = TokenStore.shared.read(), !token.isEmpty else { return }

        do {
            let room: ChatRoomDTO = try await APIClient.shared.send(
                APIRequest(path: "chatrooms/\(roomId)", method: .GET, requiresAuth: true),
                token: token
            )

            let session = RandomSession(
                roomId: roomId,
                myAlias: myAlias,
                partnerAlias: partnerAlias
            )

            selectedRoom = room
            matchedRoom = room

            selectedRandomSession = session

            showSelectedRoom = true
        } catch {
            print("❌ match fetch failed:", error)
        }
    }

    private func openChatFromNotification(roomId: Int) async {
        guard let token = TokenStore.shared.read(), !token.isEmpty else { return }

        do {
            let room: ChatRoomDTO = try await APIClient.shared.send(
                APIRequest(path: "chatrooms/\(roomId)", method: .GET, requiresAuth: true),
                token: token
            )
            selectedRandomSession = nil
            selectedRoom = room
            showSelectedRoom = true
        } catch {
            print("❌ Failed to open chat from notification:", error)
        }
    }

    private func conversationTitle(_ item: ConversationDTO) -> String {
        let display = item.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !display.isEmpty { return display }

        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }

        if item.kind.lowercased() == "sms" {
            if let phone = item.phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
                return phone
            }
            return "SMS #\(item.id)"
        }

        return "Chat #\(item.id)"
    }

    private func conversationSubtitle(_ conversation: ConversationDTO) -> String {
        guard let last = conversation.last else {
            return conversation.kind.lowercased() == "sms"
                ? "Tap to open SMS thread"
                : "Tap to open"
        }

        let text = last.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !text.isEmpty {
            if (conversation.isGroup ?? false),
               let sender = last.senderName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sender.isEmpty {
                return "\(sender): \(text)"
            }
            return text
        }

        if last.hasMedia == true {
            let kinds = (last.mediaKinds ?? []).map { $0.uppercased() }
            let base: String

            if kinds.contains("GIF") {
                base = "🎞 GIF"
            } else if kinds.contains("IMAGE") {
                base = "📷 Photo"
            } else if kinds.contains("AUDIO") {
                base = "🎤 Voice message"
            } else if kinds.contains("VIDEO") {
                base = "🎥 Video"
            } else if let mediaCount = last.mediaCount, mediaCount > 1 {
                base = "📎 \(mediaCount) attachments"
            } else {
                base = "📎 Attachment"
            }

            if (conversation.isGroup ?? false),
               let sender = last.senderName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sender.isEmpty {
                return "\(sender): \(base)"
            }

            return base
        }

        return conversation.kind.lowercased() == "sms"
            ? "Tap to open SMS thread"
            : "Tap to open"
    }

    private func conversationTimestamp(_ item: ConversationDTO) -> String {
        if let at = item.last?.at, !at.isEmpty {
            return TimestampFormatter.chatListTimestamp(from: at)
        }

        return TimestampFormatter.chatListTimestamp(from: item.updatedAt)
    }
}

private struct UnsupportedConversationView: View {
    let conversation: ConversationDTO

    var body: some View {
        EmptyStateView(
            systemImage: "questionmark.bubble",
            title: "Unsupported conversation",
            subtitle: "Kind: \(conversation.kind)"
        )
        .navigationTitle("Conversation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

