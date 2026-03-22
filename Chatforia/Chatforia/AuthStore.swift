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
    }

    func bootstrap() async {
        guard let token = tokenStore.read(), !token.isEmpty else {
            socket.disconnect()
            needsOnboarding = false
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
            print("DEVICE key publicKey =", (try? DeviceKeyManager.shared.publicKeyBase64()) ?? "nil")

            state = .loggedIn(response.user)
            evaluateOnboarding(for: response.user)

            do {
                let device = try await DeviceRegistrationService.shared.ensureCurrentDeviceRegistered(
                    userId: response.user.id,
                    token: token
                )
                if let deviceId = device.deviceId {
                    print("✅ device registered: \(deviceId)")
                } else {
                    print("✅ device registered, but deviceId was nil")
                }
            } catch {
                print("⚠️ device registration failed:", error)
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
        state = .loggedOut
    }

    func handleInvalidSession() {
        socket.disconnect()
        tokenStore.clear()
        needsOnboarding = false
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

    private func evaluateOnboarding(for user: UserDTO) {
        let languageMissing = (user.preferredLanguage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let completedLocally = UserDefaults.standard.bool(forKey: onboardingKey(for: user.id))
        needsOnboarding = languageMissing || !completedLocally
    }

    private func onboardingKey(for userId: Int) -> String {
        "chatforia.onboarding.complete.\(userId)"
    }
}

struct MeResponse: Decodable {
    let user: UserDTO
}
