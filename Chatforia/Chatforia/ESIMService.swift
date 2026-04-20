import Foundation

final class ESIMService {
    static let shared = ESIMService()

    private init() {}

    func purchaseAndProvision(pack: DataPackOption) async throws -> ESIMActivationDTO {
        try await Task.sleep(nanoseconds: 500_000_000)

        return ESIMActivationDTO(
            smdpAddress: "smdp.chatforia.example",
            activationCode: "LPA:1$chatforia.example$ACT-\(Int.random(in: 100000...999999))",
            iccid: "890100000000000000\(Int.random(in: 10...99))",
            confirmationCode: "CONF-\(Int.random(in: 100000...999999))",
            planName: pack.title,
            status: "ready_to_install",
            qrCodeURL: "https://chatforia.com/esim/qr/\(pack.product)"
        )
    }

    func fetchCurrentActivation() async throws -> ESIMActivationDTO? {
        return nil
    }
}
