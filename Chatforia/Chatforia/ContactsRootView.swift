import SwiftUI

struct ContactsRootView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @StateObject private var vm = ContactsViewModel()

    @State private var selectedRoom: ChatRoomDTO? = nil
    @State private var showSelectedRoom = false
    @State private var selectedSMSConversation: ConversationDTO? = nil
    @State private var showSelectedSMS = false

    @State private var showingStartChat = false
    @State private var showingAddContact = false
    @State private var showingImportContacts = false
    
    @State private var showingInviteFriends = false
    @State private var selectedContact: ContactDTO? = nil
    
    @EnvironmentObject private var callManager: CallManager

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.screenBackground
                    .ignoresSafeArea()

                content
            }
            .navigationDestination(item: $selectedContact) { contact in
                ContactDetailView(contact: contact) { action in
                    Task {
                        await handleContactAction(action, for: contact)
                    }
                }
                .environmentObject(auth)
                .environmentObject(themeManager)
            }
            .navigationDestination(isPresented: $showSelectedSMS) {
                if let conversation = selectedSMSConversation {
                    SMSThreadView(conversation: conversation)
                }
            }
            .navigationTitle("Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.searchText, prompt: "Search contacts")
            .onChange(of: vm.searchText) { _, _ in
                Task { await reload() }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingStartChat = true
                        } label: {
                            Label("New Conversation", systemImage: "plus.bubble")
                        }

                        Button {
                            showingAddContact = true
                        } label: {
                            Label("Add Contact", systemImage: "person.badge.plus")
                        }

                        Button {
                            showingImportContacts = true
                        } label: {
                            Label("Import from Phone", systemImage: "square.and.arrow.down")
                        }
                        
                        Button {
                            showingInviteFriends = true
                        } label: {
                            Label("Invite Friends", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(themeManager.palette.accent)
                    }

                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .foregroundStyle(themeManager.palette.accent)
                }
            }
            .sheet(isPresented: $showingStartChat) {
                StartChatView { destination in
                    switch destination {
                    case .chat(let room):
                        selectedRoom = room
                        showSelectedRoom = true

                    case .sms(let conversation):
                        selectedSMSConversation = conversation
                        showSelectedSMS = true
                    }
                }
                .environmentObject(auth)
                .environmentObject(themeManager)
            }
            .sheet(isPresented: $showingAddContact) {
                AddContactView { _ in
                    Task { await reload() }
                }
                .environmentObject(auth)
                .environmentObject(themeManager)
            }
            .sheet(isPresented: $showingImportContacts) {
                ImportPhoneContactsView {
                    Task { await reload() }
                }
                .environmentObject(auth)
                .environmentObject(themeManager)
            }
            .sheet(isPresented: $showingInviteFriends) {
                InviteFriendsView()
                    .environmentObject(auth)
            }
            .task {
                await reload()
            }
            .refreshable {
                await reload()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if vm.isLoading && vm.contacts.isEmpty {
                LoadingStateView(
                    title: "Loading contacts…",
                    subtitle: "Pulling in your saved people."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if let errorText = vm.errorText, !errorText.isEmpty, vm.contacts.isEmpty {
                EmptyStateView(
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    title: "Couldn’t load contacts",
                    subtitle: errorText,
                    buttonTitle: "Try Again",
                    buttonAction: {
                        Task { await reload() }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if vm.contacts.isEmpty && !vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No contacts found",
                    subtitle: "Try a different name or username."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if vm.contacts.isEmpty {
                EmptyStateView(
                    systemImage: "person.2",
                    title: "No contacts yet",
                    subtitle: "Add contacts manually, import them from your phone, or start a new conversation.",
                    buttonTitle: "New Conversation",
                    buttonAction: {
                        showingStartChat = true
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                List {
                    ForEach(vm.contacts) { contact in
                        Button {
                            selectedContact = contact
                        } label: {
                            ContactRowView(
                                title: vm.displayName(for: contact),
                                subtitle: vm.subtitle(for: contact),
                                favorite: contact.favorite ?? false
                            )
                            .environmentObject(themeManager)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(themeManager.palette.cardBackground)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .listStyle(.insetGrouped)
            }
        }
    }
    
    private func reload() async {
        await vm.loadContacts(token: auth.currentToken)
    }
    
    private func open(_ contact: ContactDTO) async {
        do {
            if let externalPhone = contact.externalPhone, !externalPhone.isEmpty {
                let resolvedTitle = vm.displayName(for: contact)

                selectedSMSConversation = ConversationDTO(
                    kind: "sms",
                    id: nil,
                    title: resolvedTitle,
                    displayName: resolvedTitle,
                    updatedAt: ISO8601DateFormatter().string(from: Date()),
                    isGroup: false,
                    phone: externalPhone,
                    unreadCount: 0,
                    avatarUsers: [
                        ConversationAvatarUserDTO(
                            id: 0,
                            username: resolvedTitle,
                            displayName: resolvedTitle,
                            avatarUrl: nil
                        )
                    ],
                    last: nil
                )
                showSelectedSMS = true
                return
            }

            let room = try await vm.openDirectChat(for: contact, token: auth.currentToken)
            selectedRoom = room
            showSelectedRoom = true
        } catch {
            vm.errorText = error.localizedDescription
        }
    }
    
    private func handleContactAction(_ action: ContactDetailAction, for contact: ContactDTO) async {
        switch action {
        case .message:
            await open(contact)

        case .call:
            guard let phone = contact.externalPhone?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !phone.isEmpty else {
                vm.errorText = "Invalid phone number"
                return
            }

            callManager.startCall(
                to: .phoneNumber(phone, displayName: vm.displayName(for: contact)),
                auth: auth
            )

        case .video:
            guard let calleeId = contact.user?.id else {
                vm.errorText = "This contact does not support video calls"
                return
            }

            callManager.startVideoCall(
                to: .appUser(
                    userId: calleeId,
                    username: vm.displayName(for: contact)
                ),
                auth: auth
            )
        }
    }
}
