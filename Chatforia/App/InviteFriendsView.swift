import SwiftUI

struct InviteFriendsView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var isCreatingInvite = false
    @State private var errorText: String?
    @State private var shareItems: [Any] = []
    @State private var isShowingShareSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await shareGenericInvite() }
                    } label: {
                        Label("Share My Invite Link", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isCreatingInvite)

                    NavigationLink {
                        InvitePhoneContactsView()
                    } label: {
                        Label("Invite from Phone Contacts", systemImage: "person.crop.circle.badge.plus")
                    }
                }

                if let errorText, !errorText.isEmpty {
                    Section {
                        Text(errorText)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Invite Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingShareSheet) {
                ShareSheet(items: shareItems)
            }
        }
    }

    private func shareGenericInvite() async {
        guard let token = auth.currentToken, !token.isEmpty else {
            errorText = "You need to be logged in to create an invite."
            return
        }

        isCreatingInvite = true
        errorText = nil
        defer { isCreatingInvite = false }

        do {
            let response = try await InviteService.shared.createInvite(token: token)
            let username = auth.currentUser?.username
            let message = InviteService.shared.createShareMessage(
                inviterUsername: username,
                inviteURL: response.url
            )

            shareItems = [message]
            isShowingShareSheet = true
        } catch {
            errorText = error.localizedDescription
        }
    }
}
