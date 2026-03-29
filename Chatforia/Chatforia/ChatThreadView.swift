import SwiftUI
import PhotosUI
import UIKit

struct ChatThreadView: View {
    let room: ChatRoomDTO
    let randomSession: RandomSession?

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var callManager: CallManager

    @StateObject private var vm = ChatThreadViewModel()
    @StateObject private var riaVM = RiaViewModel()
    @StateObject private var settingsVM = SettingsViewModel()

    @Environment(\.dismiss) private var dismissView
    @Environment(\.scenePhase) private var scenePhase

    @State private var draft = ""
    @State private var lastMessageId: Int? = nil

    @State private var selectedPhotoItem: PhotosPickerItem?
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

    @State private var pendingGIF: URL? = nil

    @State private var isRecordingVoice = false
    @State private var voiceDraft: VoiceNoteDraft? = nil
    @State private var isPlayingVoiceDraft = false
    @State private var recordingStartedAt: Date? = nil
    @State private var showMicSettingsAlert = false

    @State private var showAttachmentSheet = false
    @State private var showGIFPicker = false

    private let recorder = AudioRecorderService()

    var body: some View {
        mainContent
            .sheet(isPresented: $showingRewriteSheet) {
                RiaRewriteSheet(
                    draft: draft,
                    isLoading: riaVM.isLoadingRewrite,
                    options: riaVM.rewriteOptions,
                    errorText: riaVM.lastError,
                    disabledReason: riaVM.aiDisabledReason,
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
            .modifier(
                DeleteConversationDialogModifier(
                    showDeleteConversationConfirm: $showDeleteConversationConfirm,
                    onDeleteConversation: {
                        Task { await deleteConversation() }
                    }
                )
            )
            .modifier(
                DeleteConfirmDialogModifier(
                    confirmDeleteMessage: $confirmDeleteMessage,
                    pendingDeleteMessage: $pendingDeleteMessage
                )
            )
            .modifier(
                DeleteOptionsDialogModifier(
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
                )
            )
            .sheet(item: $reportingMessage) { msg in
                reportSheet(for: msg)
            }
            .sheet(item: $editingMessage) { msg in
                editSheet(for: msg)
            }
            .alert("Microphone Access Needed", isPresented: $showMicSettingsAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } message: {
                Text("Enable microphone access in Settings to record and send voice notes.")
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
            Button {
                startCall()
            } label: {
                Image(systemName: "phone.fill")
            }
            
            Button {
                startVideoCall()
            } label: {
                Image(systemName: "video.fill")
            }
            
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
    
    private var recordingElapsedSec: Double {
        guard let recordingStartedAt else { return 0 }
        return Date().timeIntervalSince(recordingStartedAt)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let mins = total / 60
        let secs = total % 60
        return "\(mins):" + String(format: "%02d", secs)
    }
    
    private func startVoiceRecording() {
        Task {
            do {
                try await recorder.start()
                
                await MainActor.run {
                    recordingStartedAt = Date()
                    isRecordingVoice = true
                    voiceDraft = nil
                    isPlayingVoiceDraft = false
                    vm.errorText = nil
                }
            } catch {
                await MainActor.run {
                    isRecordingVoice = false
                    recordingStartedAt = nil
                    voiceDraft = nil
                    isPlayingVoiceDraft = false
                    
                    let nsError = error as NSError
                    if nsError.code == 401 {
                        vm.errorText = "Microphone access is required to record a voice note."
                        showMicSettingsAlert = true
                    } else {
                        vm.errorText = "Couldn’t start recording."
                    }
                    
                    print("❌ startVoiceRecording failed:", error)
                }
            }
        }
    }
    
    private func stopVoiceRecording() {
        if let draft = recorder.stop() {
            voiceDraft = draft
        } else {
            vm.errorText = "Couldn’t finish recording."
        }
        
        recordingStartedAt = nil
        isRecordingVoice = false
    }
    
    private func cancelVoiceRecording() {
        recorder.cancel()
        recordingStartedAt = nil
        isRecordingVoice = false
    }
    
    private func cancelVoiceDraft() {
        if let voiceDraft {
            try? FileManager.default.removeItem(at: voiceDraft.fileURL)
        }
        self.voiceDraft = nil
        isPlayingVoiceDraft = false
    }
    
    private func toggleVoiceDraftPreviewPlayback() {
        isPlayingVoiceDraft.toggle()
    }
    
    private func sendVoiceDraft() async {
        guard let voiceDraft, let senderId = currentUserId else { return }
        
        let token = TokenStore.shared.read()
        
        let didSend = await vm.sendAudioMessage(
            roomId: room.id,
            token: token,
            fileURL: voiceDraft.fileURL,
            durationSec: voiceDraft.durationSec,
            senderId: senderId,
            senderUsername: currentUsername,
            senderPublicKey: nil
        )
        
        if didSend {
            try? FileManager.default.removeItem(at: voiceDraft.fileURL)
            self.voiceDraft = nil
            isPlayingVoiceDraft = false
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
            pendingEditMessage = msg
        }
        
        let deleteHandler: (MessageDTO) -> Void = { msg in
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
        guard settingsVM.enableSmartReplies else {
            riaVM.clearSuggestions()
            return
        }
        
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
        VStack(spacing: 8) {
            if let gifURL = pendingGIF {
                ZStack(alignment: .topTrailing) {
                    GIFWebView(url: gifURL)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    
                    Button {
                        pendingGIF = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .offset(x: 6, y: -6)
                }
                .padding(.horizontal, 12)
            }
            
            MessageComposerView(
                draft: $draft,
                isSending: isBusySending,
                isSendingVoice: isSendingVoice,
                onDraftChanged: {
                    vm.handleInputChanged(roomId: room.id)
                    refreshRiaSuggestions()
                },
                onAttachmentTap: {
                    showAttachmentSheet = true
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
                },
                isRecordingVoice: isRecordingVoice,
                recordingDurationText: formatDuration(recordingElapsedSec),
                voiceDraftDurationText: voiceDraft.map { formatDuration($0.durationSec) },
                onMicTap: {
                    startVoiceRecording()
                },
                onStopRecordingTap: {
                    stopVoiceRecording()
                },
                onCancelRecordingTap: {
                    cancelVoiceRecording()
                },
                onCancelVoiceDraftTap: {
                    cancelVoiceDraft()
                },
                onSendVoiceDraftTap: {
                    Task { await sendVoiceDraft() }
                },
                onPlayVoiceDraftTap: {
                    toggleVoiceDraftPreviewPlayback()
                },
                isPlayingVoiceDraft: isPlayingVoiceDraft,
                hasVoiceDraft: voiceDraft != nil,
                hasPendingAttachment: pendingGIF != nil
            )
            .environmentObject(settingsVM)
            .confirmationDialog("Add Attachment", isPresented: $showAttachmentSheet) {
                Button("Photo") {
                    showPhotoPicker = true
                }
                
                Button("GIF") {
                    showGIFPicker = true
                }
                
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            )
            .sheet(isPresented: $showGIFPicker) {
                GIFPickerView { gifURL in
                    pendingGIF = gifURL
                    showGIFPicker = false
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                
                Task {
                    await loadAndSendSelectedPhoto(from: newItem)
                }
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
    
    private func startCall() {
        if let phone = room.phone?.trimmingCharacters(in: .whitespacesAndNewlines),
           !phone.isEmpty {
            callManager.startCall(
                to: .phoneNumber(phone, displayName: roomDisplayTitle),
                auth: auth
            )
            return
        }
        
        if let other = room.participants?.first(where: { $0.id != currentUserId }) {
            callManager.startCall(
                to: .appUser(userId: other.id, username: other.username),
                auth: auth
            )
            return
        }
        
        vm.errorText = "Could not determine call destination."
    }
    
    private func startVideoCall() {
        if let phone = room.phone?.trimmingCharacters(in: .whitespacesAndNewlines),
           !phone.isEmpty {
            vm.errorText = "Video calls are only available for Chatforia users."
            return
        }
        
        if room.isGroup == true {
            callManager.startGroupVideoCall(
                roomId: room.id,
                displayName: roomDisplayTitle,
                auth: auth
            )
            return
        }
        
        if let other = room.participants?.first(where: { $0.id != currentUserId }) {
            callManager.startVideoCall(
                to: .appUser(userId: other.id, username: other.username),
                auth: auth
            )
            return
        }
        
        vm.errorText = "Could not determine video call destination."
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
            vm.configureCurrentUser(
                id: user.id,
                username: user.username,
                publicKey: user.publicKey
            )
        }
        
        settingsVM.loadLocalAISettings()
        
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
        vm.stopSocket(roomId: room.id)
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
        
        if let gifURL = pendingGIF {
            do {
                let (data, response) = try await URLSession.shared.data(from: gifURL)
                
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      !data.isEmpty else {
                    vm.errorText = "Failed to load GIF."
                    return
                }
                
                let didSend = await vm.sendGIFMessage(
                    roomId: room.id,
                    token: token,
                    gifData: data,
                    caption: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft,
                    senderId: senderId,
                    senderUsername: currentUsername,
                    senderPublicKey: nil
                )
                
                if didSend {
                    draft = ""
                    pendingGIF = nil
                    riaVM.clearSuggestions()
                    vm.stopTypingNow(roomId: room.id)
                }
            } catch {
                vm.errorText = "Failed to load GIF."
                print("❌ GIF send failed:", error)
            }
            
            return
        }
        
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
        isPreparingImageSend || vm.isSendingImage || vm.isSendingAudio
    }
    
    private var isSendingVoice: Bool {
        vm.isSendingAudio
    }
    
    private func deliveryState(for msg: MessageDTO) -> DeliveryState? {
        guard let clientMessageId = msg.clientMessageId,
              !clientMessageId.isEmpty else { return nil }
        
        // Temporary compile-safe fallback until MessageStore exposes
        // a readable delivery-state getter with the exact project name.
        _ = clientMessageId
        return nil
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
                "Message options",
                isPresented: Binding(
                    get: { deletingMessage != nil },
                    set: { if !$0 { deletingMessage = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let msg = deletingMessage {
                    let isMine = (msg.sender.id == currentUserId)
                    let canDeleteForEveryone = isMine && msg.id > 0
                    let isPending = (deliveryState(msg) == .sending)
                    
                    if canDeleteForEveryone && !isPending {
                        Button("Delete for everyone", role: .destructive) {
                            Task { await onDelete(msg, true) }
                        }
                    }
                    
                    Button("Delete for me", role: .destructive) {
                        Task { await onDelete(msg, false) }
                    }
                    
                    if !isMine {
                        Button("Report message") {
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
}

    struct EmptyAPIResponse: Decodable {}
    
    extension ChatThreadViewModel {
        func startSocket(roomId: Int, token: String?, myUsername: String?) {
            _ = token
            _ = myUsername
            SocketManager.shared.joinRoom(roomId)
        }

        func stopSocket(roomId: Int) {
            SocketManager.shared.leaveRoom(roomId)
            clearTypingUsers()
        }
        
        func handleInputChanged(roomId: Int) {
            typingStarted(roomId: roomId)
        }
        
        func submitReport(
            targetMessage: MessageDTO,
            roomId: Int,
            reason: ReportReason,
            details: String,
            contextCount: Int,
            blockAfterReport: Bool,
            token: String?
        ) async -> Bool {
            _ = roomId
            
            guard let token, !token.isEmpty else {
                reportErrorText = "Missing auth token."
                return false
            }
            
            isSubmittingReport = true
            reportErrorText = nil
            defer { isSubmittingReport = false }
            
            let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let payload = ReportCreateRequest(
                messageId: targetMessage.id,
                reason: reason.rawValue,
                details: trimmedDetails.isEmpty ? nil : trimmedDetails,
                contextCount: contextCount,
                blockAfterReport: blockAfterReport
            )
            
            do {
                let bodyData = try JSONEncoder().encode(payload)
                
                let _: ReportCreateResponse = try await APIClient.shared.send(
                    APIRequest(
                        path: "reports/messages",
                        method: .POST,
                        body: bodyData,
                        requiresAuth: true
                    ),
                    token: token
                )
                
                return true
            } catch {
                reportErrorText = error.localizedDescription
                return false
            }
        }
        
        func editMessage(
            messageId: Int,
            newText: String,
            token: String?
        ) async -> Bool {
            guard let token, !token.isEmpty else {
                errorText = "Missing auth token."
                return false
            }
            
            let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            
            do {
                let bodyData = try JSONSerialization.data(
                    withJSONObject: ["content": trimmed],
                    options: []
                )
                
                let updated: MessageDTO = try await APIClient.shared.send(
                    APIRequest(
                        path: "messages/\(messageId)",
                        method: .PATCH,
                        body: bodyData,
                        requiresAuth: true
                    ),
                    token: token
                )
                
                MessageStore.shared.upsertMessage(updated)
                self.messages = MessageStore.shared.currentWindow()
                    .filter { $0.chatRoomId == updated.chatRoomId }
                    .sorted { a, b in
                        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
                        return a.id < b.id
                    }
                return true
            } catch {
                errorText = "Couldn’t edit message."
                return false
            }
        }
        
        func deleteMessage(
            messageId: Int,
            token: String?,
            deleteForEveryone: Bool
        ) async -> Bool {
            guard let token, !token.isEmpty else {
                errorText = "Missing auth token."
                return false
            }
            
            if messageId <= 0 {
                return true
            }
            
            do {
                let path = deleteForEveryone
                ? "messages/\(messageId)?scope=everyone"
                : "messages/\(messageId)"
                
                let updated: MessageDTO = try await APIClient.shared.send(
                    APIRequest(
                        path: path,
                        method: .DELETE,
                        requiresAuth: true
                    ),
                    token: token
                )
                
                MessageStore.shared.upsertMessage(updated)
                self.messages = MessageStore.shared.currentWindow()
                    .filter { $0.chatRoomId == updated.chatRoomId }
                    .sorted { a, b in
                        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
                        return a.id < b.id
                    }
                return true
            } catch {
                errorText = "Couldn’t delete message."
                return false
            }
        }
        
        func archiveConversation(
            conversationId: Int,
            kind: String,
            token: String?
        ) async -> Bool {
            guard let token, !token.isEmpty else {
                errorText = "Missing auth token."
                return false
            }
            
            do {
                let bodyData = try JSONSerialization.data(
                    withJSONObject: ["kind": kind],
                    options: []
                )
                
                let _: EmptyAPIResponse = try await APIClient.shared.send(
                    APIRequest(
                        path: "conversations/\(conversationId)/archive",
                        method: .POST,
                        body: bodyData,
                        requiresAuth: true
                    ),
                    token: token
                )
                
                return true
            } catch {
                errorText = "Couldn’t archive conversation."
                return false
            }
        }
        
        func deleteConversation(
            conversationId: Int,
            kind: String,
            token: String?
        ) async -> Bool {
            guard let token, !token.isEmpty else {
                errorText = "Missing auth token."
                return false
            }
            
            do {
                let bodyData = try JSONSerialization.data(
                    withJSONObject: ["kind": kind],
                    options: []
                )
                
                let _: EmptyAPIResponse = try await APIClient.shared.send(
                    APIRequest(
                        path: "conversations/\(conversationId)",
                        method: .DELETE,
                        body: bodyData,
                        requiresAuth: true
                    ),
                    token: token
                )
                
                return true
            } catch {
                errorText = "Couldn’t delete conversation."
                return false
            }
        }
    }

