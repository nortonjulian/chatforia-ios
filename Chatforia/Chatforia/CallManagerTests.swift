import XCTest
@testable import Chatforia

@MainActor
final class CallManagerTests: XCTestCase {

    func testInitialStateIsIdle() {
        let manager = CallManager()

        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.activeSession)
        XCTAssertNil(manager.lastError)
        XCTAssertTrue(manager.remoteVideoTracks.isEmpty)
        XCTAssertNil(manager.remoteParticipantIdentity)
        XCTAssertTrue(manager.isVideoCameraEnabled)
    }

    func testHandleIncomingAudioCallCreatesRingingSession() {
        let manager = CallManager()

        let payload = IncomingCallPayload(
            uuid: UUID(),
            displayName: "Julian",
            remoteIdentity: "julian",
            hasVideo: false,
            backendCallId: 123
        )

        manager.handleIncomingCallPayload(payload, auth: nil)

        XCTAssertNotNil(manager.activeSession)
        XCTAssertEqual(manager.activeSession?.direction, .incoming)
        XCTAssertEqual(manager.activeSession?.status, .ringing)
        XCTAssertEqual(manager.activeSession?.displayName, "Julian")
        XCTAssertEqual(manager.activeSession?.remoteIdentity, "julian")
        XCTAssertEqual(manager.activeSession?.backendCallId, 123)
        XCTAssertEqual(manager.activeSession?.isVideo, false)
        XCTAssertEqual(manager.activeSession?.isSpeakerOn, false)
    }

    func testHandleIncomingVideoCallCreatesRingingVideoSession() {
        let manager = CallManager()

        let payload = IncomingCallPayload(
            uuid: UUID(),
            displayName: "Video Caller",
            remoteIdentity: "42",
            hasVideo: true,
            backendCallId: 456
        )

        manager.handleIncomingCallPayload(payload, auth: nil)

        XCTAssertNotNil(manager.activeSession)
        XCTAssertEqual(manager.activeSession?.direction, .incoming)
        XCTAssertEqual(manager.activeSession?.status, .ringing)
        XCTAssertEqual(manager.activeSession?.displayName, "Video Caller")
        XCTAssertEqual(manager.activeSession?.remoteIdentity, "42")
        XCTAssertEqual(manager.activeSession?.backendCallId, 456)
        XCTAssertEqual(manager.activeSession?.isVideo, true)
        XCTAssertEqual(manager.activeSession?.isSpeakerOn, true)
        XCTAssertTrue(manager.remoteVideoTracks.isEmpty)
        XCTAssertNil(manager.remoteParticipantIdentity)
        XCTAssertTrue(manager.isVideoCameraEnabled)
    }

    func testUnansweredIncomingVideoExpiresAsMissed() {
        let manager = CallManager()
        let sessionId = UUID()

        let payload = IncomingCallPayload(
            uuid: sessionId,
            displayName: "Missed Video Caller",
            remoteIdentity: "call_test",
            hasVideo: true,
            backendCallId: nil
        )

        manager.handleIncomingCallPayload(
            payload,
            auth: nil
        )

        let expired =
            manager
                .expireIncomingVideoCallIfStillRinging(
                    sessionId: sessionId
                )

        XCTAssertTrue(expired)
        XCTAssertNil(manager.activeSession)
        XCTAssertEqual(manager.state, .ended)
    }

    func testAnsweredOrDifferentVideoSessionDoesNotExpire() {
        let manager = CallManager()
        let sessionId = UUID()

        let payload = IncomingCallPayload(
            uuid: sessionId,
            displayName: "Video Caller",
            remoteIdentity: "call_test",
            hasVideo: true,
            backendCallId: nil
        )

        manager.handleIncomingCallPayload(
            payload,
            auth: nil
        )

        let expired =
            manager
                .expireIncomingVideoCallIfStillRinging(
                    sessionId: UUID()
                )

        XCTAssertFalse(expired)
        XCTAssertEqual(
            manager.activeSession?.status,
            .ringing
        )
    }

    func testIncomingCallIgnoredWhenAlreadyRinging() {
        let manager = CallManager()

        let firstPayload = IncomingCallPayload(
            uuid: UUID(),
            displayName: "First Caller",
            remoteIdentity: "first",
            hasVideo: false,
            backendCallId: 1
        )

        let secondPayload = IncomingCallPayload(
            uuid: UUID(),
            displayName: "Second Caller",
            remoteIdentity: "second",
            hasVideo: false,
            backendCallId: 2
        )

        manager.handleIncomingCallPayload(firstPayload, auth: nil)
        manager.handleIncomingCallPayload(secondPayload, auth: nil)

        XCTAssertEqual(manager.activeSession?.displayName, "First Caller")
        XCTAssertEqual(manager.activeSession?.backendCallId, 1)
    }

    func testDismissEndedStateReturnsToIdle() {
        let manager = CallManager()

        let payload = IncomingCallPayload(
            uuid: UUID(),
            displayName: "Julian",
            remoteIdentity: "julian",
            hasVideo: false,
            backendCallId: nil
        )

        manager.handleIncomingCallPayload(payload, auth: nil)
        manager.twilioVoiceIncomingInviteCanceled()

        XCTAssertEqual(manager.state, .ended)

        manager.dismissEndedState()

        XCTAssertEqual(manager.state, .idle)
    }

    func testTwilioVoiceDidConnectActivatesSession() {
        let manager = CallManager()

        let payload = IncomingCallPayload(
            uuid: UUID(),
            displayName: "Julian",
            remoteIdentity: "julian",
            hasVideo: false,
            backendCallId: nil
        )

        manager.handleIncomingCallPayload(payload, auth: nil)
        manager.twilioVoiceDidConnect(callSid: "CA123")

        XCTAssertEqual(manager.activeSession?.status, .active)
        XCTAssertEqual(manager.activeSession?.callSid, "CA123")
        XCTAssertNotNil(manager.activeSession?.answeredAt)
    }

    func testTwilioVoiceDidFailSetsFailedState() {
        let manager = CallManager()

        let payload = IncomingCallPayload(
            uuid: UUID(),
            displayName: "Julian",
            remoteIdentity: "julian",
            hasVideo: false,
            backendCallId: nil
        )

        manager.handleIncomingCallPayload(payload, auth: nil)
        manager.twilioVoiceDidFail("Call failed")

        XCTAssertNil(manager.activeSession)
        XCTAssertEqual(manager.lastError, "Call failed")
    }

    func testRemoteVideoParticipantConnectAndDisconnect() {
        let manager = CallManager()

        manager.twilioVideoRemoteParticipantDidConnect(identity: "user-123")

        XCTAssertEqual(manager.remoteParticipantIdentity, "user-123")

        manager.twilioVideoRemoteParticipantDidDisconnect(identity: "user-123")

        XCTAssertNil(manager.remoteParticipantIdentity)
        XCTAssertNil(manager.remoteVideoTracks["user-123"])
    }
}

