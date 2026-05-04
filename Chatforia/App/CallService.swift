import Foundation

final class CallService {
    static let shared = CallService()
    private init() {}

    struct CreateCallResponse: Decodable {
        let callId: Int
    }
    
    struct StartVideoCallResponse: Decodable {
        let ok: Bool
        let callId: Int
        let roomName: String
    }

    func startVideoCall(calleeId: Int, chatRoomId: Int?, token: String) async throws -> StartVideoCallResponse {
        struct Body: Encodable {
            let calleeId: Int
            let chatRoomId: Int?
        }

        let body = try JSONEncoder().encode(
            Body(calleeId: calleeId, chatRoomId: chatRoomId)
        )

        return try await APIClient.shared.send(
            APIRequest(
                path: "video/start",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }

    func createCall(
        calleeId: Int,
        mode: String,
        token: String
    ) async throws -> Int {
        struct Body: Encodable {
            let calleeId: Int
            let mode: String
            let offer: Offer?
        }

        struct Offer: Encodable {
            let type: String
            let sdp: String
        }

        let body = try JSONEncoder().encode(
            Body(
                calleeId: calleeId,
                mode: mode,
                offer: mode == "AUDIO"
                    ? Offer(type: "offer", sdp: "placeholder")
                    : nil
            )
        )

        let response: CreateCallResponse = try await APIClient.shared.send(
            APIRequest(
                path: "calls/invite",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )

        return response.callId
    }
    
    func deleteCall(
        callId: Int,
        token: String
    ) async throws {
        let _: EmptyResponse = try await APIClient.shared.send(
            APIRequest(
                path: "calls/\(callId)",
                method: .DELETE,
                requiresAuth: true
            ),
            token: token
        )
    }

    func startExternalCall(
        phoneNumber: String,
        token: String
    ) async throws -> Int {
        struct Body: Encodable {
            let phoneNumber: String
            let mode: String
        }

        let body = try JSONEncoder().encode(
            Body(
                phoneNumber: phoneNumber,
                mode: "AUDIO"
            )
        )

        let response: CreateCallResponse = try await APIClient.shared.send(
            APIRequest(
                path: "calls/start-external",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )

        return response.callId
    }

    func answerCall(
        callId: Int,
        token: String
    ) async throws {
        struct Body: Encodable {
            let answer: Answer
        }

        struct Answer: Encodable {
            let type: String
            let sdp: String
        }

        let body = try JSONEncoder().encode(
            Body(answer: Answer(type: "answer", sdp: "accepted"))
        )

        let _: EmptyResponse = try await APIClient.shared.send(
            APIRequest(
                path: "calls/\(callId)/answer",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }

    func updateCall(
        callId: Int,
        token: String,
        durationSec: Int? = nil,
        reason: String? = nil
    ) async throws {
        struct Body: Encodable {
            let callId: Int
            let reason: String?
            let durationSec: Int?
        }

        let body = try JSONEncoder().encode(
            Body(
                callId: callId,
                reason: reason,
                durationSec: durationSec
            )
        )

        let _: EmptyResponse = try await APIClient.shared.send(
            APIRequest(
                path: "calls/end",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }
}
