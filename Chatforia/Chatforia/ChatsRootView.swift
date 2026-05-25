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
        !auth.isPaid
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
                                title: String(localized: "ios.loading_chats"),
                                subtitle: String(localized: "ios.pulling_in_your_latest_conversations")
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        } else if let err = vm.errorText, !err.isEmpty, vm.conversations.isEmpty {
                            EmptyStateView(
                                systemImage: "exclamationmark.bubble",
                                title: String(localized: "ios.couldn_t_load_chats"),
                                subtitle: err,
                                buttonTitle: String(localized: "common.tryAgain"),
                                buttonAction: {
                                    Task { await reload() }
                                }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        } else if vm.filteredConversations.isEmpty &&
                                    !vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            EmptyStateView(
                                systemImage: "magnifyingglass",
                                title: String(localized: "ios.no_results"),
                                subtitle: String(localized: "ios.try_searching_for_a_different_name_or_message")
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        } else if vm.conversations.isEmpty {
                            EmptyStateView(
                                systemImage: "bubble.left.and.bubble.right",
                                title: String(localized: "ios.no_chats_yet"),
                                subtitle: String(localized: "ios.tap_the_plus_button_to_start_your_first_conversation")
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
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        Button {
                                            handleMessageFromChats(conversation)
                                        } label: {
                                            Label(
                                                String(localized: "ios.message"),
                                                systemImage: "message.fill"
                                            )
                                        }
                                        .tint(themeManager.palette.accent)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            Task {
                                                let token = TokenStore.shared.read()
                                                _ = await vm.archiveConversation(conversation, token: token)
                                            }
                                        } label: {
                                            Label(
                                                String(localized: "common.delete"),
                                                systemImage: "trash"
                                            )
                                        }
                                        .tint(.blue)

                                        Button(role: .destructive) {
                                            pendingConversation = conversation
                                            showDeleteConfirm = true
                                        } label: {
                                            Label("common.delete", systemImage: "trash")
                                        }
                                    }
                                    .listRowBackground(themeManager.palette.cardBackground)
                                }
                            }
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .listStyle(.insetGrouped)
                            .animation(
                                .easeInOut(duration: 0.2),
                                value: vm.filteredConversations.map { convo in
                                    "\(convo.kind)-\(convo.id ?? 0)"
                                }
                            )
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
            .navigationTitle(String(localized: "tab_chats"))
            .searchable(text: $vm.searchText, prompt: Text("ios.search_chats"))
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
                        if shouldShowAds {
                            InterstitialAdManager.shared.recordChatOpenAndMaybeShow()
                        }

                    case .sms(let conversation):
                        selectedSMSConversation = conversation
                        showSelectedSMS = true
                        if shouldShowAds {
                            InterstitialAdManager.shared.recordChatOpenAndMaybeShow()
                        }
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
            .alert(
                String(localized: "messages.deleteConversationTitle"),
                isPresented: $showDeleteConfirm
            ) {
                Button(
                    String(localized: "common.delete"),
                    role: .destructive
                ) {
                    if let convo = pendingConversation {
                        Task {
                            let token = TokenStore.shared.read()
                            _ = await vm.deleteConversation(convo, token: token)
                            pendingConversation = nil
                        }
                    }
                }
                Button(String(localized: "button_cancel"), role: .cancel) {
                    pendingConversation = nil
                }
            } message: {
                Text("ios.this_will_remove_the_conversation_from_your_list")
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
        await auth.refreshCurrentUser()

        if let theme = auth.currentUser?.theme {
            themeManager.apply(code: theme)
        }

        let token = TokenStore.shared.read()
        await vm.loadConversations(token: token)
    }
    
    private func handleMessageFromChats(_ conversation: ConversationDTO) {
        switch conversation.kind.lowercased() {
        case "chat":
            selectedRoom = conversation.asChatRoomDTO
            showSelectedRoom = true

        case "sms":
            selectedSMSConversation = conversation
            showSelectedSMS = true

        default:
            break
        }
    }

    @ViewBuilder
    private func destinationView(for conversation: ConversationDTO) -> some View {
        switch conversation.kind.lowercased() {
        case "chat":
            if let room = conversation.asChatRoomDTO {
                ChatThreadView(room: room, randomSession: nil)
            } else {
                UnsupportedConversationView(conversation: conversation)
            }
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

            let myAlias =
                dict["myAlias"] as? String
                ?? String(localized: "common.you")

            let partnerAlias =
                dict["partnerAlias"] as? String
                ?? String(localized: "random.stranger")

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
            let phone = item.phone?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let display = item.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !display.isEmpty {
                return display
            }

            if let phone, !phone.isEmpty {
                return phone
            }

            return String(localized: "messages.conversation")
        }

        return String(
            format: String(localized: "ios.chat_number"),
            item.id?.description ?? String(localized: "ios.draft")
        )
    }

    private func conversationSubtitle(_ conversation: ConversationDTO) -> String {
        guard let last = conversation.last else {
            return conversation.kind.lowercased() == "sms"
                ? String(localized: "ios.tap_to_open_sms_thread")
                : String(localized: "ios.tap_to_open")
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
                base = "📷 \(String(localized: "ios.photo"))"
            } else if kinds.contains("AUDIO") {
                base = "🎤 \(String(localized: "ios.voice_message"))"
            } else if kinds.contains("VIDEO") {
                base = "🎥 \(String(localized: "ios.video"))"
            } else if let mediaCount = last.mediaCount, mediaCount > 1 {
                base = "📎 \(String(localized: "ios.attachment"))"
            } else {
                base = "📎 \(String(localized: "ios.attachment"))"
            }

            if (conversation.isGroup ?? false),
               let sender = last.senderName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sender.isEmpty {
                return "\(sender): \(base)"
            }

            return base
        }

        return String(localized: "ios.tap_to_open")
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
            title: String(localized: "ios.unsupported_conversation"),
            subtitle: String(
                format: String(localized: "ios.kind_format"),
                conversation.kind
            )
        )
        .navigationTitle(
            String(localized: "messages.conversation")
        )
        .navigationBarTitleDisplayMode(.inline)
    }
}

