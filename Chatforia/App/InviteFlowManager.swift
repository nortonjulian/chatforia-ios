import Foundation
import Combine

@MainActor
final class InviteFlowManager: ObservableObject {
    static let shared = InviteFlowManager()

    @Published var lastInviterUsername: String?
    @Published var isRedeeming = false
    @Published var redemptionMessage: String?
    @Published var redemptionError: String?

    private init() {}

    func handleIncomingURL(_ url: URL) {
        guard let code = InviteLinkHandler.extractPeopleInviteCode(from: url) else { return }
        PendingInviteStore.shared.save(code: code)

        Task {
            do {
                let preview = try await InviteService.shared.previewInvite(code: code)
                let inviterUserId = preview.invite.inviterUser?.id
                let inviterUsername = preview.invite.inviterUser?.username
                PendingInviteStore.shared.savePreview(
                    inviterUserId: inviterUserId,
                    inviterUsername: inviterUsername
                )
                await MainActor.run {
                    self.lastInviterUsername = inviterUsername
                }
            } catch {
                print("⚠️ invite preview failed:", error)
            }
        }
    }

    func redeemPendingInviteIfNeeded(auth: AuthStore) async {
        guard !isRedeeming else { return }
        guard let code = PendingInviteStore.shared.currentCode() else { return }
        guard let token = auth.currentToken, !token.isEmpty else { return }
        guard auth.currentUser != nil else { return }
        guard !auth.needsOnboarding else { return }

        isRedeeming = true
        redemptionError = nil
        defer { isRedeeming = false }

        do {
            _ = try await InviteService.shared.redeemInvite(code: code, token: token)

            let inviterName = PendingInviteStore.shared.inviterUsername()
            redemptionMessage = inviterName.map { "You joined via \($0)’s invite." } ?? "Invite redeemed."
            lastInviterUsername = inviterName

            PendingInviteStore.shared.clear()
        } catch {
            redemptionError = error.localizedDescription
            print("⚠️ invite redeem failed:", error)
        }
    }

    func openChatWithInviterIfPossible(
        auth: AuthStore,
        contactsViewModel: ContactsViewModel
    ) async -> ChatRoomDTO? {
        guard let token = auth.currentToken, !token.isEmpty else { return nil }
        guard let inviterUserId = PendingInviteStore.shared.inviterUserId() else { return nil }

        do {
            let pseudoContact = ContactDTO(
                id: -1,
                alias: nil,
                favorite: false,
                externalPhone: nil,
                externalName: nil,
                createdAt: nil,
                userId: inviterUserId,
                user: ContactUserDTO(
                    id: inviterUserId,
                    username: PendingInviteStore.shared.inviterUsername(),
                    avatarUrl: nil
                )
            )

            let room = try await contactsViewModel.openDirectChat(for: pseudoContact, token: token)
            return room
        } catch {
            print("⚠️ open chat with inviter failed:", error)
            return nil
        }
    }
}
