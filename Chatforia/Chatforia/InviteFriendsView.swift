import SwiftUI

struct InviteFriendsView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("chatforia_language") private var appLanguage = "en"

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
                            appText("invite.shareInviteLink", languageCode: appLanguage),
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    .disabled(isCreatingInvite)

                    NavigationLink {
                        InvitePhoneContactsView()
                    } label: {
                        Label(
                            appText("invite.fromPhoneContacts", languageCode: appLanguage),
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
                appText("invite.title", languageCode: appLanguage)
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(appText("common.done", languageCode: appLanguage)) {
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
            errorText = appText("invite.mustBeLoggedIn", languageCode: appLanguage)
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
