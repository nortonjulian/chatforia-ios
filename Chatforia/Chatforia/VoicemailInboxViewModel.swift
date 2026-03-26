import Foundation
import Combine

@MainActor
final class VoicemailInboxViewModel: ObservableObject {
    @Published var voicemails: [VoicemailDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedVoicemail: VoicemailDTO?

    func load(token: String) async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            voicemails = try await VoicemailService.shared.fetchVoicemails(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refresh(token: String) async {
        await load(token: token)
    }

    func select(_ voicemail: VoicemailDTO) {
        selectedVoicemail = voicemail
    }

    func markRead(
        _ voicemail: VoicemailDTO,
        isRead: Bool,
        token: String
    ) async {
        guard let index = voicemails.firstIndex(where: { $0.id == voicemail.id }) else { return }

        let original = voicemails[index]
        voicemails[index] = updated(voicemail: original, isRead: isRead)
        selectedVoicemail = voicemails[index]

        do {
            try await VoicemailService.shared.setVoicemailRead(
                id: voicemail.id,
                isRead: isRead,
                token: token
            )
            selectedVoicemail = voicemails[index]
        } catch {
            voicemails[index] = original
            if selectedVoicemail?.id == voicemail.id {
                selectedVoicemail = original
            }
            errorMessage = error.localizedDescription
        }
    }
    
    func markReadIfNeeded(_ voicemail: VoicemailDTO, token: String) async {
        guard !voicemail.isRead else { return }
        await markRead(voicemail, isRead: true, token: token)
    }

    func markSelectedReadIfNeeded(token: String) async {
        guard let selectedVoicemail, !selectedVoicemail.isRead else { return }
        await markRead(selectedVoicemail, isRead: true, token: token)
    }

    func delete(
        _ voicemail: VoicemailDTO,
        token: String
    ) async {
        guard let index = voicemails.firstIndex(where: { $0.id == voicemail.id }) else { return }

        let removed = voicemails.remove(at: index)
        let wasSelected = selectedVoicemail?.id == voicemail.id

        if wasSelected {
            selectedVoicemail = nil
        }

        do {
            try await VoicemailService.shared.deleteVoicemail(
                id: voicemail.id,
                token: token
            )
        } catch {
            voicemails.insert(removed, at: index)
            if wasSelected {
                selectedVoicemail = removed
            }
            errorMessage = error.localizedDescription
        }
    }

    private func updated(voicemail: VoicemailDTO, isRead: Bool) -> VoicemailDTO {
        VoicemailDTO(
            id: voicemail.id,
            userId: voicemail.userId,
            phoneNumberId: voicemail.phoneNumberId,
            fromNumber: voicemail.fromNumber,
            toNumber: voicemail.toNumber,
            audioUrl: voicemail.audioUrl,
            durationSec: voicemail.durationSec,
            transcript: voicemail.transcript,
            transcriptStatus: voicemail.transcriptStatus,
            isRead: isRead,
            deleted: voicemail.deleted,
            createdAt: voicemail.createdAt,
            forwardedToEmailAt: voicemail.forwardedToEmailAt
        )
    }
}
