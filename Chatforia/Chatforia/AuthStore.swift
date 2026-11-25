import Foundation
import Combine

@MainActor

protocol TokenStoring {
    func read() -> String?
    func save(_ token: String)
    func clear()
}

protocol SocketManaging {
    func connect(token: String)
    func disconnect()
}

protocol APIClientSending {
    func send<T: Decodable>(_ request: APIRequest, token: String?) async throws -> T
}

protocol OfflineSessionStoring {
    func save(user: UserDTO, for token: String)
    func user(for token: String) -> UserDTO?
    func clear()
}

extension TokenStore: TokenStoring {}
extension SocketManager: SocketManaging {}
extension APIClient: APIClientSending {}

private struct DeviceLogoutRequest: Encodable {
    let deviceId: String
}

private struct DeviceLogoutResponse: Decodable {
    let ok: Bool?
    let cleared: Bool?
}

final class AuthStore: NSObject, ObservableObject {

    enum State {
        case loading
        case unavailable
        case loggedOut
        case loggedIn(UserDTO)
    }

    enum EncryptionState {
        case ready
        case missing
        case mismatch
    }

    enum SubscriptionPlan: String {
        case free = "FREE"
        case plus = "PLUS"
        case premium = "PREMIUM"
    }

    @Published var encryptionState: EncryptionState = .ready
    @Published var state: State = .loading {
        didSet {
            switch state {
            case .loggedIn(let user):
                let cachedAccountId = DecryptedMessageTextStore.shared.activeAccountId
                    ?? UserDefaults.standard.integer(forKey: "chatforia.currentUserId")
                if cachedAccountId > 0 && cachedAccountId != user.id {
                    MessageStore.shared.clearAll()
                    PrivateMessageImageCache.shared.clear()
                }
                SMSConversationSnapshotCache.shared.activateAccount(user.id)
                DecryptedMessageTextStore.shared.activateAccount(user.id)
            case .loggedOut, .unavailable:
                SMSConversationSnapshotCache.shared.clear()
                DecryptedMessageTextStore.shared.deactivateAccount()
                MessageStore.shared.clearAll()
                PrivateMessageImageCache.shared.clear()
            case .loading:
                break
            }
        }
    }
    @Published var needsOnboarding: Bool = false
    @Published var needsKeyRestore: Bool = false
    @Published var keyRestoreMessage: String?
    @Published var subscriptionPlan: SubscriptionPlan = .free
    @Published var isAppReady: Bool = false
    @Published private(set) var isOfflineSession = false
    @Published private(set) var recoveryRevision = 0

