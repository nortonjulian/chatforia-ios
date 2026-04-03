import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import AVFoundation

struct ChatThreadView: View {
    let room: ChatRoomDTO
    let randomSession: RandomSession?

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var callManager: CallManager

    @StateObject private var vm = ChatThreadViewModel()
    @StateObject private var settingsVM = SettingsViewModel()
    
    @StateObject private var riaVM = RiaViewModel()
    @State private var showingRewriteSheet = false

    @State private var draft = ""
    @State private var lastMessageId: Int? = nil

    @State private var editingMessage: MessageDTO? = nil
    @State private var editDraft: String = ""
    
    @State private var editPendingGIFURL: URL? = nil
    @State private var showEditGIFPicker = false

    @State private var deletingMessage: MessageDTO? = nil

    @State private var showAttachmentSheet = false
    @State private var showGIFPicker = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    
    @State private var isProcessingVideo = false
    @State private var videoProcessingStatus: String? = nil
    
    @State private var selectedVideoURL: IdentifiableURL? = nil
    
    @State private var pendingGIFURL: URL? = nil
    
    @State private var pendingImageData: Data? = nil
    @State private var pendingVideoURL: URL? = nil
    
    @State private var showSearchSheet = false
    @State private var searchText = ""
    @State private var highlightedMessageID: Int? = nil
    @State private var showEditEmojiPicker = false
    
    @FocusState private var isEditEditorFocused: Bool
    
    struct IdentifiableURL: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        VStack(spacing: 0) {
            if let err = vm.errorText, !err.isEmpty {
                Text(err)
                    .foregroundColor(.red)
                    .padding()
            }