final class CallRecordDTOTests: XCTestCase {
    private func makeCall(
        callerId: Int = 65,
        calleeId: Int? = nil,
        direction: String = "INCOMING",
        externalPhone: String? = "+13018019227",
        caller: CallUserSummaryDTO? = CallUserSummaryDTO(
            id: 65, username: "regina", displayName: "Regina McFadden", avatarUrl: nil
        ),
        callee: CallUserSummaryDTO? = nil
    ) -> CallRecordDTO {
        CallRecordDTO(
            id: 922, roomId: nil, callerId: callerId, calleeId: calleeId,
            mode: "AUDIO", status: "ENDED", direction: direction,
            externalPhone: externalPhone, twilioCallSid: nil,
            durationSec: nil, endReason: nil, createdAt: Date(),
            startedAt: nil, endedAt: nil, caller: caller, callee: callee,
            hasVoicemail: nil, voicemailId: nil
        )
    }

    func testUnsavedIncomingPSTNCallDisplaysNumberInsteadOfAccountOwner() {
        let call = makeCall()
        XCTAssertEqual(
            call.otherPartyName(for: 65, contacts: []),
            "+13018019227"
        )
        XCTAssertNil(call.otherUser(for: 65))
    }

    func testUnsavedOutgoingPSTNCallDisplaysNumberInsteadOfAccountOwner() {
        let call = makeCall(direction: "OUTGOING")
        XCTAssertEqual(
            call.otherPartyName(for: 65, contacts: []),
            "+13018019227"
        )
        XCTAssertNil(call.otherUser(for: 65))
    }

