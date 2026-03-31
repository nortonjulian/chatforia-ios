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
    @StateObject private var settingsVM = SettingsViewModel()

    @State private var draft = ""
    @State private var lastMessageId: Int? = nil

    @State private var editingMessage: MessageDTO? = nil
    @State private var editDraft: String = ""

    @State private var deletingMessage: MessageDTO? = nil

    var body: some View {
        VStack(spacing: 0) {
            if let err = vm.errorText, !err.isEmpty {
                Text(err)
                    .foregroundColor(.red)
                    .padding()
            }

            messagesSection

            composer
        }
        .background(themeManager.palette.screenBackground.ignoresSafeArea())
        .navigationTitle(roomDisplayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task {
            await onLoad()
        }
        .sheet(item: $editingMessage) { msg in
            NavigationStack {
                VStack(spacing: 16) {
                    TextEditor(text: $editDraft)
                        .frame(minHeight: 180)
                        .padding(12)
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
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { @MainActor in
                                guard let msg = editingMessage else { return }

                                let ok = await vm.editMessage(
                                    message: msg,
                                    newText: editDraft,
                                    token: TokenStore.shared.read()
                                )

                                if ok {
                                    editingMessage = nil
                                    editDraft = ""
                                }
                            }
                        }
                    }
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

                if msg.sender.id == auth.currentUser?.id {
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
                MessagesListView(
                    messages: vm.messages,
                    currentUserId: auth.currentUser?.id,
                    isGroupRoom: room.isGroup == true,
                    isLoadingOlder: vm.isLoadingOlder,
                    deliveryStateForMessage: { _ in nil },
                    onLoadOlder: {
                        await vm.loadOlderMessagesIfNeeded()
                    },
                    onRetryTap: { _ in },
                    onEdit: { msg in
                        editingMessage = msg
                        editDraft = msg.rawContent ?? ""
                    },
                    onDelete: { msg in
                        deletingMessage = msg
                    },
                    onReport: { _ in },
                    lastMessageId: $lastMessageId
                )
            }
        }
    }
}

extension ChatThreadView {
    private var composer: some View {
        MessageComposerView(
            draft: $draft,
            isSending: vm.isSendingImage || vm.isSendingAudio,
            onDraftChanged: {
                vm.handleInputChanged(roomId: room.id)
            },
            onAttachmentTap: {},
            onSend: {
                Task { await send() }
            }
        )
        .environmentObject(settingsVM)
        .padding(.bottom, 6)
    }
}

extension ChatThreadView {
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
        }
    }
}

extension ChatThreadView {
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

        // Load messages first, then start socket (avoids early emit races)
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
}
