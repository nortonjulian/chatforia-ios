import SwiftUI
import PhotosUI

struct ChatThreadView: View {
    let room: ChatRoomDTO
    let randomSession: RandomSession?

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var themeManager: ThemeManager

    @StateObject private var vm = ChatThreadViewModel()
    @StateObject private var riaVM = RiaViewModel()
    @StateObject private var settingsVM = SettingsViewModel()

    @Environment(\.dismiss) private var dismissView
    @Environment(\.scenePhase) private var scenePhase

    @State private var draft = ""
    @State private var lastMessageId: Int? = nil

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var isPreparingImageSend = false
    @State private var showPhotoPicker = false

    @State private var reportingMessage: MessageDTO? = nil
    @State private var reportReason: ReportReason = .harassment
    @State private var reportContextCount: Int = 10
    @State private var reportDetails: String = ""
    @State private var blockAfterReport: Bool = true

    @State private var editingMessage: MessageDTO? = nil
    @State private var editDraft: String = ""

    @State private var confirmDeleteMessage: MessageDTO? = nil
    @State private var deletingMessage: MessageDTO? = nil

    @State private var pendingEditMessage: MessageDTO? = nil
    @State private var pendingDeleteMessage: MessageDTO? = nil

    @State private var showDeleteConversationConfirm = false
    @State private var showingRewriteSheet = false

    var body: some View {
        mainContent
            .sheet(isPresented: $showingRewriteSheet) {
                RiaRewriteSheet(
                    draft: draft,
                    isLoading: riaVM.isLoadingRewrite,
                    options: riaVM.rewriteOptions,
                    onToneTap: { tone in
                        Task {
                            await riaVM.rewrite(
                                token: auth.currentToken,
                                text: draft,
                                tone: tone,
                                filterProfanity: settingsVM.maskAIProfanity
                            )
                        }
                    },
                    onSelectRewrite: { rewritten in
                        draft = rewritten
                    }
                )
                .environmentObject(themeManager)
            }
    }
}

extension ChatThreadView {
    private var mainContent: some View {
        baseContent
            .navigationTitle(roomDisplayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task(id: room.id) {
                await onTaskLoad()
            }
            .onDisappear {
                onDisappearView()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            .onReceive(SocketManager.shared.$isConnected) { connected in
                handleSocketConnectionChange(connected)
            }
            .onChange(of: pendingEditMessage?.id) { _, _ in
                guard let msg = pendingEditMessage else { return }
                print("🟣 presenting edit sheet for \(msg.id)")

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    editDraft = bestEditableText(for: msg)
                    editingMessage = msg
                    pendingEditMessage = nil
                }
            }
            .onChange(of: pendingDeleteMessage?.id) { _, _ in
                guard let msg = pendingDeleteMessage else { return }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    deletingMessage = msg
                    pendingDeleteMessage = nil
                }
            }
            .onChange(of: vm.messages.last?.id) { _, _ in
                refreshRiaSuggestions()
            }
            .modifier(DeleteConversationDialogModifier(
                showDeleteConversationConfirm: $showDeleteConversationConfirm,
                onDeleteConversation: {
                    Task { await deleteConversation() }
                }
            ))
            .modifier(DeleteConfirmDialogModifier(
                confirmDeleteMessage: $confirmDeleteMessage,
                pendingDeleteMessage: $pendingDeleteMessage
            ))
            .modifier(DeleteOptionsDialogModifier(
                deletingMessage: $deletingMessage,
                reportingMessage: $reportingMessage,
                currentUserId: currentUserId,
                deliveryState: deliveryState(for:),
                onDelete: { msg, deleteForEveryone in
                    let ok = await vm.deleteMessage(
                        messageId: msg.id,
                        token: TokenStore.shared.read(),
                        deleteForEveryone: deleteForEveryone
                    )
                    if ok {
                        deletingMessage = nil
                    }
                }
            ))
            .sheet(item: $reportingMessage) { msg in
                reportSheet(for: msg)
            }
            .sheet(item: $editingMessage) { msg in
                editSheet(for: msg)
            }
    }

