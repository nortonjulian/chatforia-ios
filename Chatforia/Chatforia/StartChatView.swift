import SwiftUI

struct StartChatView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"

    @StateObject private var vm = StartChatViewModel()
    @State private var transportContact: ContactSearchResultDTO?
    @State private var showingTransportChoice = false

    let onDestinationReady: (StartDestination) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.screenBackground
                    .ignoresSafeArea()

                Group {
                    if vm.isLoading && vm.results.isEmpty && vm.contactResults.isEmpty && vm.conversationResults.isEmpty {
                        LoadingStateView(
                            title: appText(
                                "ios.searching",
                                languageCode: appLanguage
                            ),
                            subtitle: appText(
                                "ios.looking_for_people_you_can_message",
                                languageCode: appLanguage
                            )
                        )
                    } else if let errorText = vm.errorText, !errorText.isEmpty, vm.results.isEmpty, vm.contactResults.isEmpty, vm.conversationResults.isEmpty {
                        EmptyStateView(
                            systemImage: "exclamationmark.magnifyingglass",
                            title: appText(
                                "ios.search_unavailable",
                                languageCode: appLanguage
                            ),
                            subtitle: errorText
                        )
                    } else if vm.trimmedQuery.isEmpty {
                        EmptyStateView(
                            systemImage: "person.crop.circle.badge.plus",
                            title: appText(
                                "common.startConversation",
                                languageCode: appLanguage
                            ),
                            subtitle: appText(
                                "ios.search_by_username_contact_or_phone",
                                languageCode: appLanguage
                            )
                        )
                    } else if vm.looksLikePhoneInput && vm.contactResults.isEmpty && vm.conversationResults.isEmpty,
                              let phone = vm.normalizedPhoneCandidate {
                          phoneCandidateRow(phone: phone)
                      } else if vm.results.isEmpty && vm.contactResults.isEmpty && vm.conversationResults.isEmpty {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: appText(
                                "ios.no_users_found",
                                languageCode: appLanguage
                            ),
                            subtitle: appText(
                                "ios.try_different_username_contact_or_phone",
                                languageCode: appLanguage
                            )
                        )
                    } else {
                        List {
                            if !vm.isGroupMode && !vm.conversationResults.isEmpty {
                                Section(appText("common.openConversation", languageCode: appLanguage)) {
                                    ForEach(vm.conversationResults, id: \.uniqueId) { conversation in
                                        Button {
                                            selectExistingConversation(conversation)
                                        } label: {
                                            HStack(spacing: 12) {
                                                avatarView(for: conversation.displayName ?? conversation.title)
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(conversation.displayName ?? conversation.title)
                                                        .foregroundStyle(themeManager.palette.primaryText)
                                                    Text(conversation.kind.lowercased() == "sms" ? "SMS" : "Chatforia")
                                                        .font(.footnote)
                                                        .foregroundStyle(themeManager.palette.secondaryText)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                            }
                                            .padding(.vertical, 6)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(vm.isCreating)
                                        .listRowBackground(themeManager.palette.cardBackground)
                                    }
                                }
                            }
                            if vm.looksLikePhoneInput, let phone = vm.normalizedPhoneCandidate {
                                Section(
                                    appText(
                                        "common.phoneNumber",
                                        languageCode: appLanguage
                                    )
                                ) {
                                    phoneRow(phone: phone)
                                        .listRowBackground(themeManager.palette.cardBackground)
                                }
                            }
                            
                            if !vm.contactResults.isEmpty {
                                Section(
                                    appText(
                                        "contacts.savedContacts",
                                        languageCode: appLanguage
                                    )
                                ) {
                                    ForEach(vm.contactResults) { contact in
                                        Button {
                                            if vm.isGroupMode {
                                                vm.toggleGroupContact(contact)
                                            } else {
                                                Task { await selectContact(contact) }
                                            }
                                        } label: {
                                            HStack(spacing: 12) {
                                                avatarView(for: contact.displayName)

                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(contact.displayName)
                                                        .font(.body.weight(.medium))
                                                        .foregroundStyle(themeManager.palette.primaryText)

                                                    Text(contact.externalPhone ?? (contact.user?.username.map { "@\($0)" } ?? appText(
                                                        "common.openConversation",
                                                        languageCode: appLanguage
                                                    )))
                                                        .font(.footnote)
                                                        .foregroundStyle(themeManager.palette.secondaryText)
                                                }

                                                Spacer()

                                                if vm.isCreating {
                                                    ProgressView()
                                                        .tint(themeManager.palette.accent)
                                                } else if vm.isGroupMode, let userId = contact.user?.id ?? contact.userId {
                                                    Image(
                                                        systemName: vm.isSelectedForGroup(userId: userId)
                                                            ? "checkmark.circle.fill"
                                                            : "circle"
                                                    )
                                                    .foregroundStyle(themeManager.palette.accent)
                                                } else {
                                                    Image(systemName: "chevron.right")
                                                        .foregroundStyle(.tertiary)
                                                }
                                            }
                                            .padding(.vertical, 6)
                                        }
                                        .buttonStyle(.plain)
                                        .listRowBackground(themeManager.palette.cardBackground)
                                        .disabled(vm.isCreating)
                                    }
                                }
                            }

                            Section(
                                appText(
                                    "contacts.chatforiaUsers",
                                    languageCode: appLanguage
                                )
                            ) {
                                ForEach(vm.results) { user in
                                    Button {
                                        if vm.isGroupMode {
                                            vm.toggleGroupUser(user)
                                        } else {
                                            Task { await selectUser(user) }
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            avatarView(for: user.username)

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(user.username)
                                                    .font(.body.weight(.medium))
                                                    .foregroundStyle(themeManager.palette.primaryText)

                                                Text(appText(
                                                    "contacts.startChatforiaChat",
                                                    languageCode: appLanguage
                                                ))
                                                    .font(.footnote)
                                                    .foregroundStyle(themeManager.palette.secondaryText)
                                            }

                                            Spacer()

                                            if vm.isCreating {
                                                ProgressView()
                                                    .tint(themeManager.palette.accent)
                                            } else if vm.isGroupMode {
                                                Image(
                                                    systemName: vm.isSelectedForGroup(userId: user.id)
                                                        ? "checkmark.circle.fill"
                                                        : "circle"
                                                )
                                                .foregroundStyle(themeManager.palette.accent)
                                            } else {
                                                Image(systemName: "chevron.right")
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }
                                        .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(themeManager.palette.cardBackground)
                                    .disabled(vm.isCreating)
                                }
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .listStyle(.insetGrouped)
                    }
                }
            }
            .confirmationDialog(
                appText("common.openConversation", languageCode: appLanguage),
                isPresented: $showingTransportChoice
            ) {
                if let contact = transportContact {
                    Button("Chatforia") { Task { await selectContact(contact, preferSMS: false) } }
                    Button("SMS") { Task { await selectContact(contact, preferSMS: true) } }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $vm.searchText,
                prompt: Text(
                    appText(
                        "ios.username_contact_name_or_phone_number",
                        languageCode: appLanguage
                    )
                )
            )
            .onChange(of: vm.searchText) { _, _ in
                vm.handleSearchTextChanged(currentUserId: auth.currentUser?.id)
            }
            .onChange(of: auth.currentUser?.id) { _, _ in
                vm.handleSearchTextChanged(currentUserId: auth.currentUser?.id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(appText(
                        "button_cancel",
                        languageCode: appLanguage
                    )) {
                        dismiss()
                    }
                    .foregroundStyle(themeManager.palette.accent)
                }

                ToolbarItem(placement: .principal) {
                    Text(appText(
                        "common.newConversation",
                        languageCode: appLanguage
                    ))
                        .font(.headline)
                        .foregroundStyle(themeManager.palette.primaryText)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        vm.isGroupMode
                            ? "Direct"
                            : appText("startChatModal.group", languageCode: appLanguage)
                    ) {
                        vm.isGroupMode.toggle()
                        vm.handleSearchTextChanged(currentUserId: auth.currentUser?.id)

                        if !vm.isGroupMode {
                            vm.resetGroupSelection()
                        }
                    }
                    .foregroundStyle(themeManager.palette.accent)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if vm.isGroupMode {
                    groupCreateBar
                }
            }
        }
    }
    
    
    private func selectContact(_ contact: ContactSearchResultDTO, preferSMS: Bool? = nil) async {
        let hasAppUser = (contact.user?.id ?? contact.userId) != nil
        let phone = contact.externalPhone?.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasAppUser, let phone, !phone.isEmpty, preferSMS == nil {
            transportContact = contact
            showingTransportChoice = true
            return
        }
        do {
            let destination: StartDestination
            if preferSMS == true, let phone {
                guard let token = auth.currentToken, !token.isEmpty else { throw APIError.unauthorized }
                let conversation = try await ChatRoomService.shared.startSMSThread(
                    phone: phone, contactId: contact.id, displayName: contact.displayName, token: token)
                destination = .sms(conversation)
            } else {
                destination = try await vm.destinationForContactResult(contact)
            }
            dismiss()
            onDestinationReady(destination)
        } catch {
            vm.errorText = error.localizedDescription
        }
    }

    private func phoneCandidateRow(phone: String) -> some View {
        List {
            Section(appText(
                "common.phoneNumber",
                languageCode: appLanguage
            )) {
                phoneRow(phone: phone)
                    .listRowBackground(themeManager.palette.cardBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .listStyle(.insetGrouped)
    }

    private func phoneRow(phone: String) -> some View {
        VStack(spacing: 10) {

            // Existing SMS option
            Button {
                Task { await selectPhone() }
            } label: {
                rowContent(
                    icon: "phone.fill",
                    title: phone,
                    subtitle: appText(
                        "ios.text_this_number",
                        languageCode: appLanguage
                    )
                )
            }
            .buttonStyle(.plain)

            // 🔥 NEW: Invite option
            Button {
                Task {
                    await invitePhoneNumber(phone)
                }
            } label: {
                rowContent(
                    icon: "square.and.arrow.up",
                    title: phone,
                    subtitle: appText(
                        "ios.invite_to_chatforia",
                        languageCode: appLanguage
                    )
                )
            }
            .buttonStyle(.plain)
        }
        .disabled(vm.isCreating)
    }
    
    private func rowContent(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(themeManager.palette.border)
                    .frame(width: 42, height: 42)

                Image(systemName: icon)
                    .foregroundStyle(themeManager.palette.primaryText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(themeManager.palette.primaryText)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
    
    private func invitePhoneNumber(_ phone: String) async {
        guard let token = auth.currentToken, !token.isEmpty else { return }

        do {
            let response = try await InviteService.shared.createInvite(
                targetPhone: phone,
                channel: "share_link",
                token: token
            )

            let message = InviteService.shared.createShareMessage(
                inviterUsername: auth.currentUser?.username,
                inviteURL: response.url
            )

            let av = UIActivityViewController(activityItems: [message], applicationActivities: nil)

            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.windows.first?.rootViewController {
                root.present(av, animated: true)
            }

        } catch {
            debugLog("❌ invite failed:", error)
        }
    }

    private func selectExistingConversation(_ conversation: ConversationDTO) {
        do {
            let destination = try vm.destinationForExistingConversation(conversation)
            dismiss()
            onDestinationReady(destination)
        } catch {
            vm.errorText = error.localizedDescription
        }
    }

    private func selectUser(_ user: UserSearchResultDTO) async {
        do {
            let destination = try await vm.createOrOpenDirectChat(targetUserId: user.id, displayName: user.username)
            dismiss()
            onDestinationReady(destination)
        } catch {
            vm.errorText = error.localizedDescription
        }
    }

    private func selectPhone() async {
        do {
            let destination = try await vm.createOrOpenExistingSMSThread()
            dismiss()
            onDestinationReady(destination)
        } catch {
            vm.errorText = error.localizedDescription
        }
    }

    @ViewBuilder
    private func avatarView(for text: String) -> some View {
        ZStack {
            Circle()
                .fill(themeManager.palette.border)
                .frame(width: 42, height: 42)

            Text(String(text.prefix(1)).uppercased())
                .font(.headline.weight(.semibold))
                .foregroundStyle(themeManager.palette.primaryText)
        }
    }

    private func createGroupChat() async {
        do {
            let destination = try await vm.createGroupChat()
            dismiss()
            onDestinationReady(destination)
        } catch {
            vm.errorText = error.localizedDescription
        }
    }

    private var groupCreateBar: some View {
        VStack(spacing: 10) {
            if !vm.selectedGroupUsers.isEmpty {
                TextField(
                    appText("startChatModal.groupNameOptional", languageCode: appLanguage),
                    text: $vm.groupName
                )
                .textFieldStyle(.roundedBorder)
            }

            Button {
                Task { await createGroupChat() }
            } label: {
                HStack {
                    if vm.isCreating {
                        ProgressView()
                    }

                    Text("Create group")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    vm.canCreateGroup
                        ? themeManager.palette.accent
                        : themeManager.palette.border
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!vm.canCreateGroup || vm.isCreating)

            Text("\(vm.selectedGroupUsers.count) selected")
                .font(.footnote)
                .foregroundStyle(themeManager.palette.secondaryText)
        }
        .padding()
        .background(themeManager.palette.screenBackground)
    }
}

#if DEBUG
extension StartChatView {

    func test_makeSMSConversation(
        phone: String
    ) -> ConversationDTO {

        ConversationDTO(
            kind: "sms",
            id: nil,
            title: phone,
            displayName: phone,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            isGroup: false,
            phone: phone,
            unreadCount: 0,
            avatarUsers: nil,
            last: nil
        )
    }
}
#endif