            messagesSection
            pendingMediaBar
            composer
        }
        .background(themeManager.palette.screenBackground.ignoresSafeArea())
        .navigationTitle(roomDisplayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task {
            await onLoad()
        }
        .sheet(item: $editingMessage) { _ in
            editMessageSheet
        }
        .sheet(isPresented: $showAttachmentSheet) {
            AttachmentPickerSheet(
                onPhoto: {
                    showAttachmentSheet = false

                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        presentPhotoPicker()
                    }
                },
                onGIF: {
                    showAttachmentSheet = false

                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        presentGIFPicker()
                    }
                }
            )
        }
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
        .sheet(isPresented: $showGIFPicker) {
            GIFPickerView { url in
                pendingGIFURL = url
            }
        }
        .sheet(isPresented: $showSearchSheet) {
            ChatThreadSearchSheet(
                messages: vm.messages,
                searchText: $searchText
            ) { selected in
                highlightedMessageID = selected.id
                showSearchSheet = false

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)

                    if highlightedMessageID == selected.id {
                        highlightedMessageID = nil
                    }
                }
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }

            Task {
                if let type = newItem.supportedContentTypes.first,
                   type.conforms(to: .movie) {

                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent("pending-video-\(UUID().uuidString).mov")

                        try? data.write(to: tempURL, options: .atomic)

                        await MainActor.run {
                            pendingVideoURL = tempURL
                        }
                    }
                } else {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            pendingImageData = data
                        }
                    }
                }

                await MainActor.run {
                    selectedPhotoItem = nil
                }
            }
        }
        .confirmationDialog(
            "Delete message?",
            isPresented: Binding(
                get: { deletingMessage != nil },
                set: { if !$0 { deletingMessage = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let msg = deletingMessage {
                Button("Delete for me", role: .destructive) {
                    Task {
                        let _ = await vm.deleteMessage(
                            messageId: msg.id,
                            token: TokenStore.shared.read(),
                            deleteForEveryone: false
                        )
                        deletingMessage = nil
                    }
                }

                if canDeleteForEveryone(msg) {
                    Button("Delete for everyone", role: .destructive) {
                        Task {
                            let _ = await vm.deleteMessage(
                                messageId: msg.id,
                                token: TokenStore.shared.read(),
                                deleteForEveryone: true
                            )
                            deletingMessage = nil
                        }
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                deletingMessage = nil
            }
        }
        .fullScreenCover(item: $selectedVideoURL) { item in
            FullscreenVideoView(url: item.url)
        }
    }
}

extension ChatThreadView {
    private var messagesSection: some View {
        Group {
            if vm.isLoading && vm.messages.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.messages.isEmpty {
                Text("No messages yet")
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let currentUserId = auth.currentUser?.id
                
                MessagesListView(
                    messages: vm.messages,
                    currentUserId: currentUserId,
                    isGroupRoom: room.isGroup == true,
                    isLoadingOlder: vm.isLoadingOlder,
                    deliveryStateForMessage: { _ in nil },
                    onLoadOlder: {
                        await vm.loadOlderMessagesIfNeeded()
                    },
                    onRetryTap: { _ in },
                    onEdit: { msg in
                        editingMessage = msg
                        editDraft =
                            DecryptedMessageTextStore.shared.text(for: msg.id)?
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            ?? msg.rawContent?.trimmingCharacters(in: .whitespacesAndNewlines)
                            ?? msg.translatedForMe?.trimmingCharacters(in: .whitespacesAndNewlines)
                            ?? msg.attachments?
                                .compactMap { $0.caption?.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .first(where: { !$0.isEmpty })
                            ?? ""
                        
                        if let gif = msg.attachments?.first(where: { att in
                            let kind = (att.kind ?? "").uppercased()
                            let mime = (att.mimeType ?? "").lowercased()
                            return kind == "GIF" || mime == "image/gif"
                        }),
                        let urlString = gif.url,
                        let url = URL(string: urlString) {
                            editPendingGIFURL = url
                        } else {
                            editPendingGIFURL = nil
                        }
                        
                        isEditEditorFocused = true
                    },
                    onDelete: { msg in
                        deletingMessage = msg
                    },
                    onReport: { _ in },
                    onVideoTap: { url in
                        selectedVideoURL = IdentifiableURL(url: url)
                    },
                    lastMessageId: $lastMessageId,
                    highlightedMessageID: $highlightedMessageID
                )
            }
        }
    }
}

extension ChatThreadView {
    private var pendingMediaBar: some View {
        Group {
            if let gifURL = pendingGIFURL {
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: gifURL) { phase in
                        switch phase {
                        case .empty:
                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(themeManager.palette.composerFieldBackground)
                                ProgressView()
                            }
                            .frame(height: 160)

                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 180)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        case .failure:
                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(themeManager.palette.composerFieldBackground)

                                VStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle")
                                    Text("Couldn’t load GIF")
                                        .font(.caption)
                                }
                                .foregroundStyle(themeManager.palette.secondaryText)
                            }
                            .frame(height: 160)

                        @unknown default:
                            EmptyView()
                        }
                    }

                    Button {
                        pendingGIFURL = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)

            } else if !isProcessingVideo && (pendingImageData != nil || pendingVideoURL != nil) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pendingVideoURL != nil ? "Video ready" : "Photo ready")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(themeManager.palette.primaryText)

                        Text("Add a caption, then tap Send")
                            .font(.caption)
                            .foregroundStyle(themeManager.palette.secondaryText)
                    }

                    Spacer(minLength: 0)

                    Button("Cancel") {
                        pendingImageData = nil
                        pendingVideoURL = nil
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .buttonStyle(.plain)

                    Button {
                        Task {
                            let trimmedCaption = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            let caption = trimmedCaption.isEmpty ? nil : trimmedCaption

                            if let imageData = pendingImageData {
                                let ok = await vm.sendImageMessage(
                                    roomId: room.id,
                                    token: auth.currentToken,
                                    imageData: imageData,
                                    caption: caption,
                                    senderId: auth.currentUser?.id ?? 0,
                                    senderUsername: auth.currentUser?.username,
                                    senderPublicKey: auth.currentUser?.publicKey
                                )

                                if ok {
                                    pendingImageData = nil
                                    draft = ""
                                    vm.stopTypingNow(roomId: room.id)
                                }
                            } else if let videoURL = pendingVideoURL {
                                do {
                                    let trimmedCaption = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let caption = trimmedCaption.isEmpty ? nil : trimmedCaption

                                    pendingVideoURL = nil

                                    isProcessingVideo = true
                                    videoProcessingStatus = "Uploading video..."

                                    let videoData = try Data(contentsOf: videoURL)

                                    let ok = await vm.sendVideoMessage(
                                        roomId: room.id,
                                        token: auth.currentToken,
                                        videoData: videoData,
                                        fileName: "video-\(Int(Date().timeIntervalSince1970)).mov",
                                        mimeType: "video/quicktime",
                                        caption: caption,
                                        senderId: auth.currentUser?.id ?? 0,
                                        senderUsername: auth.currentUser?.username,
                                        senderPublicKey: auth.currentUser?.publicKey
                                    )

                                    isProcessingVideo = false
                                    videoProcessingStatus = nil

                                    if ok {
                                        draft = ""
                                        vm.stopTypingNow(roomId: room.id)
                                    } else {
                                        pendingVideoURL = videoURL
                                    }

                                } catch {
                                    isProcessingVideo = false
                                    videoProcessingStatus = nil
                                    pendingVideoURL = videoURL
                                    vm.errorText = "Couldn’t load selected video. \(error.localizedDescription)"
                                }
                            }
                        }
                    } label: {
                        Text("Send")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(themeManager.palette.composerButtonForeground)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                themeManager.palette.composerButtonStart,
                                                themeManager.palette.composerButtonEnd
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isSendingImage || isProcessingVideo || auth.currentToken == nil)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(themeManager.palette.composerFieldBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(themeManager.palette.composerBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }
        }
    }
}

