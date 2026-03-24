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

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.screenBackground
                    .ignoresSafeArea()

                content
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
                            Task {
                                await open(contact)
                            }
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
                do {
                    struct Request: Encodable {
                        let phone: String
                    }

                    let body = try JSONEncoder().encode(Request(phone: externalPhone))

                    let thread: SMSStartThreadResponseDTO = try await APIClient.shared.send(
                        APIRequest(path: "sms/threads/start", method: .POST, body: body, requiresAuth: true),
                        token: auth.currentToken
                    )

                    selectedSMSConversation = ConversationDTO(
                        kind: "sms",
                        id: thread.id,
                        title: thread.displayName ?? thread.contactName ?? thread.contactPhone ?? externalPhone,
                        updatedAt: thread.updatedAt ?? ISO8601DateFormatter().string(from: Date()),
                        isGroup: false,
                        phone: thread.contactPhone ?? externalPhone,
                        unreadCount: 0,
                        last: nil
                    )
                    showSelectedSMS = true
                    return
                } catch {
                    vm.errorText = error.localizedDescription
                    return
                }
            }

            let room = try await vm.openDirectChat(for: contact, token: auth.currentToken)
            selectedRoom = room
            showSelectedRoom = true
        } catch {
            vm.errorText = error.localizedDescription
        }
    }
}