    func testSavedIncomingPSTNCallDisplaysContactAlias() {
        let call = makeCall()
        let contact = ContactDTO(
            id: 12, alias: "Mom", favorite: false,
            externalPhone: "(301) 801-9227", externalName: "Mother",
            createdAt: nil, userId: nil, user: nil
        )
        XCTAssertEqual(
            call.otherPartyName(for: 65, contacts: [contact]),
            "Mom"
        )
    }

    func testSavedOutgoingPSTNCallDisplaysContactName() {
        let call = makeCall(direction: "OUTGOING")
        let contact = ContactDTO(
            id: 13, alias: nil, favorite: false,
            externalPhone: "+13018019227", externalName: "Jordan",
            createdAt: nil, userId: nil, user: nil
        )
        XCTAssertEqual(
            call.otherPartyName(for: 65, contacts: [contact]),
            "Jordan"
        )
    }

    func testAppToAppCallKeepsOtherUser() {
        let recipient = CallUserSummaryDTO(
            id: 77, username: "julian", displayName: "Julian", avatarUrl: nil
        )
        let call = makeCall(
            calleeId: 77, direction: "OUTGOING",
            externalPhone: nil, callee: recipient
        )
        XCTAssertEqual(
            call.otherPartyName(for: 65, contacts: []),
            "Julian"
        )
        XCTAssertEqual(call.otherUser(for: 65)?.id, 77)
    }
    func testMissingExternalNumberNeverOffersAccountOwnerAsOtherUser() {
        let call = makeCall(externalPhone: nil)
        XCTAssertNil(call.otherUser(for: 65))
        XCTAssertNil(call.otherPartyName(for: 65, contacts: []))
    }

    func testOneAccountLegacyCallUsesIncomingPhoneLabel() {
        var call = makeCall(externalPhone: nil)
        call.fromLabel = "+13018019227"
        call.toLabel = "+14155550101"
        XCTAssertEqual(call.externalNumber, "+13018019227")
        XCTAssertNil(call.otherUser(for: 65))
    }

    func testOneAccountLegacyCallUsesOutgoingPhoneLabel() {
        var call = makeCall(direction: "OUTGOING", externalPhone: nil)
        call.fromLabel = "+14155550101"
        call.toLabel = "+13018019227"
        XCTAssertEqual(call.externalNumber, "+13018019227")
        XCTAssertNil(call.otherUser(for: 65))
    }

