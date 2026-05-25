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
                        Label(
                            String(localized: "invite.shareInviteLink"),
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    .disabled(isCreatingInvite)

                    NavigationLink {
                        InvitePhoneContactsView()
                    } label: {
                        Label(
                            String(localized: "invite.fromPhoneContacts"),
                            systemImage: "person.crop.circle.badge.plus"
                        )
                    }
                }

                if let errorText, !errorText.isEmpty {
                    Section {
                        Text(errorText)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(
                String(localized: "invite.title")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingShareSheet) {
                ShareSheet(items: shareItems)
            }
        }
    }

    private func shareGenericInvite() async {
        guard let token = auth.currentToken, !token.isEmpty else {
            errorText = String(
                localized: "invite.mustBeLoggedIn"
            )
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
