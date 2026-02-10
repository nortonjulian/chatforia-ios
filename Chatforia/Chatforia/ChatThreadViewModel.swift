//
//  ChatThreadViewModel.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import Foundation
import Combine

struct MessagesResponse: Decodable {
    let messages: [MessageDTO]
}

struct SendMessageRequest: Encodable {
    let rawContent: String
}

struct SendMessageResponse: Decodable {
    let message: MessageDTO
}

@MainActor
final class ChatThreadViewModel: ObservableObject {
    @Published var messages: [MessageDTO] = []
    @Published var isLoading: Bool = false
    @Published var errorText: String?

    // MARK: - Load messages

    func loadMessages(roomId: Int, token: String?) async {
        guard let token else {
            errorText = "Missing auth token."
            return
        }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            // Primary expected shape: { "messages": [ ... ] }
            do {
                let resp: MessagesResponse = try await APIClient.shared.send(
                    APIRequest(
                        path: "chatrooms/\(roomId)/messages",
                        method: .GET,
                        requiresAuth: true
                    ),
                    token: token
                )
                self.messages = resp.messages
                return
            } catch {
                // Fallback: backend might return [ ... ] directly
                let arr: [MessageDTO] = try await APIClient.shared.send(
                    APIRequest(
                        path: "chatrooms/\(roomId)/messages",
                        method: .GET,
                        requiresAuth: true
                    ),
                    token: token
                )
                self.messages = arr
                return
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Send message

    func sendMessage(roomId: Int, token: String?, text: String) async {
        guard let token else {
            errorText = "Missing auth token."
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        errorText = nil

        do {
            let body = try JSONEncoder().encode(SendMessageRequest(rawContent: trimmed))

            let resp: SendMessageResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "chatrooms/\(roomId)/messages",
                    method: .POST,
                    body: body,
                    requiresAuth: true
                ),
                token: token
            )

            // Append and let the view scroll
            self.messages.append(resp.message)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
