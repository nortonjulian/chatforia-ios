import SwiftUI

struct InvitePhoneContactsView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var viewModel = ImportPhoneContactsViewModel()

    @State private var isCreatingInvite = false
    @State private var shareItems: [Any] = []
    @State private var isShowingShareSheet = false
    @State private var inviteErrorText: String?

    var body: some View {
        List {
            Section {
                if viewModel.isLoading {
                    ProgressView("Loading contacts...")
                } else if viewModel.contacts.isEmpty {
                    Text("No phone contacts found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.contacts) { contact in
                        Button {
                            viewModel.toggle(contact)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(contact.displayName)
                                    Text(contact.phoneNumber)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if viewModel.selectedIDs.contains(contact.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let inviteErrorText, !inviteErrorText.isEmpty {
                Section {
                    Text(inviteErrorText)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Invite Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !viewModel.contacts.isEmpty {
                    Button("All") { viewModel.selectAll() }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await inviteSelected() }
                } label: {
                    if isCreatingInvite {
                        ProgressView()
                    } else {
                        Text("Invite")
                    }
                }
                .disabled(isCreatingInvite || viewModel.selectedIDs.isEmpty)
            }
        }
        .task {
            if viewModel.contacts.isEmpty {
                await viewModel.loadContacts()
            }
        }
        .sheet(isPresented: $isShowingShareSheet) {
            ShareSheet(items: shareItems)
        }
    }

    private func inviteSelected() async {
        guard let token = auth.currentToken, !token.isEmpty else {
            inviteErrorText = "You need to be logged in to create invites."
            return
        }

        let selectedContacts = viewModel.selectedContacts
        guard !selectedContacts.isEmpty else {
            inviteErrorText = "Select at least one contact."
            return
        }

        isCreatingInvite = true
        inviteErrorText = nil
        defer { isCreatingInvite = false }

        do {
            var messages: [String] = []

            for contact in selectedContacts {
                let response = try await InviteService.shared.createInvite(
                    targetPhone: contact.phoneNumber,
                    channel: "share_link",
                    token: token
                )

                let message = InviteService.shared.createShareMessage(
                    inviterUsername: auth.currentUser?.username,
                    inviteURL: response.url
                )
                messages.append("\(contact.displayName): \(message)")
            }

            shareItems = [messages.joined(separator: "\n\n")]
            isShowingShareSheet = true
        } catch {
            inviteErrorText = error.localizedDescription
        }
    }
}
