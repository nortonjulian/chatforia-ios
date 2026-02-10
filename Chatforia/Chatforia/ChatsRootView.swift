//
//  ChatsRootView.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import SwiftUI

struct ChatsRootView: View {
    @EnvironmentObject var auth: AuthStore
    @StateObject private var vm = ChatsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.rooms.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading chats…")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    List {
                        if let err = vm.errorText {
                            Text(err)
                                .foregroundStyle(.red)
                        }

                        ForEach(vm.rooms) { room in
                            NavigationLink {
                                ChatThreadView(room: room)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(roomTitle(room))
                                        .font(.headline)

                                    Text(roomSubtitle(room))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Chats")
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
            .refreshable {
                await reload()
            }
        }
    }

    private func reload() async {
        // Reads token from your same TokenStore used in AuthStore
        let token = TokenStore().read()
        await vm.loadRooms(token: token)
    }

    private func roomTitle(_ room: ChatRoomDTO) -> String {
        if let name = room.name, !name.isEmpty { return name }
        if room.isGroup == true { return "Group chat" }

        // Fallback: show participant usernames (excluding me if possible)
        let meId: Int? = {
            if case .loggedIn(let user) = auth.state { return user.id }
            return nil
        }()

        let names = (room.participants ?? [])
            .filter { $0.id != meId }
            .compactMap { $0.username }
            .filter { !$0.isEmpty }

        if !names.isEmpty { return names.joined(separator: ", ") }
        return "Chat"
    }

    private func roomSubtitle(_ room: ChatRoomDTO) -> String {
        if let msg = room.lastMessage?.content, !msg.isEmpty { return msg }
        return "Tap to open"
    }
}

