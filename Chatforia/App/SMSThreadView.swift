import SwiftUI
import PhotosUI

struct SendSMSResponseDTO: Decodable {
    let ok: Bool
    let threadId: Int
    let provider: String?
    let messageSid: String?
    let clientRef: String?
}

struct SMSThreadView: View {
    let conversation: ConversationDTO

    @StateObject private var vm = SMSThreadViewModel()
    @State private var draft: String = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isUploadingMedia = false

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var pollingTask: Task<Void, Never>?
    @State private var showPhotoPicker = false

    @State private var showingAddContact = false
    
    @State private var showSearchSheet = false
    @State private var searchText = ""
    @State private var highlightedMessageID: Int? = nil
    
    @State private var activeConversation: ConversationDTO
    
    @StateObject private var numberVM = PhoneNumberViewModel()
    @State private var showNumberPicker = false
    @EnvironmentObject private var auth: AuthStore
    
    init(conversation: ConversationDTO) {
            self.conversation = conversation
            _activeConversation = State(initialValue: conversation)
        }

    var body: some View {
        VStack(spacing: 0) {
            errorBanner

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            composer
        }
        .background(themeManager.palette.screenBackground.ignoresSafeArea())
        .navigationTitle(
            vm.resolvedTitle(
                fallback: activeConversation.title,
                fallbackPhone: activeConversation.phone
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showSearchSheet = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }

                Button {
                    showingAddContact = true
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                }

                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(activeConversation.id == nil)
            }
        }
        .sheet(isPresented: $showingAddContact) {
            AddContactView(
                initialMode: .phone,
                initialPhoneNumber: vm.resolvedPhone(fallback: activeConversation.phone) ?? "",
                initialExternalName: inferredContactName
            ) { _ in
                showingAddContact = false
            }
            .environmentObject(themeManager)
        }
        .task(id: activeConversation.uniqueId) {
            if activeConversation.id != nil {
                await reload()
                startPolling()
            }
        }
        .task(id: activeConversation.uniqueId) {
            if activeConversation.id != nil {
                await reload()
                startPolling()
            } else {
                vm.thread = nil
                vm.messages = []
                stopPolling()
            }
        }
        .onDisappear {
            stopPolling()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                if activeConversation.id != nil {
                    Task { await reload() }
                    startPolling()
                }
            } else {
                stopPolling()
            }
        }
        .sheet(isPresented: $showSearchSheet) {
            SMSThreadSearchSheet(
                messages: vm.messages,
                searchText: $searchText
            ) { selected in
                highlightedMessageID = selected.id
                showSearchSheet = false

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    try? await Task.sleep(nanoseconds: 2_000_000_000)

                    if highlightedMessageID == selected.id {
                        highlightedMessageID = nil
                    }
                }
            }
            .environmentObject(themeManager)
        }
        .sheet(isPresented: $showNumberPicker) {
            PhoneNumberManagementView()
                .environmentObject(themeManager)
                .environmentObject(auth)
        }
        .onChange(of: showNumberPicker) { _, isOpen in
            if !isOpen {
                Task {
                    await numberVM.loadCurrentNumber(token: auth.currentToken)
                }
            }
        }
    }

    private var inferredContactName: String {
        let title = activeConversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = (activeConversation.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !title.isEmpty && title != phone {
            return title
        }

        return ""
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
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.messages.isEmpty {
            LoadingStateView(
                title: "Loading SMS…",
                subtitle: "Pulling in your latest text messages."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        } else if vm.messages.isEmpty {
            EmptyStateView(
                systemImage: "message",
                title: "No messages yet",
                subtitle: "Send a text to start the conversation."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        } else {
            SMSMessagesListView(
                messages: vm.messages,
                highlightedMessageID: highlightedMessageID
            )
                .refreshable {
                    await reload()
            }
        }
    }

    private var composer: some View {
        MessageComposerView(
            draft: $draft,
            isSending: isUploadingMedia || vm.isSending,
            onDraftChanged: {},
            onAttachmentTap: {
                showPhotoPicker = true
            },
            onSend: {
                Task {
                    await send()
                }
            }
        )
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotos,
            maxSelectionCount: 6,
            matching: .images
        )
    }

    private func startPolling() {
        guard activeConversation.id != nil else { return }

        stopPolling()

        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if Task.isCancelled { break }
                await reload()
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func reload() async {
        guard let threadId = activeConversation.id else { return }
        let token = TokenStore.shared.read()
        await vm.loadThread(threadId: threadId, token: token)
    }


    private func send() async {
        let token = TokenStore.shared.read()
        
        await numberVM.loadCurrentNumber(token: token)

        if numberVM.currentNumber == nil {
            vm.errorText = "Choose a Chatforia number before sending SMS."
            showNumberPicker = true
            return
        }

        guard let to = vm.resolvedPhone(fallback: activeConversation.phone) else {
            vm.errorText = "Missing destination phone number."
            return
        }

        if !selectedPhotos.isEmpty {
            isUploadingMedia = true
            let urls = await uploadImages(selectedPhotos)
            isUploadingMedia = false
            selectedPhotos.removeAll()

            guard !urls.isEmpty else {
                vm.errorText = "Could not upload selected image(s)."
                return
            }

            let threadId = await vm.sendMediaMessage(
                existingThreadId: activeConversation.id,
                to: to,
                mediaUrls: urls,
                token: token
            )

            if let threadId {
                if activeConversation.id == nil {
                    activeConversation = ConversationDTO(
                        kind: activeConversation.kind,
                        id: threadId,
                        title: activeConversation.title,
                        displayName: activeConversation.displayName,
                        updatedAt: activeConversation.updatedAt,
                        isGroup: activeConversation.isGroup,
                        phone: activeConversation.phone,
                        unreadCount: activeConversation.unreadCount,
                        avatarUsers: activeConversation.avatarUsers,
                        last: activeConversation.last
                    )
                    startPolling()
                }

                draft = ""
            }

            return
        }

        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let threadId = await vm.sendTextMessage(
            existingThreadId: activeConversation.id,
            to: to,
            text: trimmed,
            token: token
        )

        if let threadId {
            if activeConversation.id == nil {
                activeConversation = ConversationDTO(
                    kind: activeConversation.kind,
                    id: threadId,
                    title: activeConversation.title,
                    displayName: activeConversation.displayName,
                    updatedAt: activeConversation.updatedAt,
                    isGroup: activeConversation.isGroup,
                    phone: activeConversation.phone,
                    unreadCount: activeConversation.unreadCount,
                    avatarUsers: activeConversation.avatarUsers,
                    last: activeConversation.last
                )
                startPolling()
            }

            draft = ""
        }
    }

    private func uploadImages(_ items: [PhotosPickerItem]) async -> [String] {
        guard let token = TokenStore.shared.read() else { return [] }

        var urls: [String] = []

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    continue
                }

                let uploaded = try await UploadService.shared.uploadImage(data: data, token: token)
                urls.append(uploaded.url)
            } catch {
                #if DEBUG
                print("❌ SMS image upload failed:", error)
                #endif
            }
        }

        return urls
    }
}

