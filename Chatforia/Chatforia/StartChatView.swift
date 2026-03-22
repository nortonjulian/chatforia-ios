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
                            title: "Searching…",
                            subtitle: "Looking for people you can message."
                        )
                    } else if let errorText = vm.errorText, !errorText.isEmpty, vm.results.isEmpty {
                        EmptyStateView(
                            systemImage: "exclamationmark.magnifyingglass",
                            title: "Search unavailable",
                            subtitle: errorText
                        )
                    } else if vm.trimmedQuery.isEmpty {
                        EmptyStateView(
                            systemImage: "person.crop.circle.badge.plus",
                            title: "Start a conversation",
                            subtitle: "Search by username, contact name, or phone number."
                        )
                    } else if vm.looksLikePhoneInput && vm.contactResults.isEmpty,
                              let phone = vm.normalizedPhoneCandidate {
                          phoneCandidateRow(phone: phone)
                      } else if vm.results.isEmpty && vm.contactResults.isEmpty {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: "No users found",
                            subtitle: "Try a different username, contact name, or phone number."
                        )
                    } else {
                        List {
                            if vm.looksLikePhoneInput, let phone = vm.normalizedPhoneCandidate {
                                Section("Phone number") {
                                    phoneRow(phone: phone)
                                        .listRowBackground(themeManager.palette.cardBackground)
                                }
                            }
                            
                            if !vm.contactResults.isEmpty {
                                Section("Saved contacts") {
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

                                                    Text(contact.externalPhone ?? (contact.user?.username.map { "@\($0)" } ?? "Open conversation"))
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

                            Section("Chatforia users") {
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

                                                Text("Start Chatforia chat")
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
            .searchable(text: $vm.searchText, prompt: "Username, contact name, or phone number")
            .onChange(of: vm.searchText) { _, _ in
                vm.handleSearchTextChanged(currentUserId: auth.currentUser?.id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(themeManager.palette.accent)
                }

                ToolbarItem(placement: .principal) {
                    Text("New Conversation")
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
            Section("Phone number") {
                phoneRow(phone: phone)
                    .listRowBackground(themeManager.palette.cardBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .listStyle(.insetGrouped)
    }

    private func phoneRow(phone: String) -> some View {
        Button {
            Task { await selectPhone() }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(themeManager.palette.border)
                        .frame(width: 42, height: 42)

                    Image(systemName: "phone.fill")
                        .foregroundStyle(themeManager.palette.primaryText)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(phone)
                        .font(.body.weight(.medium))
                        .foregroundStyle(themeManager.palette.primaryText)

                    Text("Text this number")
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
        .disabled(vm.isCreating)
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
        do {
            let destination = try await vm.createOrOpenSMSDestination()
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
}
