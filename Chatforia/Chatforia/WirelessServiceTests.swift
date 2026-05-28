import XCTest
@testable import Chatforia

final class WirelessServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TokenStore.shared.clear()
    }

    override func tearDown() {
        TokenStore.shared.clear()
        super.tearDown()
    }

    func testFetchWirelessStatusThrowsUnauthorizedWhenNoToken() async {

        do {
            _ = try await WirelessService.shared.fetchWirelessStatus()

            XCTFail("Expected APIError.unauthorized")

        } catch let error as APIError {

            guard case .unauthorized = error else {
                XCTFail("Expected APIError.unauthorized, got \(error)")
                return
            }

        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchWirelessStatusDoesNotThrowUnauthorizedWhenTokenExists() async {

        TokenStore.shared.save("fake-test-token")

        do {
            _ = try await WirelessService.shared.fetchWirelessStatus()

            XCTFail("Expected network/API failure, not unauthorized")

        } catch let error as APIError {

            if case .unauthorized = error {
                XCTFail("Should not fail authorization when token exists")
            }

        } catch {
            // acceptable — API/network/decode errors are fine here
            XCTAssertTrue(true)
        }
    }
}
