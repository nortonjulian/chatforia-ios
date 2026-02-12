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
                        if let err = vm.errorText, !err.isEmpty {
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
        let token = TokenStore().read()
        await vm.loadRooms(token: token)
    }

    private var currentUserId: Int? {
        if case .loggedIn(let user) = auth.state { return user.id }
        return nil
    }

    private func roomTitle(_ room: ChatRoomDTO) -> String {
        // 1) Named room (true group chats typically)
        if let name = room.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }

        // 2) Try participant usernames (excluding me)
        let names = (room.participants ?? [])
            .filter { $0.id != currentUserId }
            .compactMap { $0.username?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !names.isEmpty {
            return names.joined(separator: ", ")
        }

        // 3) Deterministic fallback so you can see rooms differ
        return "Chat #\(room.id)"
    }

    private func roomSubtitle(_ room: ChatRoomDTO) -> String {
        if let lm = room.lastMessage {
            // Most common preview field name in your project so far:
            if let c = lm.content, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return c
            }

            // If backend uses "text" instead, this covers it (won’t compile unless field exists)
            // if let t = lm.text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }
        }
        return "Tap to open"
    }
}
