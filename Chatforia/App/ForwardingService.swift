import Foundation

final class ForwardingService {
    static let shared = ForwardingService()
    private init() {}

    func fetchSettings(token: String) async throws -> ForwardingSettingsDTO {
        let (data, _) = try await APIClient.shared.sendRaw(
            APIRequest(
                path: "settings/forwarding",
                method: .GET,
                requiresAuth: true
            ),
            token: token
        )

        // Empty / whitespace-only response -> use defaults
        if data.isEmpty || String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            return .empty
        }

        do {
            let decoder = JSONDecoder.tolerantISO8601Decoder()
            return try decoder.decode(ForwardingSettingsDTO.self, from: data)
        } catch {
            print("⚠️ forwarding fetch decode failed, falling back to defaults:", error)
            if let raw = String(data: data, encoding: .utf8) {
                print("⚠️ forwarding raw response:", raw)
            }
            return .empty
        }
    }

    func saveSettings(_ request: ForwardingSettingsDTO, token: String) async throws -> ForwardingSettingsDTO {
        let body = try JSONEncoder().encode(request)

        return try await APIClient.shared.send(
            APIRequest(
                path: "settings/forwarding",
                method: .PATCH,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }
}
