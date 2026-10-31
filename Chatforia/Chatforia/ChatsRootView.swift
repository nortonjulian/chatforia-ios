import SwiftUI

struct ChatsRootView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var vm: ChatsViewModel
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    @State private var showingStartChat = false
    @State private var selectedRoom: ChatRoomDTO? = nil
    @State private var showSelectedRoom = false
    @State private var selectedSMSConversation: ConversationDTO? = nil
    @State private var showSelectedSMS = false

    @State private var isEditingConversations = false
    @State private var selectedConversationIDs = Set<String>()
    @State private var pendingBulkDeletion: [ConversationDTO] = []
    @State private var showBulkDeleteConfirm = false
    @State private var isDeletingConversations = false

    @State private var showDeleteConfirm = false
    @State private var pendingConversation: ConversationDTO?

    @State private var isMatching = false
    @State private var randomMatchSucceeded = false
    @State private var matchedRoom: ChatRoomDTO?
    @State private var selectedRandomSession: RandomSession? = nil
    @State private var didSetupRandomMatchListener = false
    @State private var showRiaChat = false
    @State private var activeRandomRoomIds = Set<Int>()
    @State private var activeRandomSessions: [Int: RandomSession] = [:]
    @State private var showPeerEndedAlert = false

    @StateObject private var settingsVM = SettingsViewModel()

    private var shouldShowAds: Bool {
        resolvedAdsEnabled(
            backendAdsEnabled:
                subscriptionManager.backendEntitlements?.entitlements.adsEnabled,
            isPaid: auth.isPaid
        )
    }

    // Unlike SwiftUI's navigation search drawer, this stays visible when
    // the user switches tabs or scrolls the conversation list.
    private var pinnedSearch: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(
                appText("ios.search_chats", languageCode: appLanguage),
                text: $vm.searchText
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .accessibilityLabel(appText("ios.search_chats", languageCode: appLanguage))

            if !vm.searchText.isEmpty {
                Button {
                    vm.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear chat search")
            }
        }
        .font(.body)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(themeManager.palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.screenBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    pinnedSearch
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
                                        if isEditingConversations {
                                            if selectedConversationIDs.contains(conversation.uniqueId) {
                                                selectedConversationIDs.remove(conversation.uniqueId)
                                            } else {
                                                selectedConversationIDs.insert(conversation.uniqueId)
                                            }
                                        } else {
                                            openConversationFromList(conversation)
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            if isEditingConversations {
                                                Image(
                                                    systemName: selectedConversationIDs.contains(conversation.uniqueId)
                                                        ? "checkmark.circle.fill"
                                                        : "circle"
                                                )
                                                .font(.title2)
                                                .foregroundStyle(themeManager.palette.accent)
                                                .accessibilityHidden(true)
                                            }

                                            ChatListRowView(
                                                title: conversationTitle(conversation),
                                                subtitle: conversationSubtitle(conversation),
                                                timestamp: conversationTimestamp(conversation),
                                                unreadCount: conversation.unreadCount ?? 0,
                                                avatarUsers: conversation.avatarUsers ?? [],
                                                isPinned: false,
                                                isSMS: conversation.kind.lowercased() == "sms"
                                            )
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(
                                        selectedConversationIDs.contains(conversation.uniqueId)
                                            ? [.isSelected] : []
                                    )
                                    .disabled(isDeletingConversations)
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
                                    .swipeActions(
                                        edge: .trailing,
                                        allowsFullSwipe: false
                                    ) {
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

                    if isEditingConversations {
                        HStack {
                            Spacer()
                            Button(role: .destructive) {
                                pendingBulkDeletion = vm.conversations.filter {
                                    selectedConversationIDs.contains($0.uniqueId)
                                }
                                showBulkDeleteConfirm = !pendingBulkDeletion.isEmpty
                            } label: {
                                Text("Delete (\(selectedConversationIDs.count))")
                            }
                            .disabled(
                                selectedConversationIDs.isEmpty || isDeletingConversations
                            )
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(themeManager.palette.screenBackground)
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
                        randomSession: selectedRandomSession,
                        onRandomLeave: selectedRandomSession == nil ? nil : {
                            guard let session = selectedRandomSession else { return }
                            SocketManager.shared.skipRandomChat(roomId: session.roomId)
                            SocketManager.shared.markRandomMatchCompleted()
                            activeRandomRoomIds.remove(session.roomId)
                            activeRandomSessions.removeValue(forKey: session.roomId)
                            selectedRandomSession = nil
                            showSelectedRoom = false
                            Task { await reload() }
                        }
                    )
                    .id(room.id)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isEditingConversations.toggle()
                        selectedConversationIDs.removeAll()
                    } label: {
                        Text(isEditingConversations ? "Done" : "Edit")
                    }
                    .disabled(isDeletingConversations)
                }

                if isEditingConversations {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            let visibleIDs = Set(vm.filteredConversations.map(\.uniqueId))
                            if !visibleIDs.isEmpty &&
                                visibleIDs.isSubset(of: selectedConversationIDs) {
                                selectedConversationIDs.subtract(visibleIDs)
                            } else {
                                selectedConversationIDs.formUnion(visibleIDs)
                            }
                        } label: {
                            let visibleIDs = Set(vm.filteredConversations.map(\.uniqueId))
                            Text(
                                !visibleIDs.isEmpty &&
                                visibleIDs.isSubset(of: selectedConversationIDs)
                                    ? "Deselect All" : "Select All"
                            )
                        }
                        .disabled(isDeletingConversations || vm.filteredConversations.isEmpty)
                    }

                } else if dynamicTypeSize.isAccessibilitySize {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("New chat", systemImage: "plus") {
                                showingStartChat = true
                            }
                            Button("Refresh", systemImage: "arrow.clockwise") {
                                Task { await reload() }
                            }
                            Button("Ria", systemImage: "sparkles") {
                                showRiaChat = true
                            }
                            Button("Random Chat", systemImage: "shuffle") {
                                startRandomChat()
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(themeManager.palette.accent)
                        }
                        .accessibilityLabel("Chat actions")
                    }
                } else {
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
            }
            .onChange(of: vm.conversations.map(\.uniqueId)) { _, currentIDs in
                selectedConversationIDs.formIntersection(Set(currentIDs))
            }
            .confirmationDialog(
                "Delete \(pendingBulkDeletion.count) conversations?",
                isPresented: $showBulkDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    let conversationsToDelete = pendingBulkDeletion
                    pendingBulkDeletion = []
                    isDeletingConversations = true

                    Task { @MainActor in
                        let token = TokenStore.shared.read()
                        var failedCount = 0
                        var firstError: String?

                        for conversation in conversationsToDelete {
                            await vm.deleteConversation(conversation, token: token)

                            if vm.conversations.contains(where: {
                                $0.uniqueId == conversation.uniqueId
                            }) {
                                failedCount += 1
                                if firstError == nil {
                                    firstError = vm.errorText
                                }
                            } else {
                                selectedConversationIDs.remove(conversation.uniqueId)
                            }
                        }

                        if failedCount > 0 {
                            vm.errorText = "\(failedCount) conversations could not be deleted. " +
                                (firstError ?? "Please try again.")
                        } else {
                            isEditingConversations = false
                            selectedConversationIDs.removeAll()
                        }

                        isDeletingConversations = false
                    }
                }

                Button("Cancel", role: .cancel) {
                    pendingBulkDeletion = []
                }
            } message: {
                Text("This will remove the selected conversations from your list.")
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
            .alert("Random Chat ended", isPresented: $showPeerEndedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your partner left the Random Chat.")
            }
            .sheet(
                isPresented: $isMatching,
                onDismiss: {
                    // Dismissing the matching sheet after a successful match must
                    // not send random:leave: the server treats it as ending the room.
                    if !randomMatchSucceeded {
                        SocketManager.shared.leaveRandomQueue()
                    }
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

                await vm.loadInitialConversationsIfNeeded(
                    token: auth.currentToken
                )
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
            .onReceive(
                NotificationCoordinator.shared.$pendingSMSThreadId
            ) { threadId in
                guard let threadId else { return }

                Task {
                    await openSMSFromNotification(threadId: threadId)
                }
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

    private func openSMSFromNotification(threadId: Int) async {
        let token = TokenStore.shared.read()
        await vm.loadConversations(token: token)

        guard let conversation = vm.conversations.first(where: {
            $0.kind.lowercased() == "sms" &&
            $0.id == threadId
        }) else {
            return
        }

        selectedRandomSession = nil
        selectedSMSConversation = conversation
        showSelectedSMS = true

        NotificationCoordinator.shared.pendingSMSThreadId = nil
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
        selectedRandomSession = conversation.id.flatMap { activeRandomSessions[$0] }

        if selectedRandomSession == nil,
            (conversation.isRandomChat == true || conversation.randomChat != nil),
            let randomChat = conversation.randomChat,
            randomChat.endedAt == nil,
            randomChat.isUnlocked != true {
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
            activeRandomSessions.removeValue(forKey: roomId)
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
        randomMatchSucceeded = false
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
            guard let roomId = (data.first as? [String: Any])?["roomId"] as? Int else { return }

            Task { @MainActor in
                let wasCurrentSession = selectedRandomSession?.roomId == roomId
                activeRandomRoomIds.remove(roomId)
                activeRandomSessions.removeValue(forKey: roomId)

                if wasCurrentSession {
                    selectedRandomSession = nil
                    showSelectedRoom = false
                    // Peer termination is navigation, not permission to
                    // expose the ordinary conversation's call/video controls.
                    showPeerEndedAlert = true
                }

                await reload()
            }
        }
    }

    private func handleMatchFound(roomId: Int, myAlias: String, partnerAlias: String) async {
        randomMatchSucceeded = true
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
            activeRandomSessions[roomId] = session

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

        let rawText = last.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Normalize only the legacy media marker, never brackets in real text
        // or participant names. Keep the stored message and preview unchanged.
        let voiceNoteLabel = appText("sms.voiceNote", languageCode: appLanguage)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mediaMarkers: Set<String> = ["[image]", "[video]", "[audio]", "[file]", "[gif]"]
        // Older Chatforia messages may have a literal attachment marker
        // without preview media metadata. Keep ordinary text intact.
        let isLegacyChatforiaMarker = conversation.kind.lowercased() != "sms"
            && mediaMarkers.contains(rawText.lowercased())
        let mediaPlaceholder = mediaMarkers.contains(rawText.lowercased())
            && (last.hasMedia == true || isLegacyChatforiaMarker)
        let text = rawText.caseInsensitiveCompare("[voice note]") == .orderedSame
            ? (voiceNoteLabel.isEmpty || voiceNoteLabel == "sms.voiceNote" ? "Voice note" : voiceNoteLabel)
            : (mediaPlaceholder ? "" : rawText)

        if !text.isEmpty {
            if (conversation.isGroup ?? false),
               let sender = last.senderName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sender.isEmpty {
                return "\(sender): \(text)"
            }
            return text
        }

        if last.hasMedia == true || isLegacyChatforiaMarker {
            var kinds = (last.mediaKinds ?? []).map { $0.uppercased() }
            if kinds.isEmpty && isLegacyChatforiaMarker {
                switch rawText.lowercased() {
                case "[image]": kinds = ["IMAGE"]
                case "[video]": kinds = ["VIDEO"]
                case "[audio]": kinds = ["AUDIO"]
                case "[gif]": kinds = ["GIF"]
                default: kinds = ["FILE"]
                }
            }
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

