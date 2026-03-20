import SwiftUI

struct ChatsRootView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @StateObject private var vm = ChatsViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.screenBackground
                    .ignoresSafeArea()

                Group {
                    if vm.isLoading && vm.conversations.isEmpty {
                        LoadingStateView(
                            title: "Loading chats…",
                            subtitle: "Pulling in your latest conversations."
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    } else if let err = vm.errorText, !err.isEmpty, vm.conversations.isEmpty {
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

                    } else if vm.filteredConversations.isEmpty &&
                                !vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: "No results",
                            subtitle: "Try searching for a different name or message."
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    } else if vm.conversations.isEmpty {
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
                                .listRowBackground(themeManager.palette.cardBackground)
                            }

                            ForEach(vm.filteredConversations) { conversation in
                                NavigationLink {
                                    destinationView(for: conversation)
                                } label: {
                                    ChatListRowView(
                                        title: conversationTitle(conversation),
                                        subtitle: conversationSubtitle(conversation),
                                        timestamp: conversationTimestamp(conversation),
                                        unreadCount: conversation.unreadCount ?? 0,
                                        isPinned: false
                                    )
                                }
                                .listRowBackground(themeManager.palette.cardBackground)
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .listStyle(.insetGrouped)
                        .animation(.easeInOut(duration: 0.2), value: vm.filteredConversations.map(\.id))
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.searchText, prompt: "Search chats")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ThemedNavigationTitle(title: "Chats")
                        .environmentObject(themeManager)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .foregroundStyle(themeManager.palette.accent)
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
        let token = TokenStore.shared.read()
        await vm.loadConversations(token: token)
    }

    @ViewBuilder
    private func destinationView(for conversation: ConversationDTO) -> some View {
        switch conversation.kind.lowercased() {
        case "chat":
            ChatThreadView(room: conversation.asChatRoomDTO)
        case "sms":
            SMSThreadView(conversation: conversation)
        default:
            UnsupportedConversationView(conversation: conversation)
        }
    }

    private func conversationTitle(_ item: ConversationDTO) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }

        if item.kind.lowercased() == "sms" {
            if let phone = item.phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
                return phone
            }
            return "SMS #\(item.id)"
        }

        return "Chat #\(item.id)"
    }

    private func conversationSubtitle(_ item: ConversationDTO) -> String {
        let text = item.last?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty { return text }

        if item.kind.lowercased() == "sms" {
            return "Tap to open SMS thread"
        }

        return "Tap to open"
    }

    private func conversationTimestamp(_ item: ConversationDTO) -> String {
        if let at = item.last?.at, !at.isEmpty {
            return TimestampFormatter.chatListTimestamp(from: at)
        }

        return TimestampFormatter.chatListTimestamp(from: item.updatedAt)
    }
}

private struct UnsupportedConversationView: View {
    let conversation: ConversationDTO

    var body: some View {
        EmptyStateView(
            systemImage: "questionmark.bubble",
            title: "Unsupported conversation",
            subtitle: "Kind: \(conversation.kind)"
        )
        .navigationTitle("Conversation")
        .navigationBarTitleDisplayMode(.inline)
    }
}
