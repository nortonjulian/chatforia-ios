import Foundation
import Combine

@MainActor
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

    private let tokenStore = TokenStore.shared
    private(set) var socket = SocketManager.shared

    var isPlus: Bool { subscriptionPlan == .plus }
    var isPremium: Bool { subscriptionPlan == .premium }
    var isPaid: Bool { isPlus || isPremium }

    override init() {
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
    }

    func bootstrap() async {
        guard let token = tokenStore.read(), !token.isEmpty else {
            socket.disconnect()
            needsOnboarding = false
            needsKeyRestore = false
            keyRestoreMessage = nil
            subscriptionPlan = .free
            state = .loggedOut
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
            
            await SubscriptionManager.shared.refreshEntitlements()

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

            if needsKeyRestore {
                print("⚠️ KEY ISSUE — temporarily bypassing for TestFlight")
            }

            do {
                let shouldRestore = try await AccountKeyManager.shared.ensureLocalKeysExist(token: token)

                if shouldRestore {
                    needsKeyRestore = true
                    keyRestoreMessage = "This device is missing your encryption key. Restore it to read older encrypted messages."
                } else {
                    needsKeyRestore = false
                    keyRestoreMessage = nil
                }
            } catch {
                print("⚠️ key bootstrap failed:", error.localizedDescription)
            }

            socket.connect(token: token)

        } catch let apiError as APIError {
            switch apiError {
            case .unauthorized:
                handleInvalidSession()
            default:
                print("⚠️ bootstrap failed with non-auth error:", apiError.localizedDescription)
            }
        } catch {
            print("⚠️ bootstrap failed with unexpected error:", error.localizedDescription)
        }
    }

    func setTokenAndLoadUser(_ token: String) async {
        tokenStore.save(token)
        await bootstrap()
    }

    func logout() {
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
        let localKey = AccountKeyManager.shared.publicKeyBase64()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !serverKey.isEmpty && localKey.isEmpty {
            encryptionState = .missing
            needsKeyRestore = true
            keyRestoreMessage = "This device is missing your encryption key. Restore it to read encrypted messages."
            return
        }

        if !serverKey.isEmpty && !localKey.isEmpty && serverKey != localKey {
            encryptionState = .mismatch
            needsKeyRestore = true
            keyRestoreMessage = "This device has a different encryption key. Restore the correct key to access your messages."
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
