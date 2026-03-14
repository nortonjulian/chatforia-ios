import SwiftUI

struct ChatsRootView: View {
    @EnvironmentObject var auth: AuthStore
    @StateObject private var vm = ChatsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.rooms.isEmpty {
                    LoadingStateView(
                        title: "Loading chats…",
                        subtitle: "Pulling in your latest conversations."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                } else if let err = vm.errorText, !err.isEmpty, vm.rooms.isEmpty {
                    EmptyStateView(
                        systemImage: "exclamationmark.bubble",
                        title: "Couldn’t load chats",
                        subtitle: err,
                        buttonTitle: "Try Again",
                        buttonAction: {
                            Task { await reload() }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                } else if vm.filteredRooms.isEmpty && !vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmptyStateView(
                        systemImage: "magnifyingglass",
                        title: "No results",
                        subtitle: "Try searching for a different name or message."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                } else if vm.rooms.isEmpty {
                    EmptyStateView(
                        systemImage: "bubble.left.and.bubble.right",
                        title: "No chats yet",
                        subtitle: "Your conversations will show up here once you start messaging."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                } else {
                    List {
                        if let err = vm.errorText, !err.isEmpty {
                            Section {
                                Text(err)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }

                        ForEach(vm.filteredRooms) { room in
                            NavigationLink {
                                ChatThreadView(room: room)
                            } label: {
                                ChatListRowView(
                                    title: roomTitle(room),
                                    subtitle: roomSubtitle(room),
                                    timestamp: roomTimestamp(room),
                                    unreadCount: 0,
                                    isPinned: false
                                )
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .animation(.easeInOut(duration: 0.2), value: vm.filteredRooms.map(\.id))
                }
            }
            .navigationTitle("Chats")
            .searchable(text: $vm.searchText, prompt: "Search chats")
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
        if let name = room.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
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

    private func roomSubtitle(_ room: ChatRoomDTO) -> String {
        guard let lm = room.lastMessage else { return "Tap to open" }

        if let content = lm.content?.trimmingCharacters(in: .whitespacesAndNewlines),
           !content.isEmpty {
            return content
        }

        return "Tap to open"
    }

    private func roomTimestamp(_ room: ChatRoomDTO) -> String {
        if let createdAt = room.lastMessage?.createdAt {
            return TimestampFormatter.chatListTimestamp(from: createdAt)
        }

        if let updatedAt = room.updatedAt {
            return TimestampFormatter.chatListTimestamp(from: updatedAt)
        }

        return ""
    }
}
