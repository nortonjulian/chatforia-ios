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
