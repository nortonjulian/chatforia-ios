import SwiftUI

struct ChatThreadView: View {
    let room: ChatRoomDTO

    @EnvironmentObject var auth: AuthStore
    @StateObject private var vm = ChatThreadViewModel()
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            errorBanner

            messagesSection

            typingBanner

            Divider()

            composer
        }
        .navigationTitle(roomDisplayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task(id: room.id) { // ✅ critical
            await reload()
        }
        .onDisappear {
            vm.stopTypingNow(roomId: room.id)
        }
    }

    // MARK: - Subviews (break up body to avoid type-check timeout)

    private var errorBanner: some View {
        Group {
            if let err = vm.errorText, !err.isEmpty {
                Text(err)
                    .foregroundStyle(.red)
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
                    ProgressView()
                    Text("Loading messages…")
                        .foregroundStyle(.secondary)
                }
                .padding()
                Spacer()
            } else if vm.messages.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text("No messages yet")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(vm.messages) { msg in
                                MessageBubbleView(
                                    msg: msg,
                                    isMe: msg.senderId == currentUserId
                                )
                                .id(msg.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: vm.messages.count) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onAppear {
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
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message…", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onChange(of: draft) { _, _ in
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
        .background(.ultraThinMaterial)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
    }

    // MARK: - Helpers

    private var currentUserId: Int? {
        if case .loggedIn(let user) = auth.state { return user.id }
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
        guard let last = vm.messages.last else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func typingIndicatorText(_ names: [String]) -> String {
        if names.count == 1 { return "\(names[0]) is typing…" }
        if names.count == 2 { return "\(names[0]) and \(names[1]) are typing…" }
        return "\(names.count) people are typing…"
    }
}

// MARK: - Bubble UI (simple Phase-1)

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
                        .foregroundStyle(.secondary)
                }

                Text(displayText)
                    .font(.body)

                if let createdAt = msg.createdAt, !createdAt.isEmpty {
                    Text(createdAt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
        if let t = msg.translatedContent, !t.isEmpty { return t }
        if let r = msg.rawContent, !r.isEmpty { return r }
        if let c = msg.contentCiphertext, !c.isEmpty { return "🔒 Encrypted message" }
        return "—"
    }
}
