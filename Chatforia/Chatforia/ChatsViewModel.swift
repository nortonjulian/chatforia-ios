import Foundation
import Combine

@MainActor
final class ChatsViewModel: ObservableObject {
    @Published var rooms: [ChatRoomDTO] = []
    @Published var isLoading: Bool = false
    @Published var errorText: String?
    @Published var searchText: String = ""

    static let chatroomsBasePath = "chatrooms"

    private func searchableRoomTitle(for room: ChatRoomDTO) -> String {
        let roomName = room.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !roomName.isEmpty {
            return roomName
        }

        let participantNames = (room.participants ?? [])
            .compactMap { $0.username?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !participantNames.isEmpty {
            return participantNames.joined(separator: ", ")
        }

        return "Chat #\(room.id)"
    }

    var filteredRooms: [ChatRoomDTO] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return rooms }

        return rooms.filter { room in
            let title = searchableRoomTitle(for: room).lowercased()
            let participantNames = (room.participants ?? [])
                .compactMap { $0.username?.lowercased() }
                .joined(separator: " ")
            let lastMessage = room.lastMessage?.content?.lowercased() ?? ""

            return title.contains(query)
                || participantNames.contains(query)
                || lastMessage.contains(query)
        }
    }

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