    private func reportSheet(for msg: MessageDTO) -> some View {
        ReportMessageSheet(
            targetMessage: msg,
            senderName: displayName(for: msg),
            previewText: bestPlaintextForReport(msg),
            isSubmitting: vm.isSubmittingReport,
            errorText: vm.reportErrorText,
            reason: $reportReason,
            contextCount: $reportContextCount,
            details: $reportDetails,
            blockAfterReport: $blockAfterReport,
            onCancel: {
                reportingMessage = nil
                vm.reportErrorText = nil
            },
            onSubmit: {
                Task {
                    let ok = await vm.submitReport(
                        targetMessage: msg,
                        roomId: room.id,
                        reason: reportReason,
                        details: reportDetails,
                        contextCount: reportContextCount,
                        blockAfterReport: blockAfterReport,
                        token: TokenStore.shared.read()
                    )
                    if ok {
                        reportingMessage = nil
                        reportDetails = ""
                        reportReason = .harassment
                        reportContextCount = 10
                        blockAfterReport = true
                    }
                }
            }
        )
    }

    private func editSheet(for msg: MessageDTO) -> some View {
        let trimmed = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = bestEditableText(for: msg).trimmingCharacters(in: .whitespacesAndNewlines)

        return NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Update your message")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.palette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(themeManager.palette.screenBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(themeManager.palette.border.opacity(0.9), lineWidth: 1)
                        )

                    TextEditor(text: $editDraft)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .padding(14)
                        .frame(minHeight: 160, maxHeight: 240)
                        .foregroundStyle(themeManager.palette.primaryText)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(themeManager.palette.screenBackground.ignoresSafeArea())
            .navigationTitle("Edit message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editingMessage = nil
                        editDraft = ""
                    }
                    .foregroundStyle(themeManager.palette.secondaryText)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let ok = await vm.editMessage(
                                messageId: msg.id,
                                newText: trimmed,
                                token: TokenStore.shared.read()
                            )

                            if ok {
                                editingMessage = nil
                                editDraft = ""
                            }
                        }
                    }
                    .disabled(trimmed.isEmpty || trimmed == original)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

