//
//  ChatsViewModel.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import Foundation
import Combine

@MainActor
final class ChatsViewModel: ObservableObject {
    @Published var rooms: [ChatRoomDTO] = []
    @Published var isLoading: Bool = false
    @Published var errorText: String?

    // Change this ONE string if your backend route differs
    private let listPath = "chatrooms"

    func loadRooms(token: String?) async {
        guard let token else {
            errorText = "Missing auth token."
            return
        }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            // Try decoding as an array first: [ChatRoomDTO]
            do {
                let arr: [ChatRoomDTO] = try await APIClient.shared.send(
                    APIRequest(path: listPath, method: .GET, requiresAuth: true),
                    token: token
                )
                self.rooms = arr
                return
            } catch {
                // If it wasn't an array, try wrapped response shapes
            }

            // Wrapped shape #1: { rooms: [...] }
            do {
                let wrapped: ChatRoomsResponse = try await APIClient.shared.send(
                    APIRequest(path: listPath, method: .GET, requiresAuth: true),
                    token: token
                )
                self.rooms = wrapped.rooms
                return
            } catch {
                // Wrapped shape #2: { chatRooms: [...] }
            }

            let wrapped2: ChatRoomsAltResponse = try await APIClient.shared.send(
                APIRequest(path: listPath, method: .GET, requiresAuth: true),
                token: token
            )
            self.rooms = wrapped2.chatRooms

        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct ChatRoomsResponse: Decodable {
    let rooms: [ChatRoomDTO]
}

private struct ChatRoomsAltResponse: Decodable {
    let chatRooms: [ChatRoomDTO]
}

