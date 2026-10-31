import SwiftUI
import Combine
import PhotosUI
import UIKit
import AVFoundation

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
    @StateObject private var voice = SMSVoiceNoteController()
    @State private var isPreparingVoiceSend = false

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var pollingTask: Task<Void, Never>?
    @State private var showPhotoPicker = false

    @State private var showingAddContact = false
    
    @State private var showSearchSheet = false
    @State private var searchText = ""
    @State private var highlightedMessageID: Int? = nil

    @State private var reportingMessage: SMSMessageDTO?
    @State private var reportReason: ReportReason = .spamScam
    @State private var reportDetails = ""
    @State private var reportContextCount = 10
    @State private var blockAfterReport = false
    @State private var isSubmittingReport = false

    @State private var numberPendingBlock: String?
    @State private var showBlockConfirmation = false
    
    @State private var activeConversation: ConversationDTO
    
    @StateObject private var numberVM = PhoneNumberViewModel()
    @State private var showNumberPicker = false
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var callManager: CallManager
    @AppStorage("chatforia_language") private var appLanguage = "en"
    
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
            ToolbarItem(placement: .principal) {
                ConversationTransportTitle(
                    title: vm.resolvedTitle(
                        fallback: activeConversation.title,
                        fallbackPhone: activeConversation.phone
                    ),
                    isSMS: true
                )
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showSearchSheet = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }

                Button {
                    startPhoneCall()
                } label: {
                    Image(systemName: "phone.fill")
                }
                .accessibilityLabel(
                    appText("common.call", languageCode: appLanguage)
                )

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
            } else {
                vm.thread = nil
                vm.messages = []
                stopPolling()
            }
        }
        .onDisappear {
            stopPolling()
            voice.discard()
        }
        .onChange(of: auth.currentUser?.id) { _, _ in
            voice.discard()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                if activeConversation.id != nil {
                    Task { await reload() }
                    startPolling()
                }
            } else {
                stopPolling()
                if newPhase == .background && (voice.isRecording || voice.isStarting) { voice.discard() }
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
        .sheet(item: $reportingMessage) { message in
            PSTNReportMessageSheet(
                phone: message.fromNumber ??
                    vm.resolvedPhone(
                        fallback: activeConversation.phone
                    ) ??
                    "Unknown number",
                previewText: message.trimmedBody ?? "",
                isSubmitting: isSubmittingReport,
                reason: $reportReason,
                contextCount: $reportContextCount,
                details: $reportDetails,
                blockAfterReport: $blockAfterReport,
                onCancel: {
                    if !isSubmittingReport {
                        reportingMessage = nil
                    }
                },
                onSubmit: {
                    Task {
                        isSubmittingReport = true

                        let succeeded = await vm.reportMessage(
                            messageId: message.id,
                            reason: reportReason,
                            details: reportDetails,
                            contextCount: reportContextCount,
                            blockAfterReport: blockAfterReport,
                            token: TokenStore.shared.read()
                        )

                        isSubmittingReport = false

                        if succeeded {
                            reportingMessage = nil
                        }
                    }
                }
            )
        }
        .confirmationDialog(
            "Block this phone number?",
            isPresented: $showBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button("Block number", role: .destructive) {
                guard let phone = numberPendingBlock else { return }

                Task {
                    let succeeded = await vm.blockNumber(
                        phone: phone,
                        token: TokenStore.shared.read()
                    )

                    if succeeded {
                        numberPendingBlock = nil
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                numberPendingBlock = nil
            }
        } message: {
            if let phone = numberPendingBlock {
                Text(
                    "Future SMS and MMS messages from \(phone) will not be stored or delivered."
                )
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

    private func startPhoneCall() {
        guard let phone = vm.resolvedPhone(
            fallback: activeConversation.phone
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !phone.isEmpty else {
            vm.errorText = "Could not find a phone number to call."
            return
        }

        let displayName = vm.resolvedTitle(
            fallback: activeConversation.title,
            fallbackPhone: activeConversation.phone
        )

        callManager.startCall(
            to: .phoneNumber(phone, displayName: displayName),
            auth: auth
        )
    }

    private var errorBanner: some View {
        Group {
            if let err = voice.errorText ?? vm.errorText, !err.isEmpty {
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
            title:
                appText("sms.loading", languageCode: appLanguage),
            subtitle:
                appText("sms.loadingSubtitle", languageCode: appLanguage)
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        } else if vm.messages.isEmpty {
            EmptyStateView(
                systemImage: "message",
                title: appText("messages.noMessagesYet", languageCode: appLanguage),
                subtitle: appText("messages.sendTextToStartConversation", languageCode: appLanguage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        } else {
            SMSMessagesListView(
                messages: vm.messages,
                highlightedMessageID: highlightedMessageID,
                onDeleteForMe: { message in
                    Task {
                        await vm.deleteMessage(
                            messageId: message.id,
                            token: TokenStore.shared.read()
                        )
                    }
                },
                onReport: { message in
                    reportReason = .spamScam
                    reportDetails = ""
                    reportContextCount = 10
                    blockAfterReport = false
                    reportingMessage = message
                },
                onBlock: { message in
                    numberPendingBlock =
                        message.fromNumber ??
                        vm.resolvedPhone(
                            fallback: activeConversation.phone
                        )

                    showBlockConfirmation =
                        !(numberPendingBlock ?? "").isEmpty
                }
            )
                .refreshable {
                    await reload()
            }
        }
    }

    private var composer: some View {
        MessageComposerView(
            draft: $draft,
            isSending: isUploadingMedia || vm.isSending || voice.isStarting || isPreparingVoiceSend,
            isSendingVoice: voice.isSending,
            onDraftChanged: {},
            onAttachmentTap: {
                showPhotoPicker = true
            },
            onSend: {
                Task {
                    await send()
                }
            },
            isRecordingVoice: voice.isRecording,
            recordingDurationText: AudioAttachmentCardView.formatTime(voice.elapsed),
            voiceDraftDurationText: voice.draft.map { AudioAttachmentCardView.formatTime($0.durationSec) },
            onMicTap: {
                guard selectedPhotos.isEmpty, !isUploadingMedia, !vm.isSending,
                      !isPreparingVoiceSend, !voice.isSending else { return }
                vm.errorText = nil
                Task { await voice.start(token: TokenStore.shared.read()) }
            },
            onStopRecordingTap: { Task { await voice.stop() } },
            onCancelRecordingTap: { voice.discard() },
            onCancelVoiceDraftTap: { voice.discard() },
            onSendVoiceDraftTap: { Task { await sendSMSVoiceDraft() } },
            onPlayVoiceDraftTap: { voice.togglePreview() },
            isPlayingVoiceDraft: voice.isPlaying,
            hasVoiceDraft: voice.draft != nil,
            hasPendingAttachment: !selectedPhotos.isEmpty
        )
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotos,
            maxSelectionCount: 5,
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


    @MainActor
    private func sendSMSVoiceDraft() async {
        guard !isPreparingVoiceSend, !voice.isSending, !vm.isSending,
              !isUploadingMedia, voice.draft != nil else { return }
        guard let token = TokenStore.shared.read(), !token.isEmpty else {
            voice.errorText = "Your session has expired. Please sign in again."
            return
        }
        isPreparingVoiceSend = true
        defer { isPreparingVoiceSend = false }
        await numberVM.loadCurrentNumber(token: token)
        guard TokenStore.shared.read() == token, voice.draft != nil else { return }
        guard numberVM.currentNumber != nil else {
            voice.errorText = appText("sms.chooseNumberBeforeSending", languageCode: appLanguage)
            showNumberPicker = true
            return
        }
        guard let to = vm.resolvedPhone(fallback: activeConversation.phone) else {
            voice.errorText = appText("sms.missingDestinationNumber", languageCode: appLanguage)
            return
        }
        let destinationID = activeConversation.id
        _ = await voice.send(token: token) { url in
            let threadID = await vm.sendMediaMessage(existingThreadId: destinationID,
                to: to, mediaUrls: [url], token: token)
            guard TokenStore.shared.read() == token, let threadID else { return false }
            if activeConversation.id == nil {
                activeConversation = ConversationDTO(kind: activeConversation.kind, id: threadID,
                    title: activeConversation.title, displayName: activeConversation.displayName,
                    updatedAt: activeConversation.updatedAt, isGroup: false, phone: to,
                    unreadCount: activeConversation.unreadCount,
                    avatarUsers: activeConversation.avatarUsers, last: activeConversation.last)
                startPolling()
            }
            return true
        }
    }

    private func send() async {
        guard !voice.isRecording, !voice.isStarting, voice.draft == nil,
              !voice.isSending, !isPreparingVoiceSend else { return }
        let token = TokenStore.shared.read()
        
        await numberVM.loadCurrentNumber(token: token)

        if numberVM.currentNumber == nil {
            vm.errorText =
            appText(
                "sms.chooseNumberBeforeSending",
                languageCode: appLanguage
            )
            showNumberPicker = true
            return
        }

        guard let to = vm.resolvedPhone(fallback: activeConversation.phone) else {
            vm.errorText =
            appText(
                "sms.missingDestinationNumber",
                languageCode: appLanguage
            )
            return
        }

        if !selectedPhotos.isEmpty {
            isUploadingMedia = true
            let urls = await uploadImages(selectedPhotos)
            isUploadingMedia = false

            guard !urls.isEmpty else {
                if vm.errorText == nil {
                    vm.errorText = appText(
                        "media.uploadFailed",
                        languageCode: appLanguage
                    )
                }
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

                selectedPhotos.removeAll()
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
        guard let token = TokenStore.shared.read(), !token.isEmpty else {
            vm.errorText = "Your session has expired. Please sign in again."
            return []
        }

        // Twilio limits the entire MMS (all media plus body) to 5 MB.
        // Carrier photo target ~1 MB leaves room for multiple attachments.
        let maxMessageBytes = 5_000_000
        let targetJPEGBytes = 1_000_000
        var preparedPhotos: [Data] = []
        var aggregateBytes = 0

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    vm.errorText = "This photo couldn't be prepared for MMS. Choose another photo."
                    return []
                }

                let longestSide = max(image.size.width, image.size.height)
                guard longestSide > 0 else {
                    vm.errorText = "This photo has invalid dimensions."
                    return []
                }

                var scale = min(CGFloat(1), 1600 / longestSide)
                var jpeg: Data?
                for attempt in 0..<7 {
                    let size = CGSize(
                        width: max(1, floor(image.size.width * scale)),
                        height: max(1, floor(image.size.height * scale))
                    )
                    let renderer = UIGraphicsImageRenderer(size: size)
                    let resized = renderer.image { context in
                        UIColor.white.setFill()
                        context.fill(CGRect(origin: .zero, size: size))
                        image.draw(in: CGRect(origin: .zero, size: size))
                    }
                    jpeg = resized.jpegData(compressionQuality: max(0.45, 0.86 - Double(attempt) * 0.065))
                    if let jpeg, jpeg.count <= targetJPEGBytes { break }
                    scale *= 0.8
                }

                guard let jpeg, jpeg.count <= maxMessageBytes else {
                    vm.errorText = "This photo couldn't be reduced below the 5 MB MMS limit."
                    return []
                }
                aggregateBytes += jpeg.count
                guard aggregateBytes <= maxMessageBytes else {
                    vm.errorText = "Your selected photos together exceed 5 MB. Select fewer photos."
                    return []
                }
                preparedPhotos.append(jpeg)
            } catch {
                vm.errorText = "Couldn't read the selected photo. Please try again."
                return []
            }
        }

        var keys: [String] = []
        for jpeg in preparedPhotos {
            do {
                let uploaded = try await UploadService.shared.uploadImage(data: jpeg, token: token)
                guard uploaded.ok == true,
                      let key = uploaded.key,
                      key.hasPrefix("uploads/u") else {
                    vm.errorText = "Couldn't confirm the photo upload. Please try again."
                    return []
                }
                keys.append(key)
            } catch {
                vm.errorText = "Couldn't upload the photo. Please try again."
                #if DEBUG
                debugLog("❌ SMS image upload failed:", error)
                #endif
                return []
            }
        }
        return keys
    }
}

// MARK: - Messages list

private struct SMSMessagesListView: View {
    let messages: [SMSMessageDTO]
    let highlightedMessageID: Int?
    let onDeleteForMe: (SMSMessageDTO) -> Void
    let onReport: (SMSMessageDTO) -> Void
    let onBlock: (SMSMessageDTO) -> Void

    @EnvironmentObject private var themeManager: ThemeManager
    @State private var expandedTimestampMessageId: Int?

    var body: some View {
        GeometryReader { geo in
            let bubbleMaxWidth = geo.size.width * 0.72

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                            let previous: SMSMessageDTO? =
                                index > 0 ? messages[index - 1] : nil

                            if shouldShowDateSeparator(
                                previous: previous,
                                current: msg
                            ) {
                                DateSeparatorView(date: msg.createdAt)
                                    .padding(.top, index == 0 ? 14 : 30)
                                    .padding(.bottom, 10)
                            }

                            SMSMessageRowView(
                                msg: msg,
                                bubbleMaxWidth: bubbleMaxWidth,
                                isHighlighted: highlightedMessageID == msg.id,
                                isTimestampVisible: expandedTimestampMessageId == msg.id,
                                onBubbleTap: {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        expandedTimestampMessageId =
                                            expandedTimestampMessageId == msg.id
                                                ? nil
                                                : msg.id
                                    }
                                },
                                onDeleteForMe: {
                                    onDeleteForMe(msg)
                                },
                                onReport: {
                                    onReport(msg)
                                },
                                onBlock: {
                                    onBlock(msg)
                                }
                            )
                            .id(msg.id)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("BOTTOM")
                    }
                    .padding(.vertical, 14)
                    .frame(minHeight: geo.size.height, alignment: .bottom)
                }
                .background(themeManager.palette.screenBackground)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        scrollToBottom(proxy, animated: false)
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                        scrollToBottom(proxy, animated: false)
                    }
                }
                .onChange(of: messages.map(\.id)) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        scrollToBottom(proxy, animated: false)
                    }
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

    private func shouldShowDateSeparator(
        previous: SMSMessageDTO?,
        current: SMSMessageDTO
    ) -> Bool {
        guard let previous else {
            return true
        }

        return !Calendar.current.isDate(
            previous.createdAt,
            inSameDayAs: current.createdAt
        )
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
    let isTimestampVisible: Bool
    let onBubbleTap: () -> Void
    let onDeleteForMe: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if msg.isOutgoing {
                Spacer(minLength: 52)
            }

            VStack(alignment: msg.isOutgoing ? .trailing : .leading, spacing: 6) {
                if !msg.media.isEmpty {
                    SMSMediaStackView(message: msg, maxWidth: bubbleMaxWidth)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onBubbleTap()
                        }
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
                            ChatBubbleShape(
                                isMe: msg.isOutgoing,
                                groupedWithPrevious: false,
                                groupedWithNext: false
                            )
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
                        .overlay {
                            ChatBubbleShape(
                                isMe: msg.isOutgoing,
                                groupedWithPrevious: false,
                                groupedWithNext: false
                            )
                            .stroke(
                                msg.isOutgoing
                                    ? themeManager.palette.bubbleOutgoingEnd.opacity(0.15)
                                    : themeManager.palette.border.opacity(0.85),
                                lineWidth: msg.isOutgoing ? 0.4 : 0.8
                            )
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onBubbleTap()
                        }

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
                            ChatBubbleShape(
                                isMe: msg.isOutgoing,
                                groupedWithPrevious: false,
                                groupedWithNext: false
                            )
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
                        .overlay {
                            ChatBubbleShape(
                                isMe: msg.isOutgoing,
                                groupedWithPrevious: false,
                                groupedWithNext: false
                            )
                            .stroke(
                                msg.isOutgoing
                                    ? themeManager.palette.bubbleOutgoingEnd.opacity(0.15)
                                    : themeManager.palette.border.opacity(0.85),
                                lineWidth: msg.isOutgoing ? 0.4 : 0.8
                            )
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onBubbleTap()
                        }
                }

                if isTimestampVisible {
                    HStack(spacing: 6) {
                        Text(timestampText(msg.createdAt))
                            .font(.caption2)
                            .foregroundStyle(themeManager.palette.secondaryText)

                        if msg.editedAt != nil {
                            Text(
                                appText(
                                    "messages.edited",
                                    languageCode: appLanguage
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(themeManager.palette.secondaryText)
                        }
                    }
                    .padding(.horizontal, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
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
        .contextMenu {
            if let copyText = msg.trimmedBody, !copyText.isEmpty {
                Button {
                    UIPasteboard.general.string = copyText
                } label: {
                    Label(
                        appText(
                            "common.copy",
                            languageCode: appLanguage
                        ),
                        systemImage: "doc.on.doc"
                    )
                }
            }

            if msg.id > 0 && !msg.isOutgoing {
                Button {
                    onReport()
                } label: {
                    Label("Report", systemImage: "exclamationmark.bubble")
                }

                Button(role: .destructive) {
                    onBlock()
                } label: {
                    Label("Block number", systemImage: "hand.raised")
                }
            }

            if msg.id > 0 {
                Button(role: .destructive) {
                    onDeleteForMe()
                } label: {
                    Label(
                        appText(
                            "messages.deleteForMe",
                            languageCode: appLanguage
                        ),
                        systemImage: "trash"
                    )
                }
            }
        }
    }

    private func timestampText(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute()
        )
    }
}

private struct PSTNReportMessageSheet: View {
    let phone: String
    let previewText: String
    let isSubmitting: Bool

    @Binding var reason: ReportReason
    @Binding var contextCount: Int
    @Binding var details: String
    @Binding var blockAfterReport: Bool

    let onCancel: () -> Void
    let onSubmit: () -> Void

    @AppStorage("chatforia_language") private var appLanguage = "en"

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    appText(
                        "report.reason",
                        languageCode: appLanguage
                    )
                ) {
                    Picker(
                        appText(
                            "report.reason",
                            languageCode: appLanguage
                        ),
                        selection: $reason
                    ) {
                        ForEach(ReportReason.allCases) { value in
                            Text(value.title(languageCode: appLanguage))
                                .tag(value)
                        }
                    }
                }

                Section(
                    appText(
                        "report.includePreviousMessages",
                        languageCode: appLanguage
                    )
                ) {
                    Picker("Context", selection: $contextCount) {
                        Text("Only this message").tag(0)
                        Text("This plus previous 5").tag(5)
                        Text("This plus previous 10").tag(10)
                        Text("This plus previous 20").tag(20)
                    }
                    .pickerStyle(.navigationLink)
                }

                Section(
                    appText(
                        "common.additionalDetails",
                        languageCode: appLanguage
                    )
                ) {
                    TextEditor(text: $details)
                        .frame(minHeight: 120)
                }

                Section {
                    Toggle(
                        "Block this number after reporting",
                        isOn: $blockAfterReport
                    )
                }

                Section("Message being reported") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(phone)
                            .font(.subheadline.weight(.semibold))

                        Text(
                            previewText.isEmpty
                                ? "No visible text"
                                : previewText
                        )
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                    }
                }
            }
            .navigationTitle("Report message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        onCancel()
                    }
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        onSubmit()
                    }
                    .disabled(isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    ProgressView()
                }
            }
        }
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
                } else if item.isAudio {
                    SMSAudioAttachmentCard(message: message, mediaIndex: index, maxWidth: maxWidth)
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

    @AppStorage("chatforia_language") private var appLanguage = "en"
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

                        Text(
                            failed
                                ? appText(
                                    "media.couldNotLoadImage",
                                    languageCode: appLanguage
                                )
                                : title
                        )
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
        }
    }
}

