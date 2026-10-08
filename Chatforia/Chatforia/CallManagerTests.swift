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
}
