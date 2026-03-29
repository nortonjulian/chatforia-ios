import Foundation

final class ESIMService {
    static let shared = ESIMService()

    private init() {}

    func purchaseAndProvision(pack: DataPackOption) async throws -> ESIMActivationDTO {
        throw URLError(.badURL)
    }
}
