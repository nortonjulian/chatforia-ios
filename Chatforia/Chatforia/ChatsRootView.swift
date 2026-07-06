import SwiftUI

struct ChatsRootView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"
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
    @State private var activeRandomRoomIds = Set<Int>()

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
                                title: appText(
                                    "ios.loading_chats",
                                    languageCode: appLanguage
                                ),
                                subtitle: appText(
                                    "ios.pulling_in_your_latest_conversations",
                                    languageCode: appLanguage
                                )
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        } else if let err = vm.errorText, !err.isEmpty, vm.conversations.isEmpty {
                            EmptyStateView(
                                systemImage: "exclamationmark.bubble",
                                title: appText(
                                    "ios.couldn_t_load_chats",
                                    languageCode: appLanguage
                                ),
                                subtitle: err,
                                buttonTitle: appText(
                                    "common.tryAgain",
                                    languageCode: appLanguage
                                ),
                                buttonAction: {
                                    Task { await reload() }
                                }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        } else if vm.filteredConversations.isEmpty &&
                                    !vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            EmptyStateView(
                                systemImage: "magnifyingglass",
                                title: appText(
                                    "ios.no_results",
                                    languageCode: appLanguage
                                ),
                                subtitle: appText(
                                    "ios.try_searching_for_a_different_name_or_message",
                                    languageCode: appLanguage
                                )
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        } else if vm.conversations.isEmpty {
                            EmptyStateView(
                                systemImage: "bubble.left.and.bubble.right",
                                title: appText(
                                    "ios.no_chats_yet",
                                    languageCode: appLanguage
                                ),
                                subtitle: appText(
                                    "ios.tap_the_plus_button_to_start_your_first_conversation",
                                    languageCode: appLanguage
                                )
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
                            
                                    Button {
                                            openConversationFromList(conversation)
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
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        if isRandomChatConversation(conversation) {
                                            Button {
                                                leaveRandomChatFromList(conversation)
                                            } label: {
                                                Label("Leave", systemImage: "xmark.circle.fill")
                                            }
                                            .tint(.orange)
                                        } else {
                                            Button {
                                                handleMessageFromChats(conversation)
                                            } label: {
                                                Label(
                                                    appText(
                                                        "ios.message",
                                                        languageCode: appLanguage
                                                    ),
                                                    systemImage: "message.fill"
                                                )
                                            }
                                            .tint(themeManager.palette.accent)
                                        }
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            Task {
                                                let token = TokenStore.shared.read()
                                                _ = await vm.archiveConversation(conversation, token: token)
                                            }
                                        } label: {
                                            Label(
                                                appText(
                                                    "common.delete",
                                                    languageCode: appLanguage
                                                ),
                                                systemImage: "trash"
                                            )
                                        }
                                        .tint(.red)

                                        Button(role: .destructive) {
                                            pendingConversation = conversation
                                            showDeleteConfirm = true
                                        } label: {
                                            Label(
                                                appText(
                                                    "common.delete",
                                                    languageCode: appLanguage
                                                ),
                                                systemImage: "trash"
                                            )
                                        }
                                    }
                                    .listRowBackground(themeManager.palette.cardBackground)
                                }
                            }
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .listStyle(.insetGrouped)
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
            .navigationTitle(appText(
                "tab_chats",
                languageCode: appLanguage
            ))
            .searchable(
                text: $vm.searchText,
                prompt: Text(
                    appText(
                        "ios.search_chats",
                        languageCode: appLanguage
                    )
                )
            )
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
                            InterstitialAdManager.shared
                                .recordChatOpenAndMaybeShow()
                        }

                    case .sms(let conversation):
                        selectedSMSConversation = conversation
                        showSelectedSMS = true
                        if shouldShowAds {
                            InterstitialAdManager.shared
                                .recordChatOpenAndMaybeShow()
                        }
                    }
                }
                .environmentObject(auth)
                .environmentObject(themeManager)
            }
            .sheet(
                isPresented: $isMatching,
                onDismiss: {
                    SocketManager.shared.leaveRandomQueue()
                }
            ) {
                RandomMatchingView(
                    onCancel: {
                        SocketManager.shared.leaveRandomQueue()
                        isMatching = false
                    }
                )
            }
            .alert(
                appText(
                    "messages.deleteConversationTitle",
                    languageCode: appLanguage
                ),
                isPresented: $showDeleteConfirm
            ) {
                Button(
                    appText(
                        "common.delete",
                        languageCode: appLanguage
                    ),
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
                Button(appText(
                    "button_cancel",
                    languageCode: appLanguage
                ), role: .cancel) {
                    pendingConversation = nil
                }
            } message: {
                Text(
                    appText(
                        "ios.this_will_remove_the_conversation_from_your_list",
                        languageCode: appLanguage
                    )
                )
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

    private func isRandomChatConversation(_ conversation: ConversationDTO) -> Bool {
        if conversation.isRandomChat == true { return true }
        if conversation.randomChat != nil { return true }

        if let id = conversation.id,
        activeRandomRoomIds.contains(id) {
            return true
        }

        return false
    }
    
    private func openConversationFromList(_ conversation: ConversationDTO) {
        selectedRandomSession = nil

        if conversation.isRandomChat == true || conversation.randomChat != nil,
            let randomChat = conversation.randomChat {
            selectedRandomSession = RandomSession(
                roomId: randomChat.chatRoomId,
                myAlias: randomChat.myAlias ?? appText("common.you", languageCode: appLanguage),
                partnerAlias: randomChat.partnerAlias ?? appText("random.stranger", languageCode: appLanguage)
            )
        }

        switch conversation.kind.lowercased() {
        case "chat":
            guard let room = conversation.asChatRoomDTO else { return }
            selectedRoom = room
            showSelectedRoom = true

        case "sms":
            selectedSMSConversation = conversation
            showSelectedSMS = true

        default:
            return
        }

        if shouldShowAds {
            InterstitialAdManager.shared.recordChatOpenAndMaybeShow()
        }
    }

    private func handleMessageFromChats(_ conversation: ConversationDTO) {
        openConversationFromList(conversation)
    }

    private func leaveRandomChatFromList(_ conversation: ConversationDTO) {
        guard isRandomChatConversation(conversation) else { return }

        let roomId =
            conversation.randomChat?.chatRoomId ??
            conversation.id

        if let roomId {
            activeRandomRoomIds.remove(roomId)
        }

        selectedRandomSession = nil
        SocketManager.shared.markRandomMatchCompleted()
        SocketManager.shared.skipRandomChat(roomId: roomId)

        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            await reload()
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
        guard let token = TokenStore.shared.read(), !token.isEmpty else {
            isMatching = false
            return
        }

        isMatching = true

        Task { @MainActor in
            SocketManager.shared.resetRandomQueueState(reason: "starting random chat")

            do {
                try await SocketManager.shared.connectAsync(token: token, timeoutSecs: 12)

                SocketManager.shared.leaveRandomQueue()

                try? await Task.sleep(nanoseconds: 200_000_000)

                SocketManager.shared.joinRandomQueue()
            } catch {
                isMatching = false
                vm.errorText = "Could not connect to Random Chat. Please try again."
                debugLog("[RandomChat][iOS] failed to connect before random join:", error.localizedDescription)
            }
        }
    }

    private func setupRandomMatchListener() {

        // 🔹 MATCH FOUND
        SocketManager.shared.on("random:matched") { data, _ in
            guard let dict = data.first as? [String: Any],
                  let roomId = dict["roomId"] as? Int else { return }

            let myAlias =
                dict["myAlias"] as? String
                ?? appText("common.you", languageCode: appLanguage)

            let partnerAlias =
                dict["partnerAlias"] as? String
                ?? appText("random.stranger", languageCode: appLanguage)

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

        SocketManager.shared.on("random:ended") { data, _ in
            let roomId = (data.first as? [String: Any])?["roomId"] as? Int

            Task { @MainActor in
                isMatching = false
                selectedRandomSession = nil
                SocketManager.shared.markRandomMatchCompleted()

                if let roomId {
                    activeRandomRoomIds.remove(roomId)
                }

                await reload()
            }
        }
    }

    private func handleMatchFound(roomId: Int, myAlias: String, partnerAlias: String) async {
        isMatching = false
        SocketManager.shared.markRandomMatchCompleted()
        activeRandomRoomIds.insert(roomId)

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

            activeRandomRoomIds.insert(roomId)

            selectedRoom = room
            matchedRoom = room

            selectedRandomSession = session

            showSelectedRoom = true
        } catch {
            debugLog("❌ match fetch failed:", error)
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
            debugLog("❌ Failed to open chat from notification:", error)
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

            return appText(
                "messages.conversation",
                languageCode: appLanguage
            )
        }

        return String(
            format: appText(
                "ios.chat_number",
                languageCode: appLanguage
            ),
            item.id?.description
                ?? appText(
                    "ios.draft",
                    languageCode: appLanguage
                )
        )
    }

    private func conversationSubtitle(_ conversation: ConversationDTO) -> String {
        guard let last = conversation.last else {
            return conversation.kind.lowercased() == "sms"
                ? appText(
                    "ios.tap_to_open_sms_thread",
                    languageCode: appLanguage
                )
                : appText(
                    "ios.tap_to_open",
                    languageCode: appLanguage
                )
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
                base = "🎞 \(appText("ios.gif", languageCode: appLanguage))"
            } else if kinds.contains("IMAGE") {
                base = "📷 \(appText("ios.photo", languageCode: appLanguage))"
            } else if kinds.contains("AUDIO") {
                base = "🎤 \(appText("ios.voice_message", languageCode: appLanguage))"
            } else if kinds.contains("VIDEO") {
                base = "🎥 \(appText("ios.video", languageCode: appLanguage))"
            } else if let mediaCount = last.mediaCount, mediaCount > 1 {
                base = "📎 \(appText("ios.attachment", languageCode: appLanguage))"
            } else {
                base = "📎 \(appText("ios.attachment", languageCode: appLanguage))"
            }

            if (conversation.isGroup ?? false),
               let sender = last.senderName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sender.isEmpty {
                return "\(sender): \(base)"
            }

            return base
        }

        return appText("ios.tap_to_open", languageCode: appLanguage)
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

    @AppStorage("chatforia_language") private var appLanguage = "en"

    var body: some View {
        EmptyStateView(
            systemImage: "questionmark.bubble",
            title: appText(
                "ios.unsupported_conversation",
                languageCode: appLanguage
            ),
            subtitle: String(
                format: appText(
                    "ios.kind_format",
                    languageCode: appLanguage
                ),
                conversation.kind
            )
        )
        .navigationTitle(
            appText(
                "messages.conversation",
                languageCode: appLanguage
            )
        )
        .navigationBarTitleDisplayMode(.inline)
    }
}