// MARK: - Messages list

private struct SMSMessagesListView: View {
    let messages: [SMSMessageDTO]
    let highlightedMessageID: Int?

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        GeometryReader { geo in
            let bubbleMaxWidth = geo.size.width * 0.72

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(messages) { msg in
                            SMSMessageRowView(
                                msg: msg,
                                bubbleMaxWidth: bubbleMaxWidth,
                                isHighlighted: highlightedMessageID == msg.id
                            )
                            .id(msg.id)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("BOTTOM")
                    }
                    .padding(.vertical, 14)
                }
                .background(themeManager.palette.screenBackground)
                .onAppear {
                    scrollToBottom(proxy, animated: false)
                }
                .onChange(of: messages.map(\.id)) { _, _ in
                    scrollToBottom(proxy, animated: true)
                }
                .onChange(of: highlightedMessageID) { _, newValue in
                    guard let id = newValue else { return }

                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .background(themeManager.palette.screenBackground)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo("BOTTOM", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("BOTTOM", anchor: .bottom)
            }
        }
    }
}

// MARK: - Row

private struct SMSMessageRowView: View {
    let msg: SMSMessageDTO
    let bubbleMaxWidth: CGFloat
    let isHighlighted: Bool

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if msg.isOutgoing {
                Spacer(minLength: 52)
            }

