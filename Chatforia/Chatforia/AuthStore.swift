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

    private let tokenStore = TokenStore()
    private(set) var socket = SocketManager.shared

    func bootstrap() async {
        guard let token = tokenStore.read() else {
            state = .loggedOut
            return
        }
        
        do {
            let response: MeResponse = try await APIClient.shared.send(
                APIRequest(path: "auth/me", method: .GET, requiresAuth: true),
                token: token
            )
            
            print("AUTH ME:", response.user.id, response.user.email ?? "nil")

            state = .loggedIn(response.user)
            socket.connect(token: token)
        } catch {
            socket.disconnect()
            tokenStore.clear()
            state = .loggedOut
        }
    }

    func setTokenAndLoadUser(_ token: String) async {
        tokenStore.save(token)
        await bootstrap()
    }

    func logout() {
        socket.disconnect()
        tokenStore.clear()
        state = .loggedOut
    }
}

struct MeResponse: Decodable {
    let user: UserDTO
}
