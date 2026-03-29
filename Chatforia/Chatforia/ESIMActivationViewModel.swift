import Foundation
import Combine

@MainActor
final class ESIMActivationViewModel: ObservableObject {
    @Published var payload: ESIMActivationDTO

    init(payload: ESIMActivationDTO) {
        self.payload = payload
    }
}
