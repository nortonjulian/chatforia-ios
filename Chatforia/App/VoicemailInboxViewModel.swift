import Foundation
import Combine

@MainActor
final class VoicemailInboxViewModel: ObservableObject {
    @Published var voicemails: [VoicemailDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedVoicemail: VoicemailDTO?

    private var observers: [NSObjectProtocol] = []

    init() {
        bindSocketEvents()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

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

    private func bindSocketEvents() {
        let center = NotificationCenter.default

        observers.append(
            center.addObserver(
                forName: .socketVoicemailNew,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                let payload = notification.userInfo as? [String: Any]
                let voicemailPayload = payload?["voicemail"] as? [String: Any]

                Task { @MainActor [weak self] in
                    guard
                        let self,
                        let voicemailPayload,
                        let data = try? JSONSerialization.data(withJSONObject: voicemailPayload),
                        let voicemail = try? JSONDecoder().decode(VoicemailDTO.self, from: data)
                    else { return }

                    if let existingIndex = self.voicemails.firstIndex(where: { $0.id == voicemail.id }) {
                        self.voicemails[existingIndex] = voicemail
                    } else {
                        self.voicemails.insert(voicemail, at: 0)
                    }
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: .socketVoicemailUpdated,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard
                    let payload = notification.userInfo as? [String: Any],
                    let id = payload["id"] as? String
                else { return }

                Task { @MainActor [weak self] in
                    guard
                        let self,
                        let index = self.voicemails.firstIndex(where: { $0.id == id })
                    else { return }

                    let current = self.voicemails[index]

                    let transcript = payload["transcript"] as? String ?? current.transcript

                    let transcriptStatus: VoicemailTranscriptStatus = {
                        if let raw = payload["transcriptStatus"] as? String,
                           let status = VoicemailTranscriptStatus(rawValue: raw) {
                            return status
                        }
                        return current.transcriptStatus
                    }()

                    let isRead: Bool = {
                        if let isRead = payload["isRead"] as? Bool {
                            return isRead
                        }
                        return current.isRead
                    }()

                    let updatedVoicemail = VoicemailDTO(
                        id: current.id,
                        userId: current.userId,
                        phoneNumberId: current.phoneNumberId,
                        fromNumber: current.fromNumber,
                        toNumber: current.toNumber,
                        audioUrl: current.audioUrl,
                        durationSec: current.durationSec,
                        transcript: transcript,
                        transcriptStatus: transcriptStatus,
                        isRead: isRead,
                        deleted: current.deleted,
                        createdAt: current.createdAt,
                        forwardedToEmailAt: current.forwardedToEmailAt
                    )

                    self.voicemails[index] = updatedVoicemail

                    if self.selectedVoicemail?.id == id {
                        self.selectedVoicemail = updatedVoicemail
                    }
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: .socketVoicemailDeleted,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard
                    let payload = notification.userInfo as? [String: Any],
                    let id = payload["id"] as? String
                else { return }

                Task { @MainActor [weak self] in
                    guard let self else { return }

                    self.voicemails.removeAll { $0.id == id }

                    if self.selectedVoicemail?.id == id {
                        self.selectedVoicemail = nil
                    }
                }
            }
        )
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