private struct SMSFullscreenImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @AppStorage("chatforia_language") private var appLanguage = "en"
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
                    Button(
                        appText(
                            "common.done",
                            languageCode: appLanguage
                        )
                    ) {
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
    @AppStorage("chatforia_language") private var appLanguage = "en"

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

                Text(item.contentType?.nilIfBlank
                ?? appText(
                    "media.protectedMedia",
                    languageCode: appLanguage
                ))
                    .font(.caption)
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(
                appText(
                    "sms.inThread",
                    languageCode: appLanguage
                )
        )
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

// Each row reads playback state only when its message is the active identity.
private struct SMSAudioAttachmentCard: View {
    let message: SMSMessageDTO
    let mediaIndex: Int
    let maxWidth: CGFloat
    @EnvironmentObject private var auth: AuthStore
    @AppStorage("chatforia_language") private var appLanguage = "en"
    @StateObject private var playback = SMSAttachmentPlayback.shared
    @State private var knownDuration: Double = 0

    private var identity: String { "\(auth.currentUser?.id ?? 0):\(message.id):\(mediaIndex)" }
    private var active: Bool { playback.identity == identity }
    private var total: Double {
        let value = active && playback.duration > 0
            ? playback.duration
            : (playback.cachedDuration(for: identity) ?? knownDuration)
        return value.isFinite && value > 0 ? value : 0
    }
    private var elapsed: Double {
        let value = active ? playback.currentTime : 0
        return value.isFinite ? max(0, total > 0 ? min(value, total) : value) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    playback.toggle(identity: identity, messageID: message.id,
                        mediaIndex: mediaIndex, token: TokenStore.shared.read())
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 44, height: 44)
                        if active && playback.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: active && playback.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .offset(x: active && playback.isPlaying ? 0 : 1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(active && playback.isLoading)
                .accessibilityLabel(active && playback.isPlaying
                    ? String(localized: "audio.pause", defaultValue: "Pause voice note")
                    : String(localized: "audio.play", defaultValue: "Play voice note"))
                VStack(alignment: .leading, spacing: 7) {
                    Text(appText("composer.voiceNote", languageCode: appLanguage, fallback: "Voice note"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    ProgressView(value: elapsed, total: max(total, 1))
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                    HStack {
                        Text(AudioAttachmentCardView.formatTime(elapsed))
                        Spacer(minLength: 8)
                        Text(total > 0 ? AudioAttachmentCardView.formatTime(total) : "—:—")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }
            if active, let error = playback.errorText {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(maxWidth: min(maxWidth, 280), alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: playback.duration) { _, value in
            if active, value.isFinite, value > 0 { knownDuration = value }
        }
        .onAppear {
            playback.prefetchDuration(identity: identity, messageID: message.id,
                mediaIndex: mediaIndex, token: TokenStore.shared.read())
        }
        .onChange(of: identity) { oldValue, newValue in
            playback.stop(ifIdentity: oldValue)
            playback.cancelDurationPrefetch(identity: oldValue)
            playback.prefetchDuration(identity: newValue, messageID: message.id,
                mediaIndex: mediaIndex, token: TokenStore.shared.read())
        }
        .onDisappear {
            playback.stop(ifIdentity: identity)
            playback.cancelDurationPrefetch(identity: identity)
        }
    }
}

// SMS media endpoints are authenticated byte downloads, not seekable streams.
// Decode their actual bytes using the same AVAudioPlayer approach as local previews.
@MainActor
private final class SMSAttachmentPlayback: ObservableObject {
    static let shared = SMSAttachmentPlayback()
    @Published private(set) var identity: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var errorText: String?
    private var player: AVAudioPlayer?
    private var downloadTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var generation = 0

    // Duration lookups never own or activate an audio session. Keep only a
    // bounded in-memory cache scoped to the current signed-in session.
    @Published private var knownDurations: [String: Double] = [:]
    private var mediaBytes: [String: Data] = [:]
    private var mediaOrder: [String] = []
    private var durationOrder: [String] = []
    private var mediaTasks: [String: Task<Data, Error>] = [:]
    private var mediaRequestIDs: [String: UUID] = [:]
    private var durationInterests: Set<String> = []
    private var durationQueue: [(identity: String, messageID: Int, mediaIndex: Int, token: String)] = []
    private var durationRequests: [String: (identity: String, messageID: Int, mediaIndex: Int, token: String)] = [:]
    private var mediaAccountToken: String?
    private var mediaEpoch = 0

    func cachedDuration(for identity: String) -> Double? {
        guard mediaAccountToken == TokenStore.shared.read() else { return nil }
        return knownDurations[identity]
    }

    private func useMediaAccount(_ token: String?) {
        guard token != mediaAccountToken else { return }
        mediaEpoch += 1
        mediaTasks.values.forEach { $0.cancel() }
        mediaTasks.removeAll(); mediaRequestIDs.removeAll()
        durationQueue.removeAll(); durationInterests.removeAll(); durationRequests.removeAll()
        mediaBytes.removeAll(); mediaOrder.removeAll()
        knownDurations.removeAll(); durationOrder.removeAll()
        mediaAccountToken = token
    }

    func prefetchDuration(identity: String, messageID: Int, mediaIndex: Int, token: String?) {
        useMediaAccount(token)
        guard let token, !token.isEmpty, token == TokenStore.shared.read(),
              messageID > 0, mediaIndex >= 0 else { return }
        durationInterests.insert(identity)
        durationRequests[identity] = (identity, messageID, mediaIndex, token)
        guard knownDurations[identity] == nil, mediaTasks[identity] == nil,
              !durationQueue.contains(where: { $0.identity == identity }),
              durationQueue.count < 32 else { return }
        durationQueue.append((identity, messageID, mediaIndex, token))
        drainDurationQueue()
    }

    func cancelDurationPrefetch(identity: String) {
        durationInterests.remove(identity)
        durationRequests.removeValue(forKey: identity)
        durationQueue.removeAll { $0.identity == identity }
        if self.identity != identity { cancelMediaTask(identity) }
        drainDurationQueue()
    }

    private func cancelMediaTask(_ identity: String) {
        mediaRequestIDs.removeValue(forKey: identity)
        mediaTasks.removeValue(forKey: identity)?.cancel()
    }

    private func drainDurationQueue() {
        // At most two media fetches; explicit Play takes priority.
        while mediaTasks.count < 2, !durationQueue.isEmpty {
            let item = durationQueue.removeFirst()
            guard durationInterests.contains(item.identity),
                  item.token == TokenStore.shared.read(), knownDurations[item.identity] == nil else { continue }
            _ = mediaTask(identity: item.identity, messageID: item.messageID,
                mediaIndex: item.mediaIndex, token: item.token)
        }
    }

    private func mediaTask(identity: String, messageID: Int, mediaIndex: Int, token: String) -> Task<Data, Error> {
        if let task = mediaTasks[identity] { return task }
        let epoch = mediaEpoch
        let requestID = UUID()
        let task = Task<Data, Error> { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            defer {
                if self.mediaEpoch == epoch, self.mediaRequestIDs[identity] == requestID {
                    self.mediaTasks.removeValue(forKey: identity)
                    self.mediaRequestIDs.removeValue(forKey: identity)
                    self.drainDurationQueue()
                }
            }
            try Task.checkCancellation()
            guard self.mediaEpoch == epoch, TokenStore.shared.read() == token else { throw CancellationError() }
            let request = APIRequest(path: "sms/media/\(messageID)/\(mediaIndex)",
                method: .GET, requiresAuth: true)
            let (data, response) = try await APIClient.shared.sendRaw(request, token: token)
            try Task.checkCancellation()
            guard self.mediaEpoch == epoch, TokenStore.shared.read() == token else { throw CancellationError() }
            guard (200...299).contains(response.statusCode), !data.isEmpty else {
                throw URLError(.badServerResponse)
            }
            // Inspect bytes off the main thread. No prepareToPlay(), play(),
            // AVAudioSession activation, or shared-player replacement here.
            let measured = try await Task.detached(priority: .utility) {
                try AVAudioPlayer(data: data).duration
            }.value
            try Task.checkCancellation()
            guard self.mediaEpoch == epoch, TokenStore.shared.read() == token else { throw CancellationError() }
            guard measured.isFinite, measured > 0 else { throw URLError(.cannotDecodeContentData) }
            self.knownDurations[identity] = measured
            self.durationOrder.removeAll { $0 == identity }; self.durationOrder.append(identity)
            while self.durationOrder.count > 128 {
                self.knownDurations.removeValue(forKey: self.durationOrder.removeFirst())
            }
            // Reuse inspected bytes on Play, without unbounded media retention.
            if data.count <= 8 * 1_024 * 1_024 {
                self.mediaBytes[identity] = data
                self.mediaOrder.removeAll { $0 == identity }; self.mediaOrder.append(identity)
                while self.mediaOrder.count > 32 || self.mediaBytes.values.reduce(0, { $0 + $1.count }) > 8 * 1_024 * 1_024 {
                    self.mediaBytes.removeValue(forKey: self.mediaOrder.removeFirst())
                }
            }
            return data
        }
        mediaTasks[identity] = task; mediaRequestIDs[identity] = requestID
        return task
    }

    private func playbackBytes(identity: String, messageID: Int, mediaIndex: Int, token: String) async throws -> Data {
        useMediaAccount(token)
        guard TokenStore.shared.read() == token else { throw CancellationError() }
        if let data = mediaBytes[identity] { return data }
        durationQueue.removeAll { $0.identity == identity }
        // Prioritize an explicit Play without exceeding two media fetches.
        if mediaTasks[identity] == nil, mediaTasks.count >= 2,
           let quietIdentity = mediaTasks.keys.first(where: { $0 != identity }) {
            cancelMediaTask(quietIdentity)
            if let request = durationRequests[quietIdentity], durationQueue.count < 32,
               !durationQueue.contains(where: { $0.identity == quietIdentity }) {
                durationQueue.append(request)
            }
        }
        return try await mediaTask(identity: identity, messageID: messageID,
            mediaIndex: mediaIndex, token: token).value
    }

    func toggle(identity requested: String, messageID: Int, mediaIndex: Int, token: String?) {
        useMediaAccount(token)
        guard let token, !token.isEmpty else {
            stop(); identity = requested
            errorText = "Sign in to play this voice note."
            return
        }
        if identity == requested, isLoading { return }
        if identity == requested, let player, !isLoading {
            if player.isPlaying {
                player.pause(); timerTask?.cancel(); timerTask = nil
                currentTime = player.currentTime; isPlaying = false
            } else { play(player) }
            return
        }
        stop()
        identity = requested; isLoading = true
        let revision = generation
        downloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try await self.playbackBytes(identity: requested,
                    messageID: messageID, mediaIndex: mediaIndex, token: token)
                guard !Task.isCancelled, revision == self.generation else { return }
                guard TokenStore.shared.read() == token else { self.stop(); return }
                let player = try AVAudioPlayer(data: data)
                guard player.duration.isFinite, player.duration > 0, player.prepareToPlay() else {
                    throw URLError(.cannotDecodeContentData)
                }
                self.player = player; self.duration = player.duration
                self.isLoading = false
                self.play(player)
            } catch {
                guard !Task.isCancelled, revision == self.generation else { return }
                guard TokenStore.shared.read() == token else {
                    self.stop(); self.useMediaAccount(TokenStore.shared.read()); return
                }
                self.isLoading = false; self.isPlaying = false
                self.errorText = "Could not play this voice note. Tap Play to retry."
            }
        }
    }

    private func play(_ player: AVAudioPlayer) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            if player.currentTime >= player.duration { player.currentTime = 0 }
            guard player.play() else { throw URLError(.cannotDecodeContentData) }
            errorText = nil; isPlaying = true
            timerTask?.cancel()
            let revision = generation
            timerTask = Task { @MainActor [weak self, weak player] in
                while !Task.isCancelled {
                    guard let self, let player, revision == self.generation else { return }
                    self.currentTime = player.currentTime
                    if !player.isPlaying { self.isPlaying = false; return }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        } catch {
            isPlaying = false; errorText = "Could not play this voice note. Tap Play to retry."
        }
    }

    func stop(ifIdentity expected: String? = nil) {
        if let expected, identity != expected { return }
        generation += 1
        if let identity, !durationInterests.contains(identity) { cancelMediaTask(identity) }
        downloadTask?.cancel(); downloadTask = nil
        timerTask?.cancel(); timerTask = nil
        let hadPlayer = player != nil
        player?.stop(); player = nil
        identity = nil; isLoading = false; isPlaying = false
        currentTime = 0; duration = 0; errorText = nil
        if hadPlayer {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

// Isolated from the Chatforia recorder/composer path.
@MainActor
final class SMSVoiceNoteController: ObservableObject {
    @Published private(set) var draft: VoiceNoteDraft?
    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    @Published private(set) var isSending = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published var errorText: String?
    private let recorder = AudioRecorderService()
    private var ticker: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var ownerToken: String?
    private var uploadedURL: String?
    private var isFinalizing = false
    private var recorderCleanup: Task<Void, Never>?
    private var generation = 0

    func start(token: String?) async {
        guard !isStarting, !isRecording, !isSending, !isFinalizing, draft == nil else { return }
        guard let token, !token.isEmpty else {
            errorText = "Your session has expired. Please sign in again."
            return
        }
        let revision = generation
        isStarting = true
        errorText = nil
        ownerToken = token
        defer { isStarting = false }
        do {
            await recorderCleanup?.value
            guard revision == generation else { return }
            try await recorder.start()
            guard revision == generation, TokenStore.shared.read() == token else {
                await recorder.cancel()
                return
            }
            isRecording = true
            elapsed = 0
            let began = Date()
            ticker = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    self.elapsed = Date().timeIntervalSince(began)
                    if self.elapsed >= 60 { await self.stop(); return }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        } catch {
            guard revision == generation else { return }
            errorText = error.localizedDescription
        }
    }

    func stop() async {
        guard isRecording, !isFinalizing else { return }
        isFinalizing = true
        defer { isFinalizing = false }
        let revision = generation
        ticker?.cancel(); ticker = nil
        let completed = await recorder.stop()
        guard revision == generation else {
            if let completed { try? FileManager.default.removeItem(at: completed.fileURL) }
            return
        }
        draft = completed
        isRecording = false
        if draft == nil { errorText = "The voice recording could not be saved." }
    }

    func discard() {
        generation += 1
        ticker?.cancel(); ticker = nil
        stopPreview()
        // An in-flight permission request must finish before another start.
        if isRecording || isStarting || isFinalizing {
            let previousCleanup = recorderCleanup
            let recorder = self.recorder
            recorderCleanup = Task {
                await previousCleanup?.value
                await recorder.cancel()
            }
        }
        if let draft { try? FileManager.default.removeItem(at: draft.fileURL) }
        draft = nil; uploadedURL = nil; ownerToken = nil
        isRecording = false; elapsed = 0; errorText = nil
    }

    func togglePreview() {
        guard let draft, !isSending else { return }
        if let player, player.isPlaying {
            player.pause(); isPlaying = false
            previewTask?.cancel(); previewTask = nil
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            if player == nil { player = try AVAudioPlayer(contentsOf: draft.fileURL) }
            guard let player else { return }
            if player.currentTime >= player.duration { player.currentTime = 0 }
            guard player.play() else { throw URLError(.cannotDecodeContentData) }
            isPlaying = true
            previewTask = Task { @MainActor [weak self, weak player] in
                while !Task.isCancelled, player?.isPlaying == true {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                guard !Task.isCancelled else { return }
                self?.isPlaying = false
            }
        } catch { errorText = "The voice-note preview could not be played." }
    }

    private func stopPreview() {
        previewTask?.cancel(); previewTask = nil
        let hadPlayer = player != nil
        player?.stop(); player = nil; isPlaying = false
        if hadPlayer {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func send(token: String, deliver: (String) async -> Bool) async -> Bool {
        guard !isSending, let draft, ownerToken == token,
              TokenStore.shared.read() == token else { return false }
        let revision = generation
        isSending = true; errorText = nil
        stopPreview()
        defer { isSending = false }
        do {
            let size = try draft.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 500_000 else {
                errorText = "This recording is too large for MMS. Record a shorter voice note."
                return false
            }
            if uploadedURL == nil {
                let data = try Data(contentsOf: draft.fileURL)
                let file = try await UploadService.shared.uploadFile(data: data, token: token,
                    fileName: "voice-" + String(draft.id.uuidString.prefix(8)) + ".m4a",
                    mimeType: "audio/mp4")
                guard revision == generation, TokenStore.shared.read() == token else { return false }
                guard file.ok != false, let url = URL(string: file.url),
                      url.scheme == "https", url.host != nil,
                      url.user == nil, url.password == nil else {
                    throw URLError(.badServerResponse)
                }
                uploadedURL = file.url
            }
            guard revision == generation, TokenStore.shared.read() == token,
                  let uploadedURL else { return false }
            let sent = await deliver(uploadedURL)
            guard revision == generation else { return sent }
            guard sent else {
                errorText = "The voice note could not be confirmed as sent. Your recording is kept; check the conversation before retrying."
                return false
            }
            discard()
            return true
        } catch {
            if revision == generation { errorText = error.localizedDescription }
            return false
        }
    }
}
