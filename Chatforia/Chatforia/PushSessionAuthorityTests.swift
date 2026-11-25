import XCTest
@testable import Chatforia

@MainActor
private final class InMemoryPushAuthorityStore: PushAuthorityStateStoring {
    var value = PushAuthorityState()
    func load() throws -> PushAuthorityState { value }
    func save(_ state: PushAuthorityState) throws { value = state }
}

@MainActor
private final class MockPushAuthorityTransport: PushAuthorityTransport {
    var activations: [PushActivationRequest] = []
    var registrations: [AuthorizedPushRegistration] = []
    var cleanups: [PushCleanupGrant] = []
    var activationHandler: ((PushActivationRequest) async throws -> PushActivationResponse)?
    var registrationHandler: ((AuthorizedPushRegistration) async throws -> Void)?
    var registrationError: Error?
    var cleanupError: Error?

    func activate(_ body: PushActivationRequest, token: String) async throws -> PushActivationResponse {
        activations.append(body)
        if let activationHandler { return try await activationHandler(body) }
        return PushActivationResponse(generation: String(activations.count),
                                      expiresAt: Date().addingTimeInterval(3_600),
                                      cleanupCapability: "cap-\(activations.count)")
    }

    func register(_ body: AuthorizedPushRegistration, token: String) async throws {
        registrations.append(body)
        if let registrationHandler { try await registrationHandler(body) }
        if let registrationError { throw registrationError }
    }

    func cleanup(_ grant: PushCleanupGrant) async throws {
        cleanups.append(grant)
        if let cleanupError { throw cleanupError }
    }
}

