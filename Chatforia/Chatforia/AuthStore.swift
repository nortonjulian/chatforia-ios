import Foundation
import Combine

@MainActor
final class AuthStore: ObservableObject {

    enum State {
        case loading
        case loggedOut
        case loggedIn(UserDTO)
    }

    @Published var state: State = .loading
    @Published var needsOnboarding: Bool = false
    @Published var needsKeyRestore: Bool = false
    @Published var keyRestoreMessage: String?
    @Published var isPremium: Bool = false

    private let tokenStore = TokenStore.shared
    private(set) var socket = SocketManager.shared

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
    }

    func bootstrap() async {
        guard let token = tokenStore.read(), !token.isEmpty else {
            socket.disconnect()
            needsOnboarding = false
            needsKeyRestore = false
            keyRestoreMessage = nil
            state = .loggedOut
            return
        }

        do {
            let response: MeResponse = try await APIClient.shared.send(
                APIRequest(path: "auth/me", method: .GET, requiresAuth: true),
                token: token
            )

            print("AUTH ME:", response.user.id, response.user.email ?? "nil")
            
            print("SERVER user.publicKey =", response.user.publicKey ?? "nil")
            print("ACCOUNT keychain publicKey =", AccountKeyManager.shared.publicKeyBase64() ?? "nil")
            print("AFTER bootstrap local key =", AccountKeyManager.shared.publicKeyBase64() ?? "nil")
            
            print("DEVICE key publicKey =", (try? DeviceKeyManager.shared.publicKeyBase64()) ?? "nil")

            state = .loggedIn(response.user)
            evaluateOnboarding(for: response.user)
            evaluateKeyRestoreNeed(for: response.user)
            isPremium = response.user.isPremium ?? false

            if needsKeyRestore {
                print("🚨 KEY MISMATCH OR MISSING — forcing restore flow")
                socket.disconnect()
                return
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
                print("⚠️ key bootstrap failed:", error)
            }

            socket.connect(token: token)
        } catch {
            handleInvalidSession()
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
        state = .loggedOut
    }

    func handleInvalidSession() {
        socket.disconnect()
        tokenStore.clear()
        needsOnboarding = false
        needsKeyRestore = false
        keyRestoreMessage = nil
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
            isPremium = response.user.isPremium ?? false

            if needsKeyRestore {
                print("🚨 KEY MISMATCH OR MISSING — forcing restore flow")
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

    // NEW
    func markKeyRestoreComplete() {
        needsKeyRestore = false
        keyRestoreMessage = nil
    }

    // NEW
    func forceKeyRestore(message: String? = nil) {
        needsKeyRestore = true
        keyRestoreMessage = message
    }

    private func evaluateOnboarding(for user: UserDTO) {
        let languageMissing = (user.preferredLanguage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let completedLocally = UserDefaults.standard.bool(forKey: onboardingKey(for: user.id))
        needsOnboarding = languageMissing || !completedLocally
    }

    private func evaluateKeyRestoreNeed(for user: UserDTO) {
        let serverKey = user.publicKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let localKey = AccountKeyManager.shared.publicKeyBase64()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // 🚨 Case 1: server has key but device has none
        if !serverKey.isEmpty && localKey.isEmpty {
            needsKeyRestore = true
            keyRestoreMessage = "This device is missing your encryption key. Restore it to read encrypted messages."
            return
        }

        // 🚨 Case 2: KEY MISMATCH (THIS IS YOUR BUG)
        if !serverKey.isEmpty && !localKey.isEmpty && serverKey != localKey {
            needsKeyRestore = true
            keyRestoreMessage = "This device has a different encryption key. Restore the correct key to access your messages."
            return
        }

        // ✅ All good
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
