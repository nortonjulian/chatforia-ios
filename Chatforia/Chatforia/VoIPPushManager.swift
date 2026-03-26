import Foundation
import PushKit
import TwilioVoice

@MainActor
protocol VoIPPushManagerDelegate: AnyObject {
    func voipPushManagerDidUpdateToken(_ token: String)
    func voipPushManagerDidInvalidateToken()
}

@MainActor
final class VoIPPushManager: NSObject {
    static let shared = VoIPPushManager()

    weak var delegate: VoIPPushManagerDelegate?

    private var registry: PKPushRegistry?

    private override init() {
        super.init()
    }

    func start() {
        if registry != nil { return }

        let registry = PKPushRegistry(queue: DispatchQueue.main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.registry = registry
    }

    private func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

extension VoIPPushManager: PKPushRegistryDelegate {
    nonisolated func pushRegistry(
        _ registry: PKPushRegistry,
        didUpdate pushCredentials: PKPushCredentials,
        for type: PKPushType
    ) {
        guard type == .voIP else { return }

        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()

        Task { @MainActor in
            self.delegate?.voipPushManagerDidUpdateToken(token)
        }
    }

    nonisolated func pushRegistry(
        _ registry: PKPushRegistry,
        didInvalidatePushTokenFor type: PKPushType
    ) {
        guard type == .voIP else { return }

        Task { @MainActor in
            self.delegate?.voipPushManagerDidInvalidateToken()
        }
    }

    nonisolated func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else {
            completion()
            return
        }

        let rawData = payload.dictionaryPayload

        let data = rawData.reduce(into: [String: Any]()) { result, pair in
            if let key = pair.key as? String {
                result[key] = pair.value
            }
        }

        let backendCallId: Int? = {
            if let id = data["callId"] as? Int { return id }
            if let str = data["callId"] as? String { return Int(str) }
            return nil
        }()

        Task { @MainActor in
            TwilioVoiceSDK.handleNotification(
                data,
                delegate: TwilioVoiceService.shared,
                delegateQueue: nil
            )

            TwilioVoiceService.shared.setPendingBackendCallId(backendCallId)

            completion()
        }
    }
}