    private let tokenStore: TokenStoring
    private let offlineSessionStore: OfflineSessionStoring
    private let apiClient: APIClientSending
    private let refreshEntitlements: () async -> Void
    private let ensureLocalKeys: (Int, String) async throws -> Bool
    private let finishLoginNotifications: () async -> Void
    private(set) var socket: SocketManaging
    private var isRefreshingCurrentUser = false
    private struct BootstrapAttempt {
        let token: String?
        let version: Int
    }
    private var activeBootstrap: BootstrapAttempt?
    private var bootstrapVersion = 0
    private var lastUserRefreshAt: Date?
    private let userRefreshInterval: TimeInterval = 30
    
    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
    }

    var isPlus: Bool { subscriptionPlan == .plus }
    var isPremium: Bool { subscriptionPlan == .premium }
    var isPaid: Bool { isPlus || isPremium }

    init(
        tokenStore: TokenStoring? = nil,
        offlineSessionStore: OfflineSessionStoring? = nil,
        apiClient: APIClientSending? = nil,
        socket: SocketManaging? = nil,
        refreshEntitlements: @escaping () async -> Void = {
            await SubscriptionManager.shared.refreshEntitlements()
        },
        ensureLocalKeys: @escaping (Int, String) async throws -> Bool = { userId, token in
            try await AccountKeyManager.shared.ensureLocalKeysExist(userId: userId, token: token)
        },
        finishLoginNotifications: @escaping () async -> Void = {
            await NotificationCoordinator.shared.requestAuthorization()
            await NotificationCoordinator.shared.retryPushRegistrationIfPossible()
        }
    ) {
        self.tokenStore = tokenStore ?? TokenStore.shared
        self.offlineSessionStore = offlineSessionStore ?? OfflineSessionStore.shared
        self.apiClient = apiClient ?? APIClient.shared
        self.socket = socket ?? SocketManager.shared
        self.refreshEntitlements = refreshEntitlements
        self.ensureLocalKeys = ensureLocalKeys
        self.finishLoginNotifications = finishLoginNotifications

        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInvalidSessionNotification),
            name: Notification.Name("auth.session.invalid"),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func handleInvalidSessionNotification() {
        handleInvalidSession()
    }

    var currentToken: String? {
        tokenStore.read()
    }

    var currentUser: UserDTO? {
        if case .loggedIn(let user) = state {
            return user
        }
        return nil
    }

    func replaceCurrentUser(_ user: UserDTO) {
        state = .loggedIn(user)
        evaluateOnboarding(for: user)
        evaluateKeyRestoreNeed(for: user)
        syncPlan(from: user)
        isAppReady = true
        if !isOfflineSession, let token = currentToken {
            offlineSessionStore.save(user: user, for: token)
        }
    }

    func bootstrap() async {
        let wasRecovering = isOfflineSession || isUnavailable
        let startingToken = tokenStore.read()
        if let activeBootstrap, activeBootstrap.token == startingToken { return }
        bootstrapVersion += 1
        let version = bootstrapVersion
        activeBootstrap = BootstrapAttempt(token: startingToken, version: version)
        defer {
            if activeBootstrap?.version == version { activeBootstrap = nil }
        }

        if case .loading = state { isAppReady = false }

        guard let token = startingToken, !token.isEmpty else {
            Task { await PushSessionAuthority.shared.cleanupAfterMissingSession() }
            socket.disconnect()
            offlineSessionStore.clear()
            isOfflineSession = false
            needsOnboarding = false
            needsKeyRestore = false
            keyRestoreMessage = nil
            subscriptionPlan = .free
            state = .loggedOut
            isAppReady = true
            return
        }

        do {
            let response: MeResponse = try await apiClient.send(
                APIRequest(path: "auth/me", method: .GET, requiresAuth: true, timeout: 8),
                token: token
            )
            guard isCurrentBootstrap(token: token, version: version) else { return }

            state = .loggedIn(response.user)

            let user = response.user

            AnalyticsManager.shared.identify(user.id, properties: [
                "email": user.email ?? "",
                "plan": user.plan ?? "FREE"
            ])

            AnalyticsManager.shared.capture("session_started")

            evaluateOnboarding(for: user)
            evaluateKeyRestoreNeed(for: user)
            syncPlan(from: user)

            // 🔹 Sync StoreKit entitlements
            await refreshEntitlements()
            guard isCurrentBootstrap(token: token, version: version) else { return }

            // 🔹 Re-fetch after StoreKit sync
            do {
                let refreshed: MeResponse = try await apiClient.send(
                    APIRequest(path: "auth/me", method: .GET, requiresAuth: true, timeout: 8),
                    token: token
                )
                guard isCurrentBootstrap(token: token, version: version) else { return }

                state = .loggedIn(refreshed.user)
                evaluateOnboarding(for: refreshed.user)
                evaluateKeyRestoreNeed(for: refreshed.user)
                syncPlan(from: refreshed.user)

            } catch {
                guard isCurrentBootstrap(token: token, version: version) else {
                    return
                }
                if let apiError = error as? APIError,
                   case .unauthorized = apiError {
                    if isCurrentBootstrap(token: token, version: version) {
                        handleInvalidSession()
                    }
                    return
                }
                debugLog("⚠️ post-StoreKit auth refresh failed:", error.localizedDescription)
            }

            // 🔹 Ensure encryption keys exist BEFORE allowing chats/socket
            do {
                let shouldRestore = try await ensureLocalKeys(user.id, token)
                guard isCurrentBootstrap(token: token, version: version) else { return }

                if shouldRestore {
                    encryptionState = .missing
                    needsKeyRestore = true
                    keyRestoreMessage = appText(
                        "auth.missingEncryptionKeyOlderMessages",
                        languageCode: appLanguage
                    )

                    socket.disconnect()
                    isAppReady = true
                    return
                }

                encryptionState = .ready
                needsKeyRestore = false
                keyRestoreMessage = nil

            } catch {
                guard isCurrentBootstrap(token: token, version: version) else { return }
                if let apiError = error as? APIError,
                   case .unauthorized = apiError {
                    handleInvalidSession()
                    return
                }
                if isTransientConnectivityError(error) {
                    useOfflineSession(for: token, error: error)
                    return
                }
                debugLog("⚠️ key bootstrap failed:", error.localizedDescription)

                encryptionState = .mismatch
                needsKeyRestore = true
                keyRestoreMessage =
                    SecureMessagesErrorPresenter.message(
                        for: error
                    )

                socket.disconnect()
                isAppReady = true
                return
            }

            socket.connect(token: token)
            if let verifiedUser = currentUser {
                UserDefaults.standard.set(
                    verifiedUser.id,
                    forKey: "chatforia.currentUserId"
                )
                offlineSessionStore.save(user: verifiedUser, for: token)
            }
            isOfflineSession = false

            isAppReady = true
            if wasRecovering { recoveryRevision += 1 }

        } catch let apiError as APIError {
            switch apiError {
            case .unauthorized:
                if isCurrentBootstrap(token: token, version: version) {
                    handleInvalidSession()
                }
            default:
                if isCurrentBootstrap(token: token, version: version) {
                    useOfflineSession(for: token, error: apiError)
                }
            }

        } catch {
            if isCurrentBootstrap(token: token, version: version) {
                useOfflineSession(for: token, error: error)
            }
        }
    }

    private func isCurrentBootstrap(token: String, version: Int) -> Bool {
        tokenStore.read() == token && activeBootstrap?.version == version
    }

    func retryOfflineBootstrap() async {
        guard isOfflineSession || isUnavailable else { return }
        await bootstrap()
    }

    var isUnavailable: Bool {
        if case .unavailable = state { return true }
        return false
    }

    private func useOfflineSession(for token: String, error: Error) {
        debugLog("Authentication startup unavailable:", error)
        socket.disconnect()
        let mayUseSnapshot = isTransientConnectivityError(error)
        if mayUseSnapshot, let user = offlineSessionStore.user(for: token) {
            state = .loggedIn(user)
            UserDefaults.standard.set(user.id, forKey: "chatforia.currentUserId")
            evaluateOnboarding(for: user)
            evaluateKeyRestoreNeed(for: user)
            syncPlan(from: user)
            isOfflineSession = true
        } else {
            state = .unavailable
            isOfflineSession = false
        }
        isAppReady = true
    }

    private func isTransientConnectivityError(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            switch apiError {
            case .network:
                return true
            case .server(let status, _, _, _) where [502, 503, 504].contains(status):
                return true
            default:
                return false
            }
        }
        return error is URLError
    }

    func setTokenAndLoadUser(_ token: String) async {
        if tokenStore.read() != token {
            do { _ = try PushSessionAuthority.shared.endCurrentSession() }
            catch { debugLog("Push authority account handoff could not be saved:", error) }
            Task { await PushSessionAuthority.shared.retryPendingCleanup() }
        }
        activeBootstrap = nil
        socket.disconnect()
        DecryptedMessageTextStore.shared.deactivateAccount()
        MessageStore.shared.clearAll()
        PrivateMessageImageCache.shared.clear()
        SMSConversationSnapshotCache.shared.clear()
        UserDefaults.standard.removeObject(forKey: "chatforia.currentUserId")
        state = .loading
        isAppReady = false
        isOfflineSession = false
        tokenStore.save(token)
        await bootstrap()

        if let user = currentUser {
            UserDefaults.standard.set(
                user.id,
                forKey: "chatforia.currentUserId"
            )

            await finishLoginNotifications()
        }

        AnalyticsManager.shared.capture("login_succeeded", properties: [
            "method": "token"
        ])
    }

    func logout() {
        activeBootstrap = nil
        // Capture authenticated device information before local auth is cleared.
        let logoutToken = tokenStore.read()
        let logoutDeviceId =
            DeviceKeyManager.shared.getOrCreateDeviceId()
        let cleanupGrant: PushCleanupGrant?
        do { cleanupGrant = try PushSessionAuthority.shared.endCurrentSession() }
        catch {
            debugLog("Push authority logout cleanup could not be saved:", error)
            cleanupGrant = nil
        }

        isAppReady = true

        AnalyticsManager.shared.capture("logout")
        AnalyticsManager.shared.reset()

        socket.disconnect()
        tokenStore.clear()
        offlineSessionStore.clear()
        OfflineAssignedNumberStore.shared.clear()
        isOfflineSession = false
        UserDefaults.standard.removeObject(forKey: "chatforia.currentUserId")

        // Explicit logout is a privacy boundary. Do not repopulate the
        // previous account identifier on the next login screen.
        UserDefaults.standard.removeObject(
            forKey: "chatforia.lastIdentifier"
        )

        needsOnboarding = false
        needsKeyRestore = false
        keyRestoreMessage = nil
        encryptionState = .ready
        subscriptionPlan = .free
        state = .loggedOut

        // Local logout has completed. Confirm server cleanup only after an
        // authenticated full-session response; retain the capability otherwise.
        Task {
            if let logoutToken, PushSessionAuthority.isFullSession(logoutToken) {
                do {
                    let body = try JSONEncoder().encode(
                        DeviceLogoutRequest(deviceId: logoutDeviceId)
                    )
                    let _: DeviceLogoutResponse = try await apiClient.send(
                        APIRequest(path: "devices/logout", method: .POST,
                                   body: body, requiresAuth: true), token: logoutToken
                    )
                    try PushSessionAuthority.shared.confirmAuthenticatedLogout(cleanupGrant)
                    return
                } catch {
                    debugLog("Device notification cleanup remains pending:", error)
                }
            }
            await PushSessionAuthority.shared.retryPendingCleanup()
        }
    }

    func handleInvalidSession() {
        do { _ = try PushSessionAuthority.shared.endCurrentSession() }
        catch { debugLog("Push authority invalid-session cleanup could not be saved:", error) }
        Task { await PushSessionAuthority.shared.retryPendingCleanup() }
        activeBootstrap = nil
        isAppReady = true
        AnalyticsManager.shared.reset()
        
        socket.disconnect()
        tokenStore.clear()
        offlineSessionStore.clear()
        OfflineAssignedNumberStore.shared.clear()
        isOfflineSession = false
        UserDefaults.standard.removeObject(forKey: "chatforia.currentUserId")
        needsOnboarding = false
        needsKeyRestore = false
        keyRestoreMessage = nil
        subscriptionPlan = .free
        state = .loggedOut
    }

    func refreshCurrentUser(force: Bool = false) async {
        guard let token = tokenStore.read(), !token.isEmpty else {
            handleInvalidSession()
            return
        }

        if isRefreshingCurrentUser {
            return
        }

        if !force,
           let lastUserRefreshAt,
           Date().timeIntervalSince(lastUserRefreshAt) < userRefreshInterval,
           currentUser != nil {
            return
        }

        isRefreshingCurrentUser = true
        defer { isRefreshingCurrentUser = false }

        do {
            let response: MeResponse = try await APIClient.shared.send(
                APIRequest(path: "auth/me", method: .GET, requiresAuth: true),
                token: token
            )

            lastUserRefreshAt = Date()

            state = .loggedIn(response.user)

            AnalyticsManager.shared.capture("profile_refreshed")
            evaluateOnboarding(for: response.user)
            evaluateKeyRestoreNeed(for: response.user)
            syncPlan(from: response.user)

            if needsKeyRestore {
                socket.disconnect()
                return
            }

        } catch {
            debugLog("⚠️ refreshCurrentUser failed:", error)
        }
    }

    func markOnboardingComplete() {
        guard let user = currentUser else {
            needsOnboarding = false
            return
        }
        UserDefaults.standard.set(true, forKey: onboardingKey(for: user.id))
        needsOnboarding = false
    }

    @discardableResult
    func markKeyRestoreComplete() -> Bool {
        guard
            let user = currentUser,
            hasMatchingAccountKey(for: user)
        else {
            if let user = currentUser {
                evaluateKeyRestoreNeed(for: user)
            }

            if !needsKeyRestore {
                encryptionState = .missing
                needsKeyRestore = true
                keyRestoreMessage = appText(
                    "auth.missingEncryptionKey",
                    languageCode: appLanguage
                )
            }

            socket.disconnect()
            return false
        }

        encryptionState = .ready
        needsKeyRestore = false
        keyRestoreMessage = nil

        if let token = currentToken, !token.isEmpty {
            socket.connect(token: token)
        }

        return true
    }

    func forceKeyRestore(message: String? = nil) {
        encryptionState = .missing
        needsKeyRestore = true
        keyRestoreMessage = message
        socket.disconnect()
    }

    private func syncPlan(from user: UserDTO) {
        switch user.normalizedPlan {
        case "PREMIUM":
            subscriptionPlan = .premium
        case "PLUS":
            subscriptionPlan = .plus
        default:
            subscriptionPlan = .free
        }
    }

    private func evaluateOnboarding(for user: UserDTO) {
        let languageMissing = (user.preferredLanguage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasTemporaryUsername = user.username.lowercased().hasPrefix("user_") || user.username.lowercased().hasPrefix("pending_")

        needsOnboarding = languageMissing || hasTemporaryUsername
    }

    private func evaluateKeyRestoreNeed(for user: UserDTO) {
        let serverPublicKey =
            user.publicKey?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""

        let localPublicKey =
            AccountKeyManager.shared
                .publicKeyBase64(userId: user.id)?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""

        let localPrivateKey =
            AccountKeyManager.shared
                .privateKeyBase64(userId: user.id)?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""

        let hasLocalPublicKey =
            !localPublicKey.isEmpty

        let hasLocalPrivateKey =
            !localPrivateKey.isEmpty

        /*
         * A partial local pair is never usable, even when the public
         * portion happens to match the account key.
         */
        if hasLocalPublicKey != hasLocalPrivateKey {
            encryptionState = .missing
            needsKeyRestore = true
            keyRestoreMessage = appText(
                "auth.missingEncryptionKey",
                languageCode: appLanguage
            )
            return
        }

        if !serverPublicKey.isEmpty &&
           (!hasLocalPublicKey || !hasLocalPrivateKey) {
            encryptionState = .missing
            needsKeyRestore = true
            keyRestoreMessage = appText(
                "auth.missingEncryptionKey",
                languageCode: appLanguage
            )
            return
        }

        if !serverPublicKey.isEmpty &&
           serverPublicKey != localPublicKey {
            encryptionState = .mismatch
            needsKeyRestore = true
            keyRestoreMessage = appText(
                "auth.mismatchedEncryptionKey",
                languageCode: appLanguage
            )
            return
        }

        encryptionState = .ready
        needsKeyRestore = false
        keyRestoreMessage = nil
    }

    private func hasMatchingAccountKey(
        for user: UserDTO
    ) -> Bool {
        let serverPublicKey =
            user.publicKey?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""

        let localPublicKey =
            AccountKeyManager.shared
                .publicKeyBase64(userId: user.id)?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""

        let localPrivateKey =
            AccountKeyManager.shared
                .privateKeyBase64(userId: user.id)?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""

        return
            !serverPublicKey.isEmpty &&
            !localPublicKey.isEmpty &&
            !localPrivateKey.isEmpty &&
            serverPublicKey == localPublicKey
    }

    private func onboardingKey(for userId: Int) -> String {
        "chatforia.onboarding.complete.\(userId)"
    }
}

struct MeResponse: Decodable {
    let user: UserDTO
}
