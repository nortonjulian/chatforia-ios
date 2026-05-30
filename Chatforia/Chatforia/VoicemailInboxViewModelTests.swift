import XCTest
@testable import Chatforia

@MainActor
final class VoicemailInboxViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = VoicemailInboxViewModel()

        XCTAssertTrue(vm.voicemails.isEmpty)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNil(vm.selectedVoicemail)
    }

    func testSelectSetsSelectedVoicemail() {
        let vm = VoicemailInboxViewModel()
        let voicemail = makeVoicemail(id: "vm-1")

        vm.select(voicemail)

        XCTAssertEqual(vm.selectedVoicemail?.id, "vm-1")
    }

    func testSocketVoicemailDeletedRemovesVoicemail() async {
        let vm = VoicemailInboxViewModel()
        let voicemail = makeVoicemail(id: "vm-1")

        vm.voicemails = [voicemail]
        vm.selectedVoicemail = voicemail

        NotificationCenter.default.post(
            name: .socketVoicemailDeleted,
            object: nil,
            userInfo: ["id": "vm-1"]
        )

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(vm.voicemails.isEmpty)
        XCTAssertNil(vm.selectedVoicemail)
    }

    func testSocketVoicemailUpdatedUpdatesExistingVoicemail() async {
        let vm = VoicemailInboxViewModel()
        let voicemail = makeVoicemail(
            id: "vm-1",
            transcript: "Old",
            isRead: false
        )

        vm.voicemails = [voicemail]
        vm.selectedVoicemail = voicemail

        NotificationCenter.default.post(
            name: .socketVoicemailUpdated,
            object: nil,
            userInfo: [
                "id": "vm-1",
                "transcript": "New transcript",
                "isRead": true,
                "transcriptStatus": "COMPLETED"
            ]
        )

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(vm.voicemails.first?.transcript, "New transcript")
        XCTAssertEqual(vm.voicemails.first?.isRead, true)
        XCTAssertEqual(vm.selectedVoicemail?.transcript, "New transcript")
        XCTAssertEqual(vm.selectedVoicemail?.isRead, true)
    }
}

// MARK: - Helpers

private func makeVoicemail(
    id: String,
    transcript: String? = nil,
    isRead: Bool = false
) -> VoicemailDTO {
    VoicemailDTO(
        id: id,
        userId: 1,
        phoneNumberId: 1,
        fromNumber: "+15551234567",
        toNumber: "+15559876543",
        audioUrl: "https://example.com/audio.mp3",
        durationSec: 12,
        transcript: transcript,
        transcriptStatus: .pending,
        isRead: isRead,
        deleted: false,
        createdAt: Date(),
        forwardedToEmailAt: nil
    )
}
