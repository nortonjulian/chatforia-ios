import SwiftUI

struct StartChatView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager

    @StateObject private var vm = StartChatViewModel()

    let onDestinationReady: (StartDestination) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.screenBackground
                    .ignoresSafeArea()

                Group {
                    if vm.isLoading && vm.results.isEmpty {
                        LoadingStateView(
                            title: String(localized: "ios.searching"),
                            subtitle: String(localized: "ios.looking_for_people_you_can_message")
                        )
                    } else if let errorText = vm.errorText, !errorText.isEmpty, vm.results.isEmpty {
                        EmptyStateView(
                            systemImage: "exclamationmark.magnifyingglass",
                            title: String(localized: "ios.search_unavailable"),
                            subtitle: errorText
                        )
                    } else if vm.trimmedQuery.isEmpty {
                        EmptyStateView(
                            systemImage: "person.crop.circle.badge.plus",
                            title: String(localized: "common.startConversation"),
                            subtitle: String(localized: "ios.search_by_username_contact_or_phone")
                        )
                    } else if vm.looksLikePhoneInput && vm.contactResults.isEmpty,
                              let phone = vm.normalizedPhoneCandidate {
                          phoneCandidateRow(phone: phone)
                      } else if vm.results.isEmpty && vm.contactResults.isEmpty {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: String(localized: "ios.no_users_found"),
                            subtitle: String(localized: "ios.try_different_username_contact_or_phone")
                        )
                    } else {
                        List {
                            if vm.looksLikePhoneInput, let phone = vm.normalizedPhoneCandidate {
                                Section(String(localized: "common.phoneNumber")) {
                                    phoneRow(phone: phone)
                                        .listRowBackground(themeManager.palette.cardBackground)
                                }
                            }
                            
                            if !vm.contactResults.isEmpty {
                                Section(String(localized: "contacts.savedContacts")) {
                                    ForEach(vm.contactResults) { contact in
                                        Button {
                                            Task { await selectContact(contact) }
                                        } label: {
                                            HStack(spacing: 12) {
                                                avatarView(for: contact.displayName)

                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(contact.displayName)
                                                        .font(.body.weight(.medium))
                                                        .foregroundStyle(themeManager.palette.primaryText)

                                                    Text(contact.externalPhone ?? (contact.user?.username.map { "@\($0)" } ?? String(localized: "common.openConversation")))
                                                        .font(.footnote)
                                                        .foregroundStyle(themeManager.palette.secondaryText)
                                                }

                                                Spacer()

                                                if vm.isCreating {
                                                    ProgressView()
                                                        .tint(themeManager.palette.accent)
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

                            Section(String(localized: "contacts.chatforiaUsers")) {
                                ForEach(vm.results) { user in
                                    Button {
                                        Task { await selectUser(user) }
                                    } label: {
                                        HStack(spacing: 12) {
                                            avatarView(for: user.username)

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(user.username)
                                                    .font(.body.weight(.medium))
                                                    .foregroundStyle(themeManager.palette.primaryText)

                                                Text(String(localized: "contacts.startChatforiaChat"))
                                                    .font(.footnote)
                                                    .foregroundStyle(themeManager.palette.secondaryText)
                                            }

                                            Spacer()

                                            if vm.isCreating {
                                                ProgressView()
                                                    .tint(themeManager.palette.accent)
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
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $vm.searchText,
                prompt: Text("ios.username_contact_name_or_phone_number")
            )
            .onChange(of: vm.searchText) { _, _ in
                vm.handleSearchTextChanged(currentUserId: auth.currentUser?.id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "button_cancel")) {
                        dismiss()
                    }
                    .foregroundStyle(themeManager.palette.accent)
                }

                ToolbarItem(placement: .principal) {
                    Text(String(localized: "common.newConversation"))
                        .font(.headline)
                        .foregroundStyle(themeManager.palette.primaryText)
                }
            }
        }
    }
    
    private func selectContact(_ contact: ContactSearchResultDTO) async {
        do {
            let destination = try await vm.destinationForContactResult(contact)
            dismiss()
            onDestinationReady(destination)
        } catch {
            vm.errorText = error.localizedDescription
        }
    }

    private func phoneCandidateRow(phone: String) -> some View {
        List {
            Section(String(localized: "common.phoneNumber")) {
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
                    subtitle: String(localized: "ios.text_this_number")
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
                    subtitle: String(localized: "ios.invite_to_chatforia")
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
            print("❌ invite failed:", error)
        }
    }

    private func selectUser(_ user: UserSearchResultDTO) async {
        do {
            let destination = try await vm.createOrOpenDirectChat(targetUserId: user.id)
            dismiss()
            onDestinationReady(destination)
        } catch {
            vm.errorText = error.localizedDescription
        }
    }

    private func selectPhone() async {
        guard let phone = vm.normalizedPhoneCandidate else {
            vm.errorText = String(localized: "ios.invalid_phone_number")
            return
        }

        let conversation = ConversationDTO(
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

        dismiss()
        onDestinationReady(.sms(conversation))
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
}
