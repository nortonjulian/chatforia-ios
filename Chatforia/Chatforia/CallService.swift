import Foundation

final class CallService {
    static let shared = CallService()
    private init() {}

    struct CreateCallResponse: Decodable {
        let callId: Int
    }

    func createCall(
        calleeId: Int,
        mode: String,
        token: String
    ) async throws -> Int {
        struct Body: Encodable {
            let calleeId: Int
            let mode: String
            let offer: Offer
        }

        struct Offer: Encodable {
            let type: String
            let sdp: String
        }

        let body = try JSONEncoder().encode(
            Body(
                calleeId: calleeId,
                mode: mode,
                offer: Offer(type: "offer", sdp: "placeholder")
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