            VStack(alignment: msg.isOutgoing ? .trailing : .leading, spacing: 6) {
                if !msg.media.isEmpty {
                    SMSMediaStackView(message: msg, maxWidth: bubbleMaxWidth)
                }

                if let text = msg.trimmedBody, !text.isEmpty {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(
                            msg.isOutgoing
                                ? themeManager.palette.bubbleOutgoingText
                                : themeManager.palette.bubbleIncomingText
                        )
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    msg.isOutgoing
                                        ? LinearGradient(
                                            colors: [
                                                themeManager.palette.bubbleOutgoingStart,
                                                themeManager.palette.bubbleOutgoingEnd
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        : LinearGradient(
                                            colors: [
                                                themeManager.palette.bubbleIncoming,
                                                themeManager.palette.bubbleIncoming
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                )
                        )
                } else if msg.media.isEmpty {
                    Text("—")
                        .font(.body)
                        .foregroundStyle(
                            msg.isOutgoing
                                ? themeManager.palette.bubbleOutgoingText
                                : themeManager.palette.bubbleIncomingText
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    msg.isOutgoing
                                        ? LinearGradient(
                                            colors: [
                                                themeManager.palette.bubbleOutgoingStart,
                                                themeManager.palette.bubbleOutgoingEnd
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        : LinearGradient(
                                            colors: [
                                                themeManager.palette.bubbleIncoming,
                                                themeManager.palette.bubbleIncoming
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                )
                        )
                }

                HStack(spacing: 6) {
                    Text(timestampText(msg.createdAt))
                        .font(.caption2)
                        .foregroundStyle(themeManager.palette.secondaryText)

                    if msg.editedAt != nil {
                        Text("Edited")
                            .font(.caption2)
                            .foregroundStyle(themeManager.palette.secondaryText)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: bubbleMaxWidth, alignment: msg.isOutgoing ? .trailing : .leading)

            if !msg.isOutgoing {
                Spacer(minLength: 52)
            }
        }
        .frame(maxWidth: .infinity, alignment: msg.isOutgoing ? .trailing : .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHighlighted ? Color.yellow.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isHighlighted ? Color.yellow.opacity(0.45) : Color.clear, lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.2), value: isHighlighted)
    }

    private func timestampText(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute()
        )
    }
}

// MARK: - Media stack

private struct SMSMediaStackView: View {
    let message: SMSMessageDTO
    let maxWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(message.media.enumerated()), id: \.offset) { index, item in
                if item.isImage {
                    SMSAuthenticatedImageCard(
                        messageId: message.id,
                        mediaIndex: index,
                        title: item.displayLabel,
                        maxWidth: min(maxWidth, 240)
                    )
                } else {
                    SMSGenericAttachmentCard(item: item)
                        .frame(width: min(maxWidth, 240))
                }
            }
        }
    }
}

// MARK: - Authenticated image card

private struct SMSAuthenticatedImageCard: View {
    let messageId: Int
    let mediaIndex: Int
    let title: String
    let maxWidth: CGFloat

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var failed = false
    @State private var showFullScreen = false

    var body: some View {
        Button {
            if image != nil {
                showFullScreen = true
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: maxWidth, height: 180)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if isLoading {
                    ProgressView()
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: failed ? "exclamationmark.triangle" : "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)

                        Text(failed ? "Could not load image" : title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: maxWidth, height: 180)
        }
        .buttonStyle(.plain)
        .task(id: "\(messageId)-\(mediaIndex)") {
            await load()
        }
        .sheet(isPresented: $showFullScreen) {
            if let image {
                SMSFullscreenImageView(image: image)
            }
        }
    }

    private func load() async {
        guard image == nil, !isLoading else { return }

        guard let token = TokenStore.shared.read() else {
            failed = true
            return
        }

        isLoading = true
        failed = false
        defer { isLoading = false }

        do {
            let request = APIRequest(
                path: "sms/media/\(messageId)/\(mediaIndex)",
                method: .GET,
                requiresAuth: true
            )

            let (data, _) = try await APIClient.shared.sendRaw(request, token: token)

            if let uiImage = UIImage(data: data) {
                image = uiImage
            } else {
                failed = true
            }
        } catch {
            failed = true
            #if DEBUG
            print("❌ SMS image load error:", error)
            #endif
        }
    }
}

private struct SMSFullscreenImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(1, min(lastScale * value, 4))
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if scale > 1 {
                                scale = 1
                                lastScale = 1
                            } else {
                                scale = 2
                                lastScale = 2
                            }
                        }
                    }
                    .padding()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - Generic attachment card

private struct SMSGenericAttachmentCard: View {
    let item: SMSMediaItemDTO

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(themeManager.palette.secondaryText)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(themeManager.palette.primaryText)
                    .lineLimit(1)

                Text(item.contentType?.nilIfBlank ?? "Protected media")
                    .font(.caption)
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text("In thread")
                .font(.caption2)
                .foregroundStyle(themeManager.palette.secondaryText)
        }
        .padding(12)
        .background(themeManager.palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(themeManager.palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var iconName: String {
        if item.isVideo { return "video.fill" }
        if item.isAudio { return "waveform" }
        if item.isImage { return "photo.fill" }
        return "paperclip"
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
