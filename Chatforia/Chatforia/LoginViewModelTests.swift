import XCTest
@testable import Chatforia

@MainActor
final class LoginViewModelTests: XCTestCase {

    private var apiClient: MockAPIClient!
    private var tokenStore: MockTokenStore!
    private var socket: MockSocketManager!
    private var auth: AuthStore!

    override func setUp() {
        super.setUp()

        apiClient = MockAPIClient()
        tokenStore = MockTokenStore()
        socket = MockSocketManager()

        auth = AuthStore(
            tokenStore: tokenStore,
            apiClient: apiClient,
            socket: socket
        )

        UserDefaults.standard.removeObject(forKey: "chatforiaHasLoggedIn")
        UserDefaults.standard.removeObject(forKey: "chatforia.lastIdentifier")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "chatforiaHasLoggedIn")
        UserDefaults.standard.removeObject(forKey: "chatforia.lastIdentifier")

        apiClient = nil
        tokenStore = nil
        socket = nil
        auth = nil

        super.tearDown()
    }

    func testOnAppearLoadsSavedIdentifierAndLoginFlag() {
        UserDefaults.standard.set(true, forKey: "chatforiaHasLoggedIn")
        UserDefaults.standard.set("julian@example.com", forKey: "chatforia.lastIdentifier")

        let vm = LoginViewModel(apiClient: apiClient)

        vm.onAppear()

        XCTAssertTrue(vm.hasLoggedInBefore)
        XCTAssertEqual(vm.identifier, "julian@example.com")
        XCTAssertNil(vm.errorText)
    }

    func testSuccessfulLoginSavesTokenAndLastIdentifier() async {
        apiClient.results = [
            LoginResponse(
                message: "ok",
                token: "login-token",
                user: makeUser()
            ),
            MeResponse(user: makeUser(plan: "FREE")),
            MeResponse(user: makeUser(plan: "FREE"))
        ]

        let vm = LoginViewModel(apiClient: apiClient)
        vm.identifier = "  julian@example.com  "
        vm.password = "password123"

        await vm.login(auth: auth, languageCode: "en")

        XCTAssertEqual(tokenStore.savedToken, "login-token")
        XCTAssertTrue(vm.hasLoggedInBefore)
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.showResendVerification)
        XCTAssertNil(vm.errorText)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "chatforia.lastIdentifier"), "julian@example.com")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "chatforiaHasLoggedIn"))
    }

    func testLoginWithUnverifiedEmailShowsResendVerification() async {
        apiClient.error = NSError(
            domain: "Test",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "email_not_verified"]
        )

        let vm = LoginViewModel(apiClient: apiClient)
        vm.identifier = "julian@example.com"
        vm.password = "password123"

        await vm.login(auth: auth, languageCode: "en")

        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.showResendVerification)
        XCTAssertEqual(vm.resendEmail, "julian@example.com")
        XCTAssertNotNil(vm.errorText)
    }

    func testFailedLoginShowsErrorMessage() async {
        apiClient.error = NSError(
            domain: "Test",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Invalid credentials"]
        )

        let vm = LoginViewModel(apiClient: apiClient)
        vm.identifier = "julian@example.com"
        vm.password = "wrong-password"

        await vm.login(auth: auth, languageCode: "en")

        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.showResendVerification)
        XCTAssertEqual(vm.errorText, "Invalid credentials")
    }

    func testResendVerificationEmailSuccessShowsSuccessMessage() async {
        apiClient.results = [
            ResendEmailResponse(ok: true)
        ]

        let vm = LoginViewModel(apiClient: apiClient)
        vm.resendEmail = "julian@example.com"

        await vm.resendVerificationEmail(languageCode: "en")

        XCTAssertFalse(vm.resendLoading)
        XCTAssertNotNil(vm.resendSuccess)
        XCTAssertNil(vm.errorText)
    }

    func testResendVerificationEmailFailureShowsError() async {
        apiClient.error = NSError(
            domain: "Test",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: "Server error"]
        )

        let vm = LoginViewModel(apiClient: apiClient)
        vm.resendEmail = "julian@example.com"

        await vm.resendVerificationEmail(languageCode: "en")

        XCTAssertFalse(vm.resendLoading)
        XCTAssertNil(vm.resendSuccess)
        XCTAssertNotNil(vm.errorText)
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
    var results: [Any] = []
    var error: Error?

    func send<T: Decodable>(_ request: APIRequest, token: String?) async throws -> T {
        if let error {
            throw error
        }

        guard !results.isEmpty else {
            throw MockAPIError.missingResult
        }

        let next = results.removeFirst()

        guard let typed = next as? T else {
            throw MockAPIError.wrongResultType
        }

        return typed
    }
}

private enum MockAPIError: Error {
    case missingResult
    case wrongResultType
}
