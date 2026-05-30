import XCTest
@testable import Chatforia

@MainActor
final class VoIPPushManagerTests: XCTestCase {

    func testHexStringConvertsDataToLowercaseHex() {
        let data = Data([0x00, 0x0f, 0x10, 0xab, 0xff])

        let result = VoIPPushManager.shared.hexString(from: data)

        XCTAssertEqual(result, "000f10abff")
    }

    func testHexStringReturnsEmptyStringForEmptyData() {
        let data = Data()

        let result = VoIPPushManager.shared.hexString(from: data)

        XCTAssertEqual(result, "")
    }

    func testStartCanBeCalledMultipleTimesWithoutCrashing() {
        VoIPPushManager.shared.start()
        VoIPPushManager.shared.start()

        XCTAssertTrue(true)
    }
}
