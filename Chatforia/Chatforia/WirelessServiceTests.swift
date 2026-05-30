import XCTest
@testable import Chatforia

@MainActor
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
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected APIError.unauthorized, got \(error)")
        }
    }

    func testFetchWirelessStatusDoesNotThrowUnauthorizedWhenTokenExists() async {
        TokenStore.shared.save("fake-test-token")

        do {
            _ = try await WirelessService.shared.fetchWirelessStatus()
            XCTFail("Expected network/API failure, not success")
        } catch APIError.unauthorized {
            XCTFail("Should not fail authorization when token exists")
        } catch {
            // expected: token exists, so failure should be network/API/decode, not unauthorized
        }
    }
}
