import XCTest
@testable import Chatforia

@MainActor
final class AuthStoreTests: XCTestCase {

    private var tokenStore: MockTokenStore!
    private var apiClient: MockAPIClient!
    private var socket: MockSocketManager!

    override func setUp() {
        super.setUp()
        tokenStore = MockTokenStore()
        apiClient = MockAPIClient()
        socket = MockSocketManager()
    }

    override func tearDown() {
        tokenStore = nil
        apiClient = nil
        socket = nil
        super.tearDown()
    }

    func testBootstrapWithoutTokenLogsOutAndMarksAppReady() async {
        let auth = makeAuthStore()

        await auth.bootstrap()

        XCTAssertTrue(auth.isAppReady)
        XCTAssertFalse(auth.needsOnboarding)
        XCTAssertFalse(auth.needsKeyRestore)
        XCTAssertNil(auth.keyRestoreMessage)
        XCTAssertEqual(auth.subscriptionPlan, .free)
        XCTAssertTrue(socket.didDisconnect)

        guard case .loggedOut = auth.state else {
            return XCTFail("Expected loggedOut state")
        }
    }

    func testLogoutClearsTokenDisconnectsSocketAndResetsState() {
        tokenStore.savedToken = "test-token"
        let auth = makeAuthStore()

        auth.forceKeyRestore(message: "Restore needed")
        auth.logout()

        XCTAssertNil(tokenStore.savedToken)
        XCTAssertTrue(socket.didDisconnect)
        XCTAssertFalse(auth.needsOnboarding)
        XCTAssertFalse(auth.needsKeyRestore)
        XCTAssertNil(auth.keyRestoreMessage)
        XCTAssertEqual(auth.encryptionState, .ready)
        XCTAssertEqual(auth.subscriptionPlan, .free)

        guard case .loggedOut = auth.state else {
            return XCTFail("Expected loggedOut state")
        }
    }

    func testHandleInvalidSessionClearsTokenDisconnectsSocketAndLogsOut() {
        tokenStore.savedToken = "test-token"
        let auth = makeAuthStore()

        auth.handleInvalidSession()

        XCTAssertNil(tokenStore.savedToken)
        XCTAssertTrue(socket.didDisconnect)
        XCTAssertFalse(auth.needsOnboarding)
        XCTAssertFalse(auth.needsKeyRestore)
        XCTAssertEqual(auth.subscriptionPlan, .free)

        guard case .loggedOut = auth.state else {
            return XCTFail("Expected loggedOut state")
        }
    }

    func testSetTokenAndLoadUserSavesToken() async {
        apiClient.result = MeResponse(user: makeUser(plan: "FREE"))
        let auth = makeAuthStore()

        await auth.setTokenAndLoadUser("abc123")

        XCTAssertEqual(tokenStore.savedToken, "abc123")
    }

    func testRefreshCurrentUserWithoutTokenInvalidatesSession() async {
        let auth = makeAuthStore()

        await auth.refreshCurrentUser()

        XCTAssertTrue(socket.didDisconnect)

        guard case .loggedOut = auth.state else {
            return XCTFail("Expected loggedOut state")
        }
    }

    func testForceKeyRestoreSetsRestoreState() {
        let auth = makeAuthStore()

        auth.forceKeyRestore(message: "Restore your encryption key")

        XCTAssertTrue(auth.needsKeyRestore)
        XCTAssertEqual(auth.keyRestoreMessage, "Restore your encryption key")
    }

    func testMarkKeyRestoreCompleteClearsRestoreState() {
        let auth = makeAuthStore()

        auth.forceKeyRestore(message: "Restore needed")
        auth.markKeyRestoreComplete()

        XCTAssertFalse(auth.needsKeyRestore)
        XCTAssertNil(auth.keyRestoreMessage)
    }

    func testCurrentUserIsNilWhenLoggedOut() {
        let auth = makeAuthStore()

        auth.logout()

        XCTAssertNil(auth.currentUser)
    }

    func testSubscriptionHelpersDefaultToFree() {
        let auth = makeAuthStore()

        XCTAssertFalse(auth.isPlus)
        XCTAssertFalse(auth.isPremium)
        XCTAssertFalse(auth.isPaid)
        XCTAssertEqual(auth.subscriptionPlan, .free)
    }

    private func makeAuthStore() -> AuthStore {
        AuthStore(
            tokenStore: tokenStore,
            apiClient: apiClient,
            socket: socket
        )
    }

    private func makeUser(
        id: Int = 1,
        username: String = "julian",
        email: String? = "julian@example.com",
        preferredLanguage: String? = "en",
        plan: String? = "FREE",
        publicKey: String? = nil,
        role: String? = "USER",
        theme: String? = "dawn",
        avatarUrl: String? = nil,
        uiLanguage: String? = "en"
    ) -> UserDTO {
        let json: [String: Any?] = [
            "id": id,
            "email": email,
            "username": username,
            "publicKey": publicKey,
            "role": role,
            "plan": plan,
            "isPremium": plan == "PREMIUM",
            "preferredLanguage": preferredLanguage,
            "uiLanguage": uiLanguage,
            "theme": theme,
            "avatarUrl": avatarUrl
        ]

        let data = try! JSONSerialization.data(
            withJSONObject: json.compactMapValues { $0 },
            options: []
        )

        return try! JSONDecoder().decode(UserDTO.self, from: data)
    }
}

// MARK: - Mocks

private final class MockTokenStore: TokenStoring {
    var savedToken: String?

    func read() -> String? {
        savedToken
    }

    func save(_ token: String) {
        savedToken = token
    }

    func clear() {
        savedToken = nil
    }
}

private final class MockSocketManager: SocketManaging {
    var connectedToken: String?
    var didDisconnect = false

    func connect(token: String) {
        connectedToken = token
    }

    func disconnect() {
        didDisconnect = true
        connectedToken = nil
    }
}

private final class MockAPIClient: APIClientSending {
    var result: Any?
    var error: Error?

    func send<T: Decodable>(_ request: APIRequest, token: String?) async throws -> T {
        if let error {
            throw error
        }

        guard let result = result as? T else {
            throw MockAPIError.missingResult
        }

        return result
    }
}

private enum MockAPIError: Error {
    case missingResult
}