extension ChatThreadView {
    private var composer: some View {
        VStack(spacing: 8) {
            if isProcessingVideo {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.9)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(videoProcessingStatus ?? "Processing video...")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(themeManager.palette.primaryText)

                        Text("Please keep Chatforia open while this finishes.")
                            .font(.caption)
                            .foregroundStyle(themeManager.palette.secondaryText)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(themeManager.palette.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(themeManager.palette.border, lineWidth: 1)
                )
                .padding(.horizontal, 10)
            }

            MessageComposerView(
                draft: $draft,
                isSending: vm.isSendingImage || vm.isSendingAudio || isProcessingVideo,
                onDraftChanged: {
                    vm.typingStarted(roomId: room.id)

                    riaVM.loadSuggestions(
                        token: auth.currentToken,
                        enabled: settingsVM.enableSmartReplies,
                        filterProfanity: settingsVM.maskAIProfanity,
                        draft: draft,
                        messages: vm.messages.suffix(8).map {
                            RiaContextMessageDTO(
                                role: $0.sender.id == auth.currentUser?.id ? "user" : "assistant",
                                content: $0.rawContent
                                    ?? $0.translatedForMe
                                    ?? ($0.contentCiphertext != nil ? "[encrypted]" : "")
                            )
                        }
                    )
                },
                onAttachmentTap: {
                    showAttachmentSheet = true
                },
                onSend: {
                    Task {
                        if let gifURL = pendingGIFURL {
                            await sendGIFWithCaption(from: gifURL)
                        } else if pendingImageData != nil || pendingVideoURL != nil {
                            await sendPendingMedia()
                        } else {
                            await send()
                        }
                    }
                },
                suggestions: riaVM.suggestions,
                isLoadingSuggestions: riaVM.isLoadingSuggestions,
                onSuggestionTap: { suggestion in
                    draft = suggestion
                },
                onRewriteTap: {
                    showingRewriteSheet = true
                },
                hasPendingAttachment: pendingGIFURL != nil || pendingImageData != nil || pendingVideoURL != nil,
                isCaptioningPendingMedia: pendingImageData != nil || pendingVideoURL != nil
            )
            .environmentObject(settingsVM)
            .padding(.bottom, 6)
        }
    }
}

extension ChatThreadView {
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                showSearchSheet = true
            } label: {
                Image(systemName: "magnifyingglass")
            }

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
        }
    }
}

