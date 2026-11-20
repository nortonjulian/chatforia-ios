import XCTest
import Security
@testable import Chatforia

@MainActor
final class AuthStoreTests: XCTestCase {

    private var tokenStore: MockTokenStore!
    private var apiClient: MockAPIClient!
    private var socket: MockSocketManager!
    private var offlineSessions: MockOfflineSessionStore!

    override func setUp() {
        super.setUp()
        DecryptedMessageTextStore.shared.deactivateAccount()
        tokenStore = MockTokenStore()
        apiClient = MockAPIClient()
        socket = MockSocketManager()
        offlineSessions = MockOfflineSessionStore()
    }

    override func tearDown() {
        DecryptedMessageTextStore.shared.deactivateAccount()
        tokenStore = nil
        apiClient = nil
        socket = nil
        offlineSessions = nil
        super.tearDown()
    }

    func testAuthenticatedAccountChangeClearsDecryptedTextAndRejectsLateWrite() {
        let auth = makeAuthStore()
        let cache = DecryptedMessageTextStore.shared
        auth.replaceCurrentUser(makeUser(id: 71))
        cache.setText("account 71 private text", for: 900, accountId: 71)
        XCTAssertEqual(cache.text(for: 900), "account 71 private text")

        auth.replaceCurrentUser(makeUser(id: 71))
        XCTAssertEqual(cache.text(for: 900), "account 71 private text")

        auth.replaceCurrentUser(makeUser(id: 72))
        cache.setText("late account 71 text", for: 900, accountId: 71)
        XCTAssertNil(cache.text(for: 900))
        cache.setText("account 72 text", for: 900, accountId: 72)
        XCTAssertEqual(cache.text(for: 900), "account 72 text")
    }

