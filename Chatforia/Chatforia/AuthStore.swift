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

extension TokenStore: TokenStoring {}
extension SocketManager: SocketManaging {}
extension APIClient: APIClientSending {}

final class AuthStore: NSObject, ObservableObject {

    enum State {
        case loading
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
    @Published var state: State = .loading
    @Published var needsOnboarding: Bool = false
    @Published var needsKeyRestore: Bool = false
    @Published var keyRestoreMessage: String?
    @Published var subscriptionPlan: SubscriptionPlan = .free
    @Published var isAppReady: Bool = false

    private let tokenStore: TokenStoring
    private let apiClient: APIClientSending
    private(set) var socket: SocketManaging
    
    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
    }

    var isPlus: Bool { subscriptionPlan == .plus }
    var isPremium: Bool { subscriptionPlan == .premium }
    var isPaid: Bool { isPlus || isPremium }

    init(
        tokenStore: TokenStoring? = nil,
        apiClient: APIClientSending? = nil,
        socket: SocketManaging? = nil
    ) {
        self.tokenStore = tokenStore ?? TokenStore.shared
        self.apiClient = apiClient ?? APIClient.shared
        self.socket = socket ?? SocketManager.shared

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
    }

    func bootstrap() async {
        isAppReady = false

        guard let token = tokenStore.read(), !token.isEmpty else {
            socket.disconnect()
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
                APIRequest(path: "auth/me", method: .GET, requiresAuth: true),
                token: token
            )

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
            await SubscriptionManager.shared.refreshEntitlements()

            // 🔹 Re-fetch after StoreKit sync
            do {
                let refreshed: MeResponse = try await APIClient.shared.send(
                    APIRequest(path: "auth/me", method: .GET, requiresAuth: true),
                    token: token
                )

                state = .loggedIn(refreshed.user)
                evaluateOnboarding(for: refreshed.user)
                evaluateKeyRestoreNeed(for: refreshed.user)
                syncPlan(from: refreshed.user)

            } catch {
                print("⚠️ post-StoreKit auth refresh failed:", error.localizedDescription)
            }

            // 🔹 Ensure encryption keys exist BEFORE allowing chats/socket
            do {
                let shouldRestore = try await AccountKeyManager.shared.ensureLocalKeysExist(
                    userId: user.id,
                    token: token
                )

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
                print("⚠️ key bootstrap failed:", error.localizedDescription)

                encryptionState = .mismatch
                needsKeyRestore = true
                keyRestoreMessage = error.localizedDescription

                socket.disconnect()
                isAppReady = true
                return
            }

            socket.connect(token: token)

            isAppReady = true

        } catch let apiError as APIError {
            switch apiError {
            case .unauthorized:
                handleInvalidSession()
            default:
                print("⚠️ bootstrap failed with non-auth error:", apiError.localizedDescription)
                isAppReady = true
            }

        } catch {
            print("⚠️ bootstrap failed with unexpected error:", error.localizedDescription)
            isAppReady = true
        }
    }

    func setTokenAndLoadUser(_ token: String) async {
        tokenStore.save(token)
        await bootstrap()

        AnalyticsManager.shared.capture("login_succeeded", properties: [
            "method": "token"
        ])
    }

    func logout() {
        isAppReady = true
        AnalyticsManager.shared.reset()
        
        socket.disconnect()
        tokenStore.clear()
        needsOnboarding = false
        needsKeyRestore = false
        keyRestoreMessage = nil
        encryptionState = .ready
        subscriptionPlan = .free
        state = .loggedOut
    }

    func handleInvalidSession() {
        isAppReady = true
        AnalyticsManager.shared.reset()
        
        socket.disconnect()
        tokenStore.clear()
        needsOnboarding = false
        needsKeyRestore = false
        keyRestoreMessage = nil
        subscriptionPlan = .free
        state = .loggedOut
    }

    func refreshCurrentUser() async {
        guard let token = tokenStore.read(), !token.isEmpty else {
            handleInvalidSession()
            return
        }

        do {
            let response: MeResponse = try await APIClient.shared.send(
                APIRequest(path: "auth/me", method: .GET, requiresAuth: true),
                token: token
            )
            state = .loggedIn(response.user)
            evaluateOnboarding(for: response.user)
            evaluateKeyRestoreNeed(for: response.user)
            syncPlan(from: response.user)

            if needsKeyRestore {
                socket.disconnect()
                return
            }
        } catch {
            print("⚠️ refreshCurrentUser failed:", error)
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

    func markKeyRestoreComplete() {
        needsKeyRestore = false
        keyRestoreMessage = nil
    }

    func forceKeyRestore(message: String? = nil) {
        needsKeyRestore = true
        keyRestoreMessage = message
    }

    private func syncPlan(from user: UserDTO) {
        let normalized = (user.plan ?? "FREE").uppercased()

        switch normalized {
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
        let serverKey = user.publicKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let localKey =
            AccountKeyManager.shared.publicKeyBase64(userId: user.id)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !serverKey.isEmpty && localKey.isEmpty {
            encryptionState = .missing
            needsKeyRestore = true
            keyRestoreMessage = appText(
                "auth.missingEncryptionKey",
                languageCode: appLanguage
            )
            return
        }

        if !serverKey.isEmpty && !localKey.isEmpty && serverKey != localKey {
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

    private func onboardingKey(for userId: Int) -> String {
        "chatforia.onboarding.complete.\(userId)"
    }
}

struct MeResponse: Decodable {
    let user: UserDTO
}