extension ChatThreadView {
    private func sendGIFWithCaption(from url: URL) async {
        guard let senderId = auth.currentUser?.id else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !data.isEmpty else {
                await MainActor.run {
                    vm.errorText = "GIF data is empty."
                }
                return
            }

            let caption = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveCaption = caption.isEmpty ? nil : caption

            let ok = await vm.sendGIFMessage(
                roomId: room.id,
                token: TokenStore.shared.read(),
                gifData: data,
                caption: effectiveCaption,
                senderId: senderId,
                senderUsername: auth.currentUser?.username,
                senderPublicKey: nil
            )

            if ok {
                draft = ""
                pendingGIFURL = nil
                vm.stopTypingNow(roomId: room.id)
            }
        } catch {
            await MainActor.run {
                vm.errorText = "Couldn’t send GIF. \(error.localizedDescription)"
            }
        }
    }
    
    private func sendPendingMedia() async {
        let trimmedCaption = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let caption = trimmedCaption.isEmpty ? nil : trimmedCaption

        if let imageData = pendingImageData {
            let ok = await vm.sendImageMessage(
                roomId: room.id,
                token: auth.currentToken,
                imageData: imageData,
                caption: caption,
                senderId: auth.currentUser?.id ?? 0,
                senderUsername: auth.currentUser?.username,
                senderPublicKey: auth.currentUser?.publicKey
            )

            if ok {
                pendingImageData = nil
                draft = ""
                vm.stopTypingNow(roomId: room.id)
            }
            return
        }

        if let videoURL = pendingVideoURL {
            do {
                pendingVideoURL = nil
                isProcessingVideo = true
                videoProcessingStatus = "Uploading video..."

                let videoData = try Data(contentsOf: videoURL)

                let ok = await vm.sendVideoMessage(
                    roomId: room.id,
                    token: auth.currentToken,
                    videoData: videoData,
                    fileName: "video-\(Int(Date().timeIntervalSince1970)).mov",
                    mimeType: "video/quicktime",
                    caption: caption,
                    senderId: auth.currentUser?.id ?? 0,
                    senderUsername: auth.currentUser?.username,
                    senderPublicKey: auth.currentUser?.publicKey
                )

                isProcessingVideo = false
                videoProcessingStatus = nil

                if ok {
                    draft = ""
                    vm.stopTypingNow(roomId: room.id)
                } else {
                    pendingVideoURL = videoURL
                }
            } catch {
                isProcessingVideo = false
                videoProcessingStatus = nil
                pendingVideoURL = videoURL
                vm.errorText = "Couldn’t load selected video. \(error.localizedDescription)"
            }
        }
    }
    

    
    private func onLoad() async {
        if let user = auth.currentUser {
            vm.configureCurrentUser(
                id: user.id,
                username: user.username,
                publicKey: user.publicKey
            )
            settingsVM.load(from: user)
        }

        settingsVM.loadLocalAISettings()

        await reload()

        vm.startSocket(
            roomId: room.id,
            token: TokenStore.shared.read(),
            myUsername: auth.currentUser?.username
        )
    }

    private func reload() async {
        await vm.loadMessages(
            roomId: room.id,
            token: TokenStore.shared.read()
        )
    }

    private func send() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let senderId = auth.currentUser?.id else { return }

        let ok = await vm.sendMessage(
            roomId: room.id,
            token: TokenStore.shared.read(),
            text: trimmed,
            senderId: senderId,
            senderUsername: auth.currentUser?.username,
            senderPublicKey: nil
        )

        if ok {
            draft = ""
            vm.stopTypingNow(roomId: room.id)
        }
    }
    
    private var deleteForEveryoneWindowSec: TimeInterval { 900 }

    private func canDeleteForEveryone(_ msg: MessageDTO) -> Bool {
        guard msg.sender.id == auth.currentUser?.id else { return false }
        return Date().timeIntervalSince(msg.createdAt) <= deleteForEveryoneWindowSec
    }

    private func presentPhotoPicker() {
        showAttachmentSheet = false

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            showPhotoPicker = true
        }
    }

    private func presentGIFPicker() {
        showAttachmentSheet = false

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            showGIFPicker = true
        }
    }

    private func startCall() {
        guard let phone = room.phone else { return }

        callManager.startCall(
            to: .phoneNumber(phone, displayName: roomDisplayTitle),
            auth: auth
        )
    }

    private func startVideoCall() {
        if room.isGroup == true {
            callManager.startGroupVideoCall(
                roomId: room.id,
                displayName: roomDisplayTitle,
                auth: auth
            )
        }
    }

    private var roomDisplayTitle: String {
        room.name ?? "Chat #\(room.id)"
    }
    
    private var editMessageSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Button("GIF") {
                        showEditGIFPicker = true
                    }

                    Button("Emoji") {
                        if !isEditEditorFocused {
                            isEditEditorFocused = true
                        }
                    }

                    if editPendingGIFURL != nil {
                        Button("Remove GIF", role: .destructive) {
                            editPendingGIFURL = nil
                        }
                    }

                    Spacer()
                }

                if let editPendingGIFURL {
                    GIFWebView(url: editPendingGIFURL)
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                EditMessageTextView(
                    text: $editDraft,
                    isFocused: Binding(
                        get: { isEditEditorFocused },
                        set: { isEditEditorFocused = $0 }
                    )
                )
                .frame(minHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(themeManager.palette.border, lineWidth: 1)
                )

                Spacer()
            }
            .padding()
            .navigationTitle("Edit message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editingMessage = nil
                        editDraft = ""
                        editPendingGIFURL = nil
                        showEditGIFPicker = false
                        isEditEditorFocused = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { @MainActor in
                            guard let msg = editingMessage else { return }

                            let ok = await vm.editMessage(
                                message: msg,
                                newText: editDraft,
                                gifURL: editPendingGIFURL,
                                token: TokenStore.shared.read()
                            )

                            if ok {
                                editingMessage = nil
                                editDraft = ""
                                editPendingGIFURL = nil
                                showEditGIFPicker = false
                                isEditEditorFocused = false
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showEditGIFPicker) {
                GIFPickerView { url in
                    editPendingGIFURL = url
                    showEditGIFPicker = false
                }
            }
        }
    }
}
