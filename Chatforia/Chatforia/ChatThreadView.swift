//
//  ChatThreadView.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import SwiftUI

struct ChatThreadView: View {
    let room: ChatRoomDTO

    @EnvironmentObject var auth: AuthStore
    @StateObject private var vm = ChatThreadViewModel()

    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {

            // Messages area
            if vm.isLoading && vm.messages.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading messages…")
                        .foregroundStyle(.secondary)
                }
                .padding()
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {

                            if let err = vm.errorText {
                                Text(err)
                                    .foregroundStyle(.red)
                                    .padding(.bottom, 8)
                            }

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

            // Composer
            Divider()

            HStack(spacing: 10) {
                TextField("Message…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)

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
        .navigationTitle(room.name ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            await reload()
        }
    }

    private var currentUserId: Int? {
        if case .loggedIn(let user) = auth.state { return user.id }
        return nil
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
}

// MARK: - Bubble UI (simple Phase-1)

private struct MessageBubbleView: View {
    let msg: MessageDTO
    let isMe: Bool

    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 4) {
                // Sender label (we only have senderId right now)
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
