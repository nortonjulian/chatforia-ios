import XCTest
@testable import Chatforia

@MainActor
final class VoicemailInboxViewModelTests: XCTestCase {

    func testTabReturnUsesRecentInboxAndAccountSwitchClearsIt() async {
        var requests: [String] = []
        let vm = VoicemailInboxViewModel { token in
            requests.append(token)
            return [makeVoicemail(id: token)]
        }

        vm.prepareForAccount(1)
        let firstLoad = await vm.loadIfNeeded(token: "one")
        let cachedLoad = await vm.loadIfNeeded(token: "one")
        XCTAssertTrue(firstLoad)
        XCTAssertTrue(cachedLoad)
        XCTAssertEqual(requests, ["one"])
        XCTAssertEqual(vm.voicemails.first?.id, "one")

        vm.invalidateForNextOpen()
        let resumedLoad = await vm.loadIfNeeded(token: "one")
        XCTAssertTrue(resumedLoad)
        XCTAssertEqual(requests, ["one", "one"])

        vm.prepareForAccount(2)
        XCTAssertTrue(vm.voicemails.isEmpty)
        let secondAccountLoad = await vm.loadIfNeeded(token: "two")
        XCTAssertTrue(secondAccountLoad)
        XCTAssertEqual(requests, ["one", "one", "two"])
    }

    func testVoicemailFromOtherAccountIsIgnored() async throws {
        let vm = VoicemailInboxViewModel()
        vm.prepareForAccount(1)
        let foreign = makeVoicemail(id: "foreign", userId: 2)
        let encoded = try JSONEncoder().encode(foreign)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        NotificationCenter.default.post(
            name: .socketVoicemailNew, object: nil,
            userInfo: ["voicemail": payload]
        )
        let own = makeVoicemail(id: "own", userId: 1)
        let ownData = try JSONEncoder().encode(own)
        let ownPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: ownData) as? [String: Any])
        NotificationCenter.default.post(
            name: .socketVoicemailNew, object: nil,
            userInfo: ["voicemail": ownPayload]
        )
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(vm.voicemails.map(\.id), ["own"])
    }

    func testExplicitDeepLinkRefreshSupersedesPendingInboxLoad() async {
        let firstRequestStarted = expectation(description: "Initial inbox request started")
        var requestCount = 0
        let vm = VoicemailInboxViewModel { _ in
            requestCount += 1
            let request = requestCount
            if request == 1 {
                firstRequestStarted.fulfill()
                try await Task.sleep(nanoseconds: 300_000_000)
            }
            return [makeVoicemail(id: "response-\(request)")]
        }
        vm.prepareForAccount(1)
        let initial = Task { await vm.loadIfNeeded(token: "one") }
        await fulfillment(of: [firstRequestStarted], timeout: 2)
        let explicitResult = await vm.load(token: "one")
        _ = await initial.value

        XCTAssertTrue(explicitResult)
        XCTAssertEqual(vm.voicemails.first?.id, "response-2")
    }

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
    isRead: Bool = false,
    userId: Int = 1
) -> VoicemailDTO {
    VoicemailDTO(
        id: id,
        userId: userId,
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
        forwardedToEmailAt: nil,
        callerUserId: nil,
        displayName: nil,
        username: nil
    )
}
