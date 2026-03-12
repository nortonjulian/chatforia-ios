import Foundation
import Combine

@MainActor
final class ChatsViewModel: ObservableObject {
    @Published var rooms: [ChatRoomDTO] = []
    @Published var isLoading: Bool = false
    @Published var errorText: String?

    static let chatroomsBasePath = "chatrooms"

    func loadRooms(token: String?) async {
        guard let token else {
            errorText = "Missing auth token."
            return
        }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let response: ChatRoomsResponse = try await APIClient.shared.send(
                APIRequest(path: Self.chatroomsBasePath, method: .GET, requiresAuth: true),
                token: token
            )
            self.rooms = response.rooms
        } catch {
            errorText = error.localizedDescription
            print("❌ loadRooms error:", error)
        }
    }
}

private struct ChatRoomsResponse: Decodable {
    let rooms: [ChatRoomDTO]
}
