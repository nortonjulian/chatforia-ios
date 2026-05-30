import XCTest
@testable import Chatforia

@MainActor
final class TwilioVideoServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()

        let service = TwilioVideoService.shared
        service.setMuted(false)
        service.setCameraEnabled(true)
    }

    func testInitialStateDefaults() {
        let service = TwilioVideoService.shared

        XCTAssertNil(service.room)
        XCTAssertNil(service.roomName)

        XCTAssertFalse(service.isMuted)
        XCTAssertTrue(service.isCameraEnabled)
        XCTAssertTrue(service.isFrontCamera)
    }

    func testSetMutedTrueUpdatesState() {
        let service = TwilioVideoService.shared

        service.setMuted(true)

        XCTAssertTrue(service.isMuted)
    }

    func testSetMutedFalseUpdatesState() {
        let service = TwilioVideoService.shared

        service.setMuted(true)
        service.setMuted(false)

        XCTAssertFalse(service.isMuted)
    }

    func testSetCameraEnabledFalseUpdatesState() {
        let service = TwilioVideoService.shared

        service.setCameraEnabled(false)

        XCTAssertFalse(service.isCameraEnabled)
    }

    func testSetCameraEnabledTrueUpdatesState() {
        let service = TwilioVideoService.shared

        service.setCameraEnabled(false)
        service.setCameraEnabled(true)

        XCTAssertTrue(service.isCameraEnabled)
    }

    func testCurrentLocalVideoTrackDefaultsToNil() {
        let service = TwilioVideoService.shared

        XCTAssertNil(service.currentLocalVideoTrack())
    }

    func testRemoteVideoTrackDefaultsToNil() {
        let service = TwilioVideoService.shared

        XCTAssertNil(
            service.remoteVideoTrack(
                for: "missing-participant"
            )
        )
    }

    func testDisconnectWithoutRoomDoesNotCrash() {
        let service = TwilioVideoService.shared

        service.disconnect()

        XCTAssertTrue(true)
    }

    func testFlipCameraWithoutCameraSourceDoesNotCrash() {
        let service = TwilioVideoService.shared

        service.flipCamera()

        XCTAssertTrue(true)
    }
}
