import XCTest
@testable import Chatforia

@MainActor
final class WirelessServiceTests: XCTestCase {

    func testFetchWirelessStatusThrowsUnauthorizedWhenNoToken() async {
        let client = StubWirelessAPIClient()
        let service = WirelessService(apiClient: client, tokenProvider: { nil })
        do {
            _ = try await service.fetchWirelessStatus()
            XCTFail("Expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected APIError.unauthorized, got \(error)")
        }
        XCTAssertNil(client.receivedToken)
    }

    func testFetchWirelessStatusSendsStoredToken() async {
        let client = StubWirelessAPIClient()
        let service = WirelessService(
            apiClient: client,
            tokenProvider: { "fake-test-token" }
        )
        do {
            let status = try await service.fetchWirelessStatus()
            XCTAssertEqual(status.state, "active")
            XCTAssertEqual(client.receivedToken, "fake-test-token")
            XCTAssertEqual(client.receivedPath, "api/wireless/status")
        } catch {
            XCTFail("Unexpected failure: \(error)")
        }
    }
}

private final class StubWirelessAPIClient: APIClientSending {
    var receivedToken: String?
    var receivedPath: String?

    func send<T: Decodable>(_ request: APIRequest, token: String?) async throws -> T {
        receivedToken = token
        receivedPath = request.path
        return try JSONDecoder().decode(
            T.self,
            from: Data(#"{"mode":"esim","state":"active"}"#.utf8)
        )
    }
}