@MainActor
final class PushSessionAuthorityTests: XCTestCase {
    private func fullToken(_ id: Int) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["typ": "session", "id": id],
                                               options: [.sortedKeys])
        return "header.\(data.base64EncodedString()).signature"
    }

    private func fixture() -> (PushSessionAuthority, InMemoryPushAuthorityStore,
                               MockPushAuthorityTransport, (Int, String) -> Void) {
        let store = InMemoryPushAuthorityStore()
        let transport = MockPushAuthorityTransport()
        var activeAccount = 1
        var activeToken = fullToken(1)
        let authority = PushSessionAuthority(storage: store, transport: transport,
                                             isCurrent: { $0 == activeAccount && $1 == activeToken })
        return (authority, store, transport, { account, token in
            activeAccount = account
            activeToken = token
        })
    }

    func testShortTokenCannotActivatePushAuthority() async throws {
        let (authority, _, transport, _) = fixture()
        do {
            try await authority.register(provider: "apns", pushToken: "alert", accountId: 1,
                                         authToken: "short", deviceId: "device")
            XCTFail("Short token must be rejected")
        } catch PushAuthorityClientError.fullSessionRequired { }
        XCTAssertTrue(transport.activations.isEmpty)
    }

    func testAlertAndVoIPRegistrationReuseStableInstallationAndSeparateProviders() async throws {
        let (authority, store, transport, _) = fixture()
        let token = fullToken(1)
        try await authority.register(provider: "apns", pushToken: "alert", accountId: 1,
                                     authToken: token, deviceId: "device")
        try await authority.register(provider: "apns_voip", pushToken: "voip", accountId: 1,
                                     authToken: token, deviceId: "device")
        XCTAssertEqual(transport.activations.count, 1)
        XCTAssertEqual(transport.registrations.map(\.provider), ["apns", "apns_voip"])
        XCTAssertEqual(transport.registrations.map(\.installationId),
                       [store.value.identity!.installationId, store.value.identity!.installationId])
        XCTAssertEqual(transport.registrations.map(\.generation), ["1", "1"])
        XCTAssertEqual(Set(transport.registrations.map(\.environment)).count, 1)
        XCTAssertNotNil(store.value.current?.cleanupCapability)
    }

    func testTokenRotationAdvancesRevisionWithoutChangingInstallation() async throws {
        let (authority, store, transport, _) = fixture()
        let token = fullToken(1)
        for pushToken in ["first", "first", "second"] {
            try await authority.register(provider: "apns", pushToken: pushToken, accountId: 1,
                                         authToken: token, deviceId: "device")
        }
        XCTAssertEqual(transport.registrations.map(\.tokenRevision), [1, 1, 2])
        XCTAssertEqual(transport.activations.count, 1)
        XCTAssertEqual(store.value.revisions["apns"]?.revision, 2)
    }

    func testFailedCleanupRetainsCapabilityForRetry() async throws {
        let (authority, store, transport, _) = fixture()
        try await authority.register(provider: "apns", pushToken: "alert", accountId: 1,
                                     authToken: fullToken(1), deviceId: "device")
        let grant = try XCTUnwrap(authority.endCurrentSession())
        transport.cleanupError = URLError(.notConnectedToInternet)
        await authority.retryPendingCleanup()
        XCTAssertEqual(store.value.pending, [grant])
        transport.cleanupError = nil
        await authority.retryPendingCleanup()
        XCTAssertTrue(store.value.pending.isEmpty)
        XCTAssertEqual(transport.cleanups.count, 2)
    }

    func testLateActivationAfterAccountSwitchCannotRevokeNewAccountGrant() async throws {
        let (authority, store, transport, setAccount) = fixture()
        let oldToken = fullToken(1)
        let newToken = fullToken(2)
        var releaseOld: CheckedContinuation<PushActivationResponse, Never>?
        let oldActivationStarted = expectation(description: "old activation started")
        transport.activationHandler = { _ in
            if transport.activations.count == 1 {
                return await withCheckedContinuation {
                    releaseOld = $0
                    oldActivationStarted.fulfill()
                }
            }
            return PushActivationResponse(generation: "2", expiresAt: Date().addingTimeInterval(3_600),
                                          cleanupCapability: "new-cap")
        }
        let old = Task {
            try await authority.register(provider: "apns", pushToken: "old", accountId: 1,
                                         authToken: oldToken, deviceId: "device")
        }
        await fulfillment(of: [oldActivationStarted], timeout: 5)
        setAccount(2, newToken)
        try await authority.register(provider: "apns", pushToken: "new", accountId: 2,
                                     authToken: newToken, deviceId: "device")
        releaseOld?.resume(returning: PushActivationResponse(
            generation: "1", expiresAt: Date().addingTimeInterval(3_600), cleanupCapability: "old-cap"))
        do { try await old.value; XCTFail("Old account must be rejected") }
        catch PushAuthorityClientError.staleAccount { }
        XCTAssertEqual(store.value.current?.accountId, 2)
        XCTAssertEqual(store.value.current?.cleanupCapability, "new-cap")
        XCTAssertFalse(store.value.pending.contains { $0.accountId == 2 })
        // Cleanup may already have completed by the time the stale callback
        // returns. Either a retained retry or a completed cleanup is safe.
        XCTAssertTrue(store.value.pending.contains { $0.accountId == 1 } ||
                      transport.cleanups.contains { $0.accountId == 1 })
    }

    func testRevokedRegistrationClearsOnlyMatchingGrant() async throws {
        let (authority, store, transport, _) = fixture()
        transport.registrationError = APIError.server(status: 403, code: "PUSH_AUTHORITY_REVOKED",
                                                       message: nil)
        do {
            try await authority.register(provider: "apns", pushToken: "alert", accountId: 1,
                                         authToken: fullToken(1), deviceId: "device")
            XCTFail("Revoked authority must fail")
        } catch APIError.server { }
        XCTAssertNil(store.value.current)
        XCTAssertEqual(store.value.pending.count, 1)
    }

    func testAuthenticatedLogoutConfirmationDoesNotRemoveAnotherSessionGrant() async throws {
        let (authority, store, _, setAccount) = fixture()
        try await authority.register(provider: "apns", pushToken: "old", accountId: 1,
                                     authToken: fullToken(1), deviceId: "device")
        let oldGrant = try XCTUnwrap(authority.endCurrentSession())
        setAccount(2, fullToken(2))
        try await authority.register(provider: "apns", pushToken: "new", accountId: 2,
                                     authToken: fullToken(2), deviceId: "device")
        try authority.confirmAuthenticatedLogout(oldGrant)
        XCTAssertEqual(store.value.current?.accountId, 2)
        XCTAssertTrue(store.value.pending.isEmpty)
    }

    func testUnauthorizedRegistrationCannotLeaveEligibleLocalGrant() async throws {
        let (authority, store, transport, _) = fixture()
        transport.registrationError = APIError.unauthorized
        do {
            try await authority.register(provider: "apns_voip", pushToken: "voip", accountId: 1,
                                         authToken: fullToken(1), deviceId: "device")
            XCTFail("Unauthorized registration must fail")
        } catch APIError.unauthorized { }
        XCTAssertNil(store.value.current)
        XCTAssertEqual(store.value.pending.count, 1)
        XCTAssertEqual(transport.registrations.map(\.provider), ["apns_voip"])
    }

    func testDelayedOldRegistrationCannotClearNewAccountGrant() async throws {
        let (authority, store, transport, setAccount) = fixture()
        var releaseOld: CheckedContinuation<Void, Never>?
        let oldRegistrationStarted = expectation(description: "old registration started")
        transport.registrationHandler = { _ in
            await withCheckedContinuation {
                releaseOld = $0
                oldRegistrationStarted.fulfill()
            }
        }
        let old = Task {
            try await authority.register(provider: "apns", pushToken: "old", accountId: 1,
                                         authToken: fullToken(1), deviceId: "device")
        }
        await fulfillment(of: [oldRegistrationStarted], timeout: 5)
        _ = try authority.endCurrentSession()
        setAccount(2, fullToken(2))
        transport.registrationHandler = nil
        try await authority.register(provider: "apns", pushToken: "new", accountId: 2,
                                     authToken: fullToken(2), deviceId: "device")
        releaseOld?.resume()
        do { try await old.value; XCTFail("Old registration must be rejected") }
        catch PushAuthorityClientError.staleAccount { }
        XCTAssertEqual(store.value.current?.accountId, 2)
        XCTAssertEqual(transport.registrations.count, 2)
    }
}
