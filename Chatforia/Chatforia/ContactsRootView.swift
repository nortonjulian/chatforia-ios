import SwiftUI

struct ContactsRootView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"
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
    
    @State private var contactToDelete: ContactDTO? = nil
    @State private var showingDeleteContactAlert = false
    @State private var contactToEdit: ContactDTO? = nil
    
    @EnvironmentObject private var callManager: CallManager

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.screenBackground
                    .ignoresSafeArea()

                content
            }
            .navigationDestination(item: $selectedContact) { contact in
                ContactDetailView(
                    contact: contact,
                    onAction: { action in
                        Task {
                            await handleContactAction(action, for: contact)
                        }
                    },
                    onEdit: {
                        contactToEdit = contact
                    }
                )
                .environmentObject(auth)
                .environmentObject(themeManager)
            }
            .navigationDestination(isPresented: $showSelectedSMS) {
                if let conversation = selectedSMSConversation {
                    SMSThreadView(conversation: conversation)
                }
            }
            .navigationDestination(isPresented: $showSelectedRoom) {
                if let room = selectedRoom {
                    ChatThreadView(room: room, randomSession: nil)
                        .environmentObject(auth)
                        .environmentObject(themeManager)
                        .environmentObject(callManager)
                }
            }
            .navigationTitle(
                appText(
                    "tab_contacts",
                    languageCode: appLanguage
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $vm.searchText,
                prompt: appText(
                    "ios.search_contacts",
                    languageCode: appLanguage
                )
            )
            .onChange(of: vm.searchText) { _, _ in
                Task { await reload() }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingStartChat = true
                        } label: {
                            Label(
                                appText(
                                    "common.newConversation",
                                    languageCode: appLanguage
                                ), systemImage: "plus.bubble")
                        }

                        Button {
                            showingAddContact = true
                        } label: {
                            Label(
                                appText(
                                    "contacts.addContact",
                                    languageCode: appLanguage
                                ),
                                systemImage: "person.badge.plus"
                            )

                        }

                        Button {
                            showingImportContacts = true
                        } label: {
                            Label(appText(
                                "common.importFromPhone",
                                languageCode: appLanguage
                            ), systemImage: "square.and.arrow.down")
                        }
                        
                        Button {
                            showingInviteFriends = true
                        } label: {
                            Label(
                                appText(
                                    "ios.invite_friends",
                                    languageCode: appLanguage
                                ),
                                systemImage: "square.and.arrow.up"
                            )
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
            .sheet(item: $contactToEdit) { contact in
                AddContactView(
                    initialMode: contact.user?.username != nil ? .username : .phone,
                    initialUsername: contact.user?.username ?? "",
                    initialPhoneNumber: contact.externalPhone ?? "",
                    initialExternalName: contact.externalName ?? "",
                    initialAlias: contact.alias ?? "",
                    initialFavorite: contact.favorite ?? false
                ) { _ in
                    contactToEdit = nil
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
            .alert(
                appText("ios.delete_contact", languageCode: appLanguage),
                isPresented: $showingDeleteContactAlert
            ) {
                Button(appText("common.cancel", languageCode: appLanguage), role: .cancel) {
                    contactToDelete = nil
                }

                Button(appText("common.delete", languageCode: appLanguage), role: .destructive) {
                    guard let contact = contactToDelete else { return }

                    Task {
                        await vm.deleteContact(contact, token: auth.currentToken)
                        contactToDelete = nil
                    }
                }
            } message: {
                Text(appText("ios.delete_contact_confirmation", languageCode: appLanguage))
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
                    title: appText(
                            "ios.loading_contacts",
                            languageCode: appLanguage
                        ),
                    subtitle: appText(
                        "ios.pulling_in_your_saved_people",
                        languageCode: appLanguage
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if let errorText = vm.errorText, !errorText.isEmpty, vm.contacts.isEmpty {
                EmptyStateView(
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    title: appText(
                        "ios.couldn_t_load_contacts",
                        languageCode: appLanguage
                    ),
                    subtitle: errorText,
                    buttonTitle: appText(
                        "common.tryAgain",
                        languageCode: appLanguage
                    ),
                    buttonAction: {
                        Task { await reload() }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if vm.contacts.isEmpty && !vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: appText(
                        "ios.no_contacts_found",
                        languageCode: appLanguage
                    ),
                    subtitle: appText(
                        "ios.try_a_different_name_or_username",
                        languageCode: appLanguage
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if vm.contacts.isEmpty {
                EmptyStateView(
                    systemImage: "person.2",
                    title: appText(
                        "ios.no_contacts_yet",
                        languageCode: appLanguage
                    ),
                    subtitle: appText(
                        "ios.add_contacts_manually_import_from_phone_or_start_new_conversation",
                        languageCode: appLanguage
                    ),
                    buttonTitle: appText(
                        "common.newConversation",
                        languageCode: appLanguage
                    ),
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
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                contactToDelete = contact
                                showingDeleteContactAlert = true
                            } label: {
                                Label(
                                    appText("common.delete", languageCode: appLanguage),
                                    systemImage: "trash"
                                )
                            }
                        }
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
            if let userId = contact.user?.id ?? contact.userId {
                callManager.startCall(
                    to: .appUser(
                        userId: userId,
                        username: vm.displayName(for: contact)
                    ),
                    auth: auth
                )
                return
            }

            guard let phone = contact.externalPhone?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !phone.isEmpty else {
                vm.errorText = appText("ios.invalid_phone_number", languageCode: appLanguage)
                return
            }

            callManager.startCall(
                to: .phoneNumber(phone, displayName: vm.displayName(for: contact)),
                auth: auth
            )

        case .video:
            guard let calleeId = contact.user?.id else {
                vm.errorText = appText(
                    "ios.contact_does_not_support_video_calls",
                    languageCode: appLanguage
                )
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