    func testLogoutAndInvalidSessionClearDecryptedText() {
        let auth = makeAuthStore()
        let cache = DecryptedMessageTextStore.shared
        auth.replaceCurrentUser(makeUser(id: 71))
        cache.setText("private text", for: 900, accountId: 71)
        auth.logout()
        XCTAssertNil(cache.text(for: 900))
        XCTAssertNil(cache.activeAccountId)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "chatforia.currentUserId"), 0)

        auth.replaceCurrentUser(makeUser(id: 71))
        cache.setText("private text", for: 900, accountId: 71)
        auth.handleInvalidSession()
        XCTAssertNil(cache.text(for: 900))
        XCTAssertNil(cache.activeAccountId)
    }

    func testAccountSwitchAndLogoutClearPersistedMessageWindow() {
        let auth = makeAuthStore()
        let message = MessageDTO(
            id: 950, rawContent: "synthetic cached text", createdAt: Date(),
            sender: SenderDTO(id: 9, username: "sender", publicKey: nil, avatarUrl: nil),
            chatRoomId: 10
        )
        auth.replaceCurrentUser(makeUser(id: 71))
        MessageStore.shared.upsertMessage(message)
        XCTAssertNotNil(MessageStore.shared.message(withId: 950))

        auth.replaceCurrentUser(makeUser(id: 72))
        XCTAssertNil(MessageStore.shared.message(withId: 950))

        MessageStore.shared.upsertMessage(message)
        XCTAssertNotNil(MessageStore.shared.message(withId: 950))
        auth.logout()
        XCTAssertNil(MessageStore.shared.message(withId: 950))
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

    func testOfflineColdStartUsesOnlyMatchingPreviouslyVerifiedSession() async {
        let user = makeUser()
        tokenStore.savedToken = "saved-token"
        offlineSessions.save(user: user, for: "saved-token")
        apiClient.error = APIError.network(URLError(.notConnectedToInternet))
        let auth = makeAuthStore()

        await auth.bootstrap()

        XCTAssertTrue(auth.isAppReady)
        XCTAssertTrue(auth.isOfflineSession)
        XCTAssertEqual(auth.currentUser?.id, user.id)
        XCTAssertNil(socket.connectedToken)
        XCTAssertEqual(tokenStore.savedToken, "saved-token")
        XCTAssertEqual(apiClient.sendCount, 1)
    }

    func testOfflineColdStartWithoutVerifiedSnapshotShowsRetryAndKeepsToken() async {
        tokenStore.savedToken = "saved-token"
        offlineSessions.save(user: makeUser(), for: "different-token")
        apiClient.error = APIError.network(URLError(.notConnectedToInternet))
        let auth = makeAuthStore()

        await auth.bootstrap()

        XCTAssertTrue(auth.isAppReady)
        XCTAssertTrue(auth.isUnavailable)
        XCTAssertNil(auth.currentUser)
        XCTAssertEqual(tokenStore.savedToken, "saved-token")
        XCTAssertNil(socket.connectedToken)
    }

    func testReconnectAfterFailedColdStartRecoversWithoutDuplicateLogin() async {
        tokenStore.savedToken = "saved-token"
        offlineSessions.save(user: makeUser(), for: "saved-token")
        apiClient.error = APIError.network(URLError(.notConnectedToInternet))
        let auth = makeAuthStore()
        await auth.bootstrap()

        apiClient.error = nil
        apiClient.result = MeResponse(user: makeUser())
        await auth.retryOfflineBootstrap()

        XCTAssertFalse(auth.isOfflineSession)
        XCTAssertFalse(auth.isUnavailable)
        XCTAssertEqual(auth.currentUser?.id, 1)
        XCTAssertEqual(socket.connectedToken, "saved-token")
        XCTAssertEqual(offlineSessions.user(for: "saved-token")?.id, 1)
        XCTAssertEqual(apiClient.sendCount, 3)
        XCTAssertEqual(auth.recoveryRevision, 1)
        await auth.retryOfflineBootstrap()
        XCTAssertEqual(apiClient.sendCount, 3)
        XCTAssertEqual(auth.recoveryRevision, 1)
    }

    func testFailedReconnectRetainsOfflineSessionForAnotherRetry() async {
        tokenStore.savedToken = "saved-token"
        offlineSessions.save(user: makeUser(), for: "saved-token")
        apiClient.error = APIError.network(URLError(.notConnectedToInternet))
        let auth = makeAuthStore()

        await auth.bootstrap()
        await auth.retryOfflineBootstrap()

        XCTAssertEqual(auth.currentUser?.id, 1)
        XCTAssertTrue(auth.isOfflineSession)
        XCTAssertEqual(auth.recoveryRevision, 0)
        XCTAssertEqual(tokenStore.savedToken, "saved-token")
        XCTAssertEqual(apiClient.sendCount, 2)
    }

    func testNetworkLossDuringKeyCheckUsesVerifiedSnapshotNotKeyReset() async {
        tokenStore.savedToken = "saved-token"
        offlineSessions.save(user: makeUser(), for: "saved-token")
        apiClient.result = MeResponse(user: makeUser())
        let auth = AuthStore(
            tokenStore: tokenStore,
            offlineSessionStore: offlineSessions,
            apiClient: apiClient,
            socket: socket,
            refreshEntitlements: {},
            ensureLocalKeys: { _, _ in
                throw APIError.network(URLError(.notConnectedToInternet))
            },
            finishLoginNotifications: {}
        )

        await auth.bootstrap()

        XCTAssertTrue(auth.isOfflineSession)
        XCTAssertFalse(auth.needsKeyRestore)
        XCTAssertEqual(auth.currentUser?.id, 1)
        XCTAssertNil(socket.connectedToken)
    }

    func testUnexpectedServerErrorDoesNotTreatSnapshotAsVerifiedOnline() async {
        tokenStore.savedToken = "saved-token"
        offlineSessions.save(user: makeUser(), for: "saved-token")
        apiClient.error = APIError.server(status: 400, message: "Bad request")
        let auth = makeAuthStore()

        await auth.bootstrap()

        XCTAssertTrue(auth.isUnavailable)
        XCTAssertNil(auth.currentUser)
        XCTAssertEqual(tokenStore.savedToken, "saved-token")
    }

    func testNormalOnlineLaunchStoresVerifiedSession() async {
        tokenStore.savedToken = "saved-token"
        apiClient.result = MeResponse(user: makeUser())
        let auth = makeAuthStore()

        await auth.bootstrap()

        XCTAssertFalse(auth.isOfflineSession)
        XCTAssertEqual(auth.recoveryRevision, 0)
        XCTAssertEqual(auth.currentUser?.id, 1)
        XCTAssertEqual(socket.connectedToken, "saved-token")
        XCTAssertEqual(offlineSessions.user(for: "saved-token")?.id, 1)
        XCTAssertEqual(apiClient.sendCount, 2)
        XCTAssertEqual(apiClient.requestTimeouts, [8, 8])
    }

    func testKeychainSnapshotRequiresExactTokenAndCanBeCleared() {
        let store = OfflineSessionStore()
        store.clear()
        defer { store.clear() }

        store.save(user: makeUser(id: 73), for: "verified-token")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.chatforia.ios",
            kSecAttrAccount as String: "chatforia.auth.offlineSession",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var rawItem: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &rawItem)
        XCTAssertEqual(status, errSecSuccess, "Simulator Keychain read status: \(status)")

        XCTAssertEqual(store.user(for: "verified-token")?.id, 73)
        XCTAssertNil(store.user(for: "other-token"))
        store.clear()
        XCTAssertNil(store.user(for: "verified-token"))
    }

    func testUnauthorizedOfflineSnapshotCannotBypassInvalidSession() async {
        tokenStore.savedToken = "saved-token"
        offlineSessions.save(user: makeUser(), for: "saved-token")
        apiClient.error = APIError.unauthorized
        let auth = makeAuthStore()

        await auth.bootstrap()

        XCTAssertNil(tokenStore.savedToken)
        XCTAssertNil(offlineSessions.user(for: "saved-token"))
        XCTAssertFalse(auth.isOfflineSession)
        guard case .loggedOut = auth.state else {
            return XCTFail("Expected loggedOut after 401")
        }
    }

    func testUnauthorizedOnPostEntitlementCheckClearsSession() async {
        tokenStore.savedToken = "saved-token"
        offlineSessions.save(user: makeUser(), for: "saved-token")
        apiClient.result = MeResponse(user: makeUser())
        apiClient.unauthorizedAtSend = 2
        let auth = makeAuthStore()

        await auth.bootstrap()

        XCTAssertNil(auth.currentUser)
        XCTAssertNil(tokenStore.savedToken)
        XCTAssertNil(offlineSessions.user(for: "saved-token"))
        XCTAssertNil(socket.connectedToken)
    }

    func testUnauthorizedDuringKeyCheckClearsSession() async {
        tokenStore.savedToken = "saved-token"
        offlineSessions.save(user: makeUser(), for: "saved-token")
        apiClient.result = MeResponse(user: makeUser())
        let auth = AuthStore(
            tokenStore: tokenStore,
            offlineSessionStore: offlineSessions,
            apiClient: apiClient,
            socket: socket,
            refreshEntitlements: {},
            ensureLocalKeys: { _, _ in throw APIError.unauthorized },
            finishLoginNotifications: {}
        )

        await auth.bootstrap()

        XCTAssertNil(auth.currentUser)
        XCTAssertNil(tokenStore.savedToken)
        XCTAssertNil(offlineSessions.user(for: "saved-token"))
    }

    func testConcurrentBootstrapDoesNotDuplicateRequests() async {
        tokenStore.savedToken = "saved-token"
        apiClient.result = MeResponse(user: makeUser())
        apiClient.delayNanoseconds = 20_000_000
        let auth = makeAuthStore()

        async let first: Void = auth.bootstrap()
        async let second: Void = auth.bootstrap()
        _ = await (first, second)

        XCTAssertEqual(apiClient.sendCount, 2)
    }

    func testLogoutDuringStartupCannotRestorePreviousAccount() async {
        tokenStore.savedToken = "saved-token"
        apiClient.result = MeResponse(user: makeUser())
        apiClient.delayNanoseconds = 30_000_000
        let auth = makeAuthStore()
        let startup = Task { await auth.bootstrap() }
        await Task.yield()
        auth.logout()
        await startup.value

        XCTAssertNil(auth.currentUser)
        XCTAssertNil(offlineSessions.user(for: "saved-token"))
        guard case .loggedOut = auth.state else {
            return XCTFail("Expected logout to win")
        }
    }

    func testNewAccountCanBootstrapWhileOldRequestIsInFlight() async {
        tokenStore.savedToken = "old-token"
        apiClient.result = MeResponse(user: makeUser(id: 2))
        apiClient.delayNanoseconds = 30_000_000
        let auth = makeAuthStore()
        let oldStartup = Task { await auth.bootstrap() }
        for _ in 0..<100 where apiClient.sendCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(apiClient.sendCount, 1)

        await auth.setTokenAndLoadUser("new-token")
        await oldStartup.value

        XCTAssertEqual(auth.currentToken, "new-token")
        XCTAssertEqual(auth.currentUser?.id, 2)
        XCTAssertEqual(socket.connectedToken, "new-token")
        XCTAssertEqual(offlineSessions.user(for: "new-token")?.id, 2)
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

        auth.forceKeyRestore(message: "Restore secure messages")

        XCTAssertTrue(auth.needsKeyRestore)
        XCTAssertEqual(auth.keyRestoreMessage, "Restore secure messages")
    }

    func testMarkKeyRestoreCompleteRequiresMatchingAccountKey() {
        let auth = makeAuthStore()

        auth.forceKeyRestore(message: "Restore needed")
        let didComplete = auth.markKeyRestoreComplete()

        XCTAssertFalse(didComplete)
        XCTAssertTrue(auth.needsKeyRestore)
        XCTAssertEqual(auth.encryptionState, .missing)
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

    func testPlusRemainsPaidButNotPremium() {
        let auth = makeAuthStore()
        auth.replaceCurrentUser(
            makeUser(plan: "PLUS", isPremium: false)
        )

        XCTAssertTrue(auth.isPlus)
        XCTAssertFalse(auth.isPremium)
        XCTAssertTrue(auth.isPaid)
        XCTAssertEqual(auth.subscriptionPlan, .plus)
    }

    func testBackendConfirmedPremiumIsPremium() {
        let auth = makeAuthStore()
        auth.replaceCurrentUser(
            makeUser(plan: "PREMIUM", isPremium: true)
        )

        XCTAssertFalse(auth.isPlus)
        XCTAssertTrue(auth.isPremium)
        XCTAssertTrue(auth.isPaid)
        XCTAssertEqual(auth.subscriptionPlan, .premium)
    }

    func testBackendDeniedPremiumFallsBackToFree() {
        let auth = makeAuthStore()
        auth.replaceCurrentUser(
            makeUser(plan: "PREMIUM", isPremium: false)
        )

        XCTAssertFalse(auth.isPlus)
        XCTAssertFalse(auth.isPremium)
        XCTAssertFalse(auth.isPaid)
        XCTAssertEqual(auth.subscriptionPlan, .free)
    }

    func testUserDTOPremiumWithoutAuthoritativeFlagFallsBackToPremium() {
        let user = makeUser(plan: "PREMIUM", isPremium: nil)

        XCTAssertEqual(user.normalizedPlan, "PREMIUM")
    }

    private func makeAuthStore() -> AuthStore {
        AuthStore(
            tokenStore: tokenStore,
            offlineSessionStore: offlineSessions,
            apiClient: apiClient,
            socket: socket,
            refreshEntitlements: {},
            ensureLocalKeys: { _, _ in false },
            finishLoginNotifications: {}
        )
    }

    private func makeUser(
        id: Int = 1,
        username: String = "julian",
        email: String? = "julian@example.com",
        preferredLanguage: String? = "en",
        plan: String? = "FREE",
        isPremium: Bool? = nil,
        publicKey: String? = nil,
        role: String? = "USER",
        theme: String? = "Dawn",
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
            "isPremium": isPremium ?? (plan == "PREMIUM"),
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
    var sendCount = 0
    var requestTimeouts: [TimeInterval?] = []
    var delayNanoseconds: UInt64 = 0
    var unauthorizedAtSend: Int?

    func send<T: Decodable>(_ request: APIRequest, token: String?) async throws -> T {
        sendCount += 1
        requestTimeouts.append(request.timeout)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let unauthorizedAtSend, sendCount == unauthorizedAtSend {
            throw APIError.unauthorized
        }
        if let error {
            throw error
        }

        guard let result = result as? T else {
            throw MockAPIError.missingResult
        }

        return result
    }
}

private final class MockOfflineSessionStore: OfflineSessionStoring {
    private var record: (token: String, user: UserDTO)?

    func save(user: UserDTO, for token: String) {
        record = (token, user)
    }

    func user(for token: String) -> UserDTO? {
        record?.token == token ? record?.user : nil
    }

    func clear() { record = nil }
}

private enum MockAPIError: Error {
    case missingResult
}
