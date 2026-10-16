import XCTest
@testable import Chatforia

@MainActor
final class WirelessServiceTests: XCTestCase {

    func testFetchWirelessStatusThrowsUnauthorizedWhenNoToken() async {
        let client = StubWirelessAPIClient()
        let service = WirelessService(
            apiClient: client,
            tokenProvider: { nil }
        )

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

            XCTAssertEqual(status.state, "ACTIVE")
            XCTAssertEqual(
                client.receivedToken,
                "fake-test-token"
            )
            XCTAssertEqual(
                client.receivedPath,
                "api/wireless/status"
            )
            XCTAssertEqual(
                client.receivedMethod,
                .GET
            )

            XCTAssertEqual(
                status.source?.id,
                42
            )
            XCTAssertEqual(
                status.source?.remainingDataMb,
                2973
            )

            XCTAssertEqual(
                status.queuedPacks?.count,
                1
            )
            XCTAssertEqual(
                status.queuedPacks?.first?.id,
                43
            )
            XCTAssertEqual(
                status.queuedPacks?.first?.remainingDataMb,
                3072
            )

            XCTAssertEqual(
                status.queuedDataMb,
                3072
            )
            XCTAssertEqual(
                status.totalAvailableDataMb,
                6045
            )
        } catch {
            XCTFail("Unexpected failure: \(error)")
        }
    }

    func testReplaceEsimSendsPurchaseAndIdempotencyKey() async {
        let client = StubWirelessAPIClient()
        let service = WirelessService(
            apiClient: client,
            tokenProvider: { "fake-test-token" }
        )

        do {
            let response = try await service.replaceEsim(
                purchaseId: 321,
                idempotencyKey: "  replacement-test-key  "
            )

            XCTAssertTrue(response.ok)
            XCTAssertEqual(
                response.replacement.purchaseId,
                321
            )
            XCTAssertEqual(
                response.replacement.status,
                "COMPLETED"
            )
            XCTAssertEqual(
                response.replacement.installation?.iccid,
                "NEW-ICCID"
            )

            XCTAssertEqual(
                client.receivedPath,
                "api/wireless/esim/321/replace"
            )
            XCTAssertEqual(
                client.receivedMethod,
                .POST
            )
            XCTAssertEqual(
                client.receivedToken,
                "fake-test-token"
            )
            XCTAssertEqual(
                client.receivedHeaders["Idempotency-Key"],
                "replacement-test-key"
            )
        } catch {
            XCTFail("Unexpected failure: \(error)")
        }
    }

    func testReplaceEsimRejectsMissingToken() async {
        let client = StubWirelessAPIClient()
        let service = WirelessService(
            apiClient: client,
            tokenProvider: { nil }
        )

        do {
            _ = try await service.replaceEsim(
                purchaseId: 321,
                idempotencyKey: "replacement-test-key"
            )
            XCTFail("Expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail(
                "Expected APIError.unauthorized, got \(error)"
            )
        }

        XCTAssertNil(client.receivedPath)
    }

    func testReplaceEsimRejectsEmptyIdempotencyKey() async {
        let client = StubWirelessAPIClient()
        let service = WirelessService(
            apiClient: client,
            tokenProvider: { "fake-test-token" }
        )

        do {
            _ = try await service.replaceEsim(
                purchaseId: 321,
                idempotencyKey: "   "
            )
            XCTFail("Expected APIError.invalidURL")
        } catch APIError.invalidURL {
            // expected
        } catch {
            XCTFail(
                "Expected APIError.invalidURL, got \(error)"
            )
        }

        XCTAssertNil(client.receivedPath)
    }
}

private final class StubWirelessAPIClient: APIClientSending {
    var receivedToken: String?
    var receivedPath: String?
    var receivedMethod: HTTPMethod?
    var receivedHeaders: [String: String] = [:]

    func send<T: Decodable>(
        _ request: APIRequest,
        token: String?
    ) async throws -> T {
        receivedToken = token
        receivedPath = request.path
        receivedMethod = request.method
        receivedHeaders = request.headers

        let data: Data

        if request.path.contains("/replace") {
            data = Data(
                #"""
                {
                  "ok": true,
                  "replacement": {
                    "id": "replacement-1",
                    "purchaseId": 321,
                    "status": "COMPLETED",
                    "oldIccid": "OLD-ICCID",
                    "newIccid": "NEW-ICCID",
                    "remainingDataMb": 4301,
                    "expiresAt": null,
                    "createdAt": null,
                    "completedAt": null,
                    "installation": {
                      "subscriberId": 99,
                      "iccid": "NEW-ICCID",
                      "providerProfileId": "NEW-PROFILE",
                      "smdp": "smdp.example.com",
                      "activationCode": "ABC123",
                      "lpaUri": "LPA:1$smdp.example.com$ABC123",
                      "qrPayload": "LPA:1$smdp.example.com$ABC123"
                    }
                  }
                }
                """#.utf8
            )
        } else {
            data = Data(
                #"""
                {
                  "mode": "INDIVIDUAL",
                  "state": "ACTIVE",
                  "low": false,
                  "exhausted": false,
                  "expired": false,
                  "source": {
                    "type": "ESIM_PACK",
                    "id": 42,
                    "addonKind": "chatforia_esim_local_3_premium",
                    "totalDataMb": 3072,
                    "remainingDataMb": 2973,
                    "expiresAt": "2026-11-13T03:33:20Z",
                    "daysRemaining": 30
                  },
                  "queuedPacks": [
                    {
                      "id": 43,
                      "addonKind": "chatforia_esim_local_3_premium",
                      "totalDataMb": 3072,
                      "remainingDataMb": 3072,
                      "expiresAt": "2026-11-13T19:27:49Z"
                    }
                  ],
                  "queuedDataMb": 3072,
                  "totalAvailableDataMb": 6045
                }
                """#.utf8
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(
            T.self,
            from: data
        )
    }
}