    func testLegacyPhoneNumberIsDecodedFromHistoryResponse() throws {
        let payload = """
        {"id":922,"callerId":65,"mode":"AUDIO","status":"DECLINED",
         "direction":"INCOMING","phoneNumber":"+13018019227",
         "fromLabel":"+13018019227","toLabel":"+14155550101",
         "createdAt":"2026-09-27T22:05:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let call = try decoder.decode(CallRecordDTO.self, from: Data(payload.utf8))
        XCTAssertEqual(call.externalNumber, "+13018019227")
        XCTAssertEqual(call.fromLabel, "+13018019227")
        XCTAssertNil(call.otherUser(for: 65))
    }

    func testIncomingAppCallResolvesDistinctCaller() {
        let caller = CallUserSummaryDTO(
            id: 77, username: "julian", displayName: "Julian", avatarUrl: nil
        )
        let call = makeCall(
            callerId: 77, calleeId: 65, externalPhone: nil, caller: caller
        )
        XCTAssertEqual(call.otherUser(for: 65)?.id, 77)
        XCTAssertEqual(call.otherPartyName(for: 65, contacts: []), "Julian")
        XCTAssertNil(call.otherUser(for: nil))
        XCTAssertNil(call.otherUser(for: 999))
    }

    func testSelfCallNeverOffersVideoOrOwnerName() {
        let call = makeCall(calleeId: 65, externalPhone: nil)
        XCTAssertNil(call.otherUser(for: 65))
        XCTAssertNil(call.otherPartyName(for: 65, contacts: []))
    }

    func testLinkedExternalContactOffersTheDistinctUserAndFullName() {
        let call = makeCall(externalPhone: "+17609249652")
        var user = ContactUserDTO(id: 1, username: "julian", avatarUrl: nil)
        user.displayName = "Julian Norton"
        let contact = ContactDTO(
            id: 17, alias: nil, favorite: false,
            externalPhone: "+17609249652", externalName: nil,
            createdAt: nil, userId: 1, user: user
        )
        XCTAssertEqual(call.otherPartyName(for: 65, contacts: [contact]), "Julian Norton")
        XCTAssertEqual(call.otherUser(for: 65, contacts: [contact])?.id, 1)
        XCTAssertEqual(call.externalNumber, "+17609249652")
        XCTAssertNil(call.otherUser(for: 1, contacts: [contact]))
    }

    func testNamedPhoneOnlyContactDoesNotOfferAppActions() {
        let call = makeCall()
        let contact = ContactDTO(
            id: 18, alias: "Julian Norton", favorite: false,
            externalPhone: "+13018019227", externalName: nil,
            createdAt: nil, userId: nil, user: nil
        )
        XCTAssertEqual(call.otherPartyName(for: 65, contacts: [contact]), "Julian Norton")
        XCTAssertNil(call.otherUser(for: 65, contacts: [contact]))
    }

    func testLinkedContactWinsOverAnUnlinkedDuplicateNumber() {
        let call = makeCall()
        let unlinked = ContactDTO(
            id: 18, alias: nil, favorite: false, externalPhone: "+13018019227",
            externalName: nil, createdAt: nil, userId: nil, user: nil
        )
        var user = ContactUserDTO(id: 1, username: "julian", avatarUrl: nil)
        user.displayName = "Julian Norton"
        let linked = ContactDTO(
            id: 17, alias: nil, favorite: false, externalPhone: "(301) 801-9227",
            externalName: nil, createdAt: nil, userId: 1, user: user
        )
        XCTAssertEqual(call.otherPartyName(for: 65, contacts: [unlinked, linked]), "Julian Norton")
        XCTAssertEqual(call.otherUser(for: 65, contacts: [unlinked, linked])?.id, 1)
    }

}


@MainActor
final class VoicemailEmailSettingsTests: XCTestCase {
    private func user(canForward: Bool) throws -> UserDTO {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": 65, "username": "regina", "plan": canForward ? "PLUS" : "FREE",
            "voicemailEnabled": false,
            "voicemailForwardEmail": "saved@example.com",
            "voicemailEmailForwardingEnabled": true,
            "canForwardVoicemailEmail": canForward
        ])
        return try JSONDecoder().decode(UserDTO.self, from: data)
    }

    func testTurningEmailForwardingOffPreservesAddressAndOmitsVoicemailAvailability() throws {
        let vm = SettingsViewModel()
        vm.load(from: try user(canForward: true))
        vm.voicemailEmailForwardingEnabled = false
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(vm.makeRequest())) as? [String: Any])
        XCTAssertEqual(body["voicemailEmailForwardingEnabled"] as? Bool, false)
        XCTAssertEqual(body["voicemailForwardEmail"] as? String, "saved@example.com")
        XCTAssertNil(body["voicemailEnabled"])
    }

    func testFreeSettingsSaveOmitsPaidPreferencesButKeepsSavedAddress() throws {
        let vm = SettingsViewModel()
        vm.load(from: try user(canForward: false))
        vm.voicemailGreetingText = "Hello"
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(vm.makeRequest())) as? [String: Any])
        XCTAssertNil(body["voicemailEmailForwardingEnabled"])
        XCTAssertNil(body["voicemailForwardEmail"])
        XCTAssertNil(body["voicemailEnabled"])
        XCTAssertEqual(body["voicemailGreetingText"] as? String, "Hello")
        XCTAssertEqual(vm.voicemailForwardEmail, "saved@example.com")
    }
}