extension ChatThreadView {
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    Task {
                        let ok = await vm.archiveConversation(
                            conversationId: room.id,
                            kind: "chat",
                            token: TokenStore.shared.read()
                        )
                        if ok {
                            dismissView()
                        }
                    }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }

                Button(role: .destructive) {
                    showDeleteConversationConfirm = true
                } label: {
                    Label("Delete conversation", systemImage: "trash")
                }

                Divider()

                Button {
                    Task { await reload() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func deleteConversation() async {
        let success = await vm.deleteConversation(
            conversationId: room.id,
            kind: "chat",
            token: TokenStore.shared.read()
        )

        if success {
            dismissView()
        }
    }

    private var baseContent: some View {
        VStack(spacing: 0) {
            errorBanner

            if let session = vm.randomSession, !session.isFriendUnlocked {
                matchedHeaderCard(session: session)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }

            messagesSection
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            typingBanner

            composer
        }
        .background(themeManager.palette.screenBackground.ignoresSafeArea())
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
            } else if let aiReason = riaVM.aiDisabledReason, !aiReason.isEmpty {
                Text(aiReason)
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(themeManager.palette.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.errorText)
        .animation(.easeInOut(duration: 0.2), value: riaVM.aiDisabledReason)
    }

    private func matchedHeaderCard(session: RandomSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(themeManager.palette.border)
                        .frame(width: 44, height: 44)

                    Image(systemName: "person.2.wave.2.fill")
                        .foregroundStyle(themeManager.palette.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("You matched with \(session.partnerAlias)")
                        .font(.headline)
                        .foregroundStyle(themeManager.palette.primaryText)

                    if session.iRequestedFriend && !session.partnerRequestedFriend {
                        Text("Friend request sent. Waiting for them to accept.")
                            .font(.footnote)
                            .foregroundStyle(themeManager.palette.secondaryText)
                    } else {
                        Text("You’re anonymous until both people choose Add Friend.")
                            .font(.footnote)
                            .foregroundStyle(themeManager.palette.secondaryText)
                    }
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    Task { await vm.requestAddFriend() }
                } label: {
                    Text(session.iRequestedFriend ? "Requested" : "Add Friend")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.iRequestedFriend)

                Button {
                    Task {
                        await vm.nextPerson()
                        dismissView()
                    }
                } label: {
                    Text("Next Person")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(themeManager.palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(themeManager.palette.border.opacity(0.8), lineWidth: 1)
        )
    }

    private var messagesSection: some View {
        let retryHandler: (MessageDTO) -> Void = { msg in
            guard let cid = msg.clientMessageId, !cid.isEmpty else { return }
            SendQueueManager.shared.retryJob(clientMessageId: cid)
        }

        let editHandler: (MessageDTO) -> Void = { msg in
            guard msg.id > 0 else { return }
            print("🟢 editHandler received \(msg.id)")
            pendingEditMessage = msg
        }

        let deleteHandler: (MessageDTO) -> Void = { msg in
            print("🟢 deleteHandler received \(msg.id)")

            if msg.id <= 0 {
                Task {
                    _ = await vm.deleteMessage(
                        messageId: msg.id,
                        token: TokenStore.shared.read(),
                        deleteForEveryone: false
                    )
                }
                return
            }

            confirmDeleteMessage = msg
        }

        let reportHandler: (MessageDTO) -> Void = { msg in
            reportingMessage = msg
            reportReason = .harassment
            reportContextCount = 10
            reportDetails = ""
            blockAfterReport = true
            vm.reportErrorText = nil
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
                    onReport: reportHandler,
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
                    .background(themeManager.palette.screenBackground)
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.typingUsernames)
    }

    private func riaContextMessages(from messages: [MessageDTO], currentUserId: Int?) -> [RiaContextMessageDTO] {
        let recent = messages.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
        .suffix(8)

        return recent.compactMap { msg in
            let text =
                DecryptedMessageTextStore.shared.text(for: msg.id)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? msg.translatedForMe?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? msg.rawContent?.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let text, !text.isEmpty else { return nil }

            let role = (msg.sender.id == currentUserId) ? "user" : "assistant"
            return RiaContextMessageDTO(role: role, content: text)
        }
    }

    private func refreshRiaSuggestions() {
        guard let token = auth.currentToken else { return }

        riaVM.loadSuggestions(
            token: token,
            enabled: settingsVM.enableSmartReplies,
            filterProfanity: settingsVM.maskAIProfanity,
            draft: draft,
            messages: riaContextMessages(from: vm.messages, currentUserId: auth.currentUser?.id)
        )
    }

    private var composer: some View {
        MessageComposerView(
            draft: $draft,
            isSending: isBusySending,
            onDraftChanged: {
                vm.handleInputChanged(roomId: room.id)
                refreshRiaSuggestions()
            },
            onAttachmentTap: {
                showPhotoPicker = true
            },
            onSend: {
                Task { await send() }
            },
            suggestions: riaVM.suggestions,
            isLoadingSuggestions: riaVM.isLoadingSuggestions,
            onSuggestionTap: { suggestion in
                draft = suggestion
                vm.handleInputChanged(roomId: room.id)
            },
            onRewriteTap: {
                showingRewriteSheet = true
            }
        )
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }

            Task {
                await loadAndSendSelectedPhoto(from: newItem)
            }
        }
    }

    private func bestPlaintextForReport(_ msg: MessageDTO) -> String {
        if let translated = msg.translatedForMe,
           !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return translated
        }

        if let raw = msg.rawContent,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw
        }

        return ""
    }

    private func loadAndSendSelectedPhoto(from item: PhotosPickerItem) async {
        guard !isPreparingImageSend else { return }

        isPreparingImageSend = true
        defer {
            isPreparingImageSend = false
            selectedPhotoItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                await MainActor.run {
                    vm.errorText = "Couldn’t load the selected image."
                }
                return
            }

            guard let senderId = currentUserId else {
                await MainActor.run {
                    vm.errorText = "Missing current user identity."
                }
                return
            }

            let token = TokenStore.shared.read()

            let didQueue = await vm.sendImageMessage(
                roomId: room.id,
                token: token,
                imageData: data,
                caption: nil,
                senderId: senderId,
                senderUsername: currentUsername,
                senderPublicKey: nil
            )

            if !didQueue {
                print("⚠️ Image message was not queued.")
            }
        } catch {
            await MainActor.run {
                vm.errorText = "Failed to prepare image."
            }
            print("❌ loadAndSendSelectedPhoto failed:", error)
        }
    }

    private func bestEditableText(for msg: MessageDTO) -> String {
        if let raw = msg.rawContent,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw
        }

        if let translated = msg.translatedForMe,
           !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return translated
        }

        if let decrypted = DecryptedMessageTextStore.shared.text(for: msg.id),
           !decrypted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return decrypted
        }

        return ""
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
        if let session = vm.randomSession, !session.isFriendUnlocked {
            return session.partnerAlias
        }

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

    private func displayName(for msg: MessageDTO) -> String {
        guard let session = vm.randomSession, !session.isFriendUnlocked else {
            return msg.sender.username ?? "User"
        }

        if msg.sender.id == currentUserId {
            return session.myAlias
        } else {
            return session.partnerAlias
        }
    }

    private func onTaskLoad() async {
        if let user = auth.currentUser {
            settingsVM.load(from: user)
        }
        settingsVM.loadLocalAISettings()

        vm.configureRoom(roomId: room.id)

        if let session = randomSession {
            vm.configureRandomSession(
                roomId: session.roomId,
                myAlias: session.myAlias,
                partnerAlias: session.partnerAlias
            )
        }

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
            self.refreshRiaSuggestions()
        }
    }

    private func onDisappearView() {
        vm.stopTypingNow(roomId: room.id)
        vm.stopSocket()
        vm.stopExpiryLoop()
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        if newPhase == .active {
            Task {
                await vm.resyncIfNeeded(token: TokenStore.shared.read())
                if let user = auth.currentUser {
                    settingsVM.load(from: user)
                }
                settingsVM.loadLocalAISettings()
                refreshRiaSuggestions()
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
            refreshRiaSuggestions()
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
        guard let senderId = currentUserId else {
            vm.errorText = "Missing current user identity."
            return
        }

        let token = TokenStore.shared.read()
        let text = draft

        let didQueue = await vm.sendMessage(
            roomId: room.id,
            token: token,
            text: text,
            senderId: senderId,
            senderUsername: currentUsername,
            senderPublicKey: nil
        )

        if didQueue {
            draft = ""
            riaVM.clearSuggestions()
            vm.stopTypingNow(roomId: room.id)
        }
    }

    private func typingIndicatorText(_ names: [String]) -> String {
        if let session = vm.randomSession, !session.isFriendUnlocked {
            if names.isEmpty { return "" }
            if names.count == 1 { return "\(session.partnerAlias) is typing…" }
            return "People are typing…"
        }

        if names.count == 1 { return "\(names[0]) is typing…" }
        if names.count == 2 { return "\(names[0]) and \(names[1]) are typing…" }
        return "\(names.count) people are typing…"
    }

    private var isBusySending: Bool {
        isPreparingImageSend || vm.isSendingImage
    }

    private func deliveryState(for msg: MessageDTO) -> DeliveryState? {
        guard let clientMessageId = msg.clientMessageId,
              !clientMessageId.isEmpty else { return nil }

        return MessageStore.shared.getDeliveryState(clientMessageId: clientMessageId)
    }
}

// MARK: - Dialog Modifiers

private struct DeleteConversationDialogModifier: ViewModifier {
    @Binding var showDeleteConversationConfirm: Bool
    let onDeleteConversation: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete conversation?",
            isPresented: $showDeleteConversationConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete conversation", role: .destructive) {
                onDeleteConversation()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct DeleteConfirmDialogModifier: ViewModifier {
    @Binding var confirmDeleteMessage: MessageDTO?
    @Binding var pendingDeleteMessage: MessageDTO?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete message?",
            isPresented: Binding(
                get: { confirmDeleteMessage != nil },
                set: { if !$0 { confirmDeleteMessage = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let msg = confirmDeleteMessage {
                Button("Delete", role: .destructive) {
                    pendingDeleteMessage = msg
                    confirmDeleteMessage = nil
                }
            }

            Button("Cancel", role: .cancel) {
                confirmDeleteMessage = nil
            }
        }
    }
}

private struct DeleteOptionsDialogModifier: ViewModifier {
    @Binding var deletingMessage: MessageDTO?
    @Binding var reportingMessage: MessageDTO?

    let currentUserId: Int?
    let deliveryState: (MessageDTO) -> DeliveryState?
    let onDelete: (MessageDTO, Bool) async -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete options",
            isPresented: Binding(
                get: { deletingMessage != nil },
                set: { if !$0 { deletingMessage = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let msg = deletingMessage {
                let isMine = msg.sender.id == currentUserId || (msg.id < 0 && msg.clientMessageId != nil)
                let age = Date().timeIntervalSince(msg.createdAt)
                let withinWindow = age <= 15 * 60
                let isServerMessage = msg.id > 0
                let isSending = deliveryState(msg) == .pending || deliveryState(msg) == .sending

                if isMine {
                    if isServerMessage && !isSending && withinWindow {
                        Button("Delete for everyone", role: .destructive) {
                            Task {
                                await onDelete(msg, true)
                            }
                        }
                    }

                    Button("Delete for me", role: .destructive) {
                        Task {
                            await onDelete(msg, false)
                        }
                    }
                } else {
                    Button("Delete for me", role: .destructive) {
                        Task {
                            await onDelete(msg, false)
                        }
                    }

                    Button("Report") {
                        reportingMessage = msg
                        deletingMessage = nil
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                deletingMessage = nil
            }
        }
    }
}
