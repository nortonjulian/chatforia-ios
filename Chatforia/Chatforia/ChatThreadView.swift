// ChatThreadView.swift
import SwiftUI

struct ChatThreadView: View {
    let room: ChatRoomDTO

    @EnvironmentObject var auth: AuthStore
    @StateObject private var vm = ChatThreadViewModel()
    @State private var draft = ""

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            errorBanner
            messagesSection
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            typingBanner
            Divider()
            composer
        }
        .navigationTitle(roomDisplayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task(id: room.id) {
            vm.configureRoom(roomId: room.id)
            await reload()
            await vm.resyncIfNeeded(token: TokenStore().read())
            vm.startSocket(roomId: room.id, token: TokenStore().read(), myUsername: currentUsername)
            vm.startExpiryLoop()
        }
        .onDisappear {
            vm.stopTypingNow(roomId: room.id)
            vm.stopSocket()
            vm.stopExpiryLoop()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await vm.resyncIfNeeded(token: TokenStore().read()) }
                vm.startExpiryLoop()
            } else {
                vm.stopTypingNow(roomId: room.id)
                vm.stopExpiryLoop()
            }
        }
        .onReceive(SocketManager.shared.$isConnected) { connected in
            guard connected else { return }
            Task { await vm.resyncIfNeeded(token: TokenStore().read()) }
        }
    }

    // MARK: - Subviews / helpers

    private var errorBanner: some View {
        Group {
            if let err = vm.errorText, !err.isEmpty {
                Text(err)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
        }
    }

    private var messagesSection: some View {
        Group {
            if vm.isLoading && vm.messages.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Loading messages…")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()

            } else if vm.messages.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text("No messages yet")
                        .foregroundColor(.secondary)
                    Spacer()
                }

            } else {
                let sortedMessages = vm.messages.sorted(by: { $0.id < $1.id })

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(sortedMessages) { msg in
                                MessageBubbleView(
                                    msg: msg,
                                    isMe: (msg.sender?.id ?? msg.senderId) == currentUserId
                                )
                                .id(msg.id)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("BOTTOM")
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                    }
                    .onAppear {
                        scrollToBottom(proxy)
                    }
                    .onChange(of: vm.messages.count) { _ in
                        scrollToBottom(proxy)
                    }
                }
            }
        }
    }

    private var typingBanner: some View {
        Group {
            if !vm.typingUsernames.isEmpty {
                Text(typingIndicatorText(vm.typingUsernames))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            // single-line TextField for broad compatibility
            TextField("Message…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onChange(of: draft) { _ in
                    vm.handleInputChanged(roomId: room.id)
                }

            Button {
                Task { await send() }
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(.thinMaterial)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
    }

    // MARK: - Helpers used by the view

    private var currentUserId: Int? {
        if case .loggedIn(let user) = auth.state { return user.id }
        return nil
    }

    private var currentUsername: String? {
        if case .loggedIn(let user) = auth.state { return user.username }
        return nil
    }

    private var roomDisplayTitle: String {
        if let n = room.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !n.isEmpty {
            return n
        }
        return "Chat"
    }

    private func reload() async {
        let token = TokenStore().read()
        await vm.loadMessages(roomId: room.id, token: token)
    }

    private func send() async {
        let token = TokenStore().read()
        let text = draft
        draft = ""
        await vm.sendMessage(roomId: room.id, token: token, text: text)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo("BOTTOM", anchor: .bottom)
        }
    }

    private func typingIndicatorText(_ names: [String]) -> String {
        if names.count == 1 { return "\(names[0]) is typing…" }
        if names.count == 2 { return "\(names[0]) and \(names[1]) are typing…" }
        return "\(names.count) people are typing…"
    }
}

// MARK: - Message Bubble

private struct MessageBubbleView: View {
    let msg: MessageDTO
    let isMe: Bool

    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 4) {
                if let sid = msg.senderId {
                    Text("User \(sid)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(displayText)
                    .font(.body)

                if let createdAt = msg.createdAt, !createdAt.isEmpty {
                    Text(createdAt)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if !isMe { Spacer(minLength: 40) }
        }
    }

    private var displayText: String {
        if (msg.deletedForAll ?? false) { return "This message was deleted" }

        if let t = msg.translatedForMe, !t.isEmpty { return t }
        if let t = msg.translatedContent, !t.isEmpty { return t }
        if let r = msg.rawContent, !r.isEmpty { return r }
        if msg.contentCiphertext != nil { return "🔒 Encrypted message" }
        return "—"
    }
}
