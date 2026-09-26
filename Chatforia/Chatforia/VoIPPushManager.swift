import Foundation
import CryptoKit
import PushKit
import TwilioVoice

@MainActor
protocol VoIPPushManagerDelegate: AnyObject {
    func voipPushManagerDidUpdateToken(_ token: String, tokenData: Data)
    func voipPushManagerDidInvalidateToken()

    func voipPushManagerDidReceiveIncomingCall(
        _ payload: IncomingCallPayload,
        completion: @escaping () -> Void
    )
}

@MainActor
final class VoIPPushManager: NSObject {
    static let shared = VoIPPushManager()

    weak var delegate: VoIPPushManagerDelegate? {
        didSet {
            deliverCachedTokenIfPossible()
        }
    }

    private var registry: PKPushRegistry?
    private var cachedToken: String?
    private var cachedTokenData: Data?

    private func deliverCachedTokenIfPossible() {
        guard
            let delegate,
            let cachedToken,
            let cachedTokenData
        else {
            return
        }

        debugLog("📞 Delivering cached VoIP push credentials")

        delegate.voipPushManagerDidUpdateToken(
            cachedToken,
            tokenData: cachedTokenData
        )
    }

    private override init() {
        super.init()
    }

    func start() {
        if registry != nil {
            debugLog("📞 VoIPPushManager already started")
            return
        }

        debugLog("📞 Starting VoIPPushManager")

        let registry = PKPushRegistry(queue: DispatchQueue.main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.registry = registry
    }

    nonisolated func hexString(from data: Data) -> String {
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

        let token = hexString(from: pushCredentials.token)

        Task { @MainActor in
            debugLog("📞 VoIP push credentials received")

            let tokenHash = token.data(using: .utf8).map {
                SHA256.hash(data: $0)
                    .map { String(format: "%02x", $0) }
                    .joined()
            } ?? "hash-failed"

            debugLog(
                "📞 Current PushKit token SHA256:",
                tokenHash
            )

            self.cachedToken = token
            self.cachedTokenData = pushCredentials.token
            self.deliverCachedTokenIfPossible()
        }
    }

    nonisolated func pushRegistry(
        _ registry: PKPushRegistry,
        didInvalidatePushTokenFor type: PKPushType
    ) {
        guard type == .voIP else { return }

        Task { @MainActor in
            self.cachedToken = nil
            self.cachedTokenData = nil
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

        // PKPushRegistry was created on the main queue. Handle the call
        // synchronously so CallKit can be reported during this callback.
        MainActor.assumeIsolated {
            if let incomingPayload = self.makeChatforiaIncomingCallPayload(from: data) {
                guard let delegate = self.delegate else {
                    debugLog("⚠️ VoIP push received but no CallManager delegate is attached")
                    completion()
                    return
                }

                delegate.voipPushManagerDidReceiveIncomingCall(
                    incomingPayload,
                    completion: completion
                )
                return
            }

            let backendCallId = self.intValue(data["callId"])

            NSLog("📞 Incoming Twilio PushKit notification received")

            TwilioVoiceService.shared.handleIncomingPushNotification(
                data,
                backendCallId: backendCallId,
                completion: completion
            )
        }
    }

    private func makeChatforiaIncomingCallPayload(
        from data: [String: Any]
    ) -> IncomingCallPayload? {
        let type = stringValue(data["type"])?.lowercased()

        guard type == "call_incoming" else {
            return nil
        }

        let mode = stringValue(data["mode"])?.uppercased() ?? "AUDIO"
        let isVideo = mode == "VIDEO"

        let backendCallId = intValue(data["callId"])
        let callerId = intValue(data["callerId"])
        let callerName = stringValue(data["callerName"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let displayName =
            callerName?.isEmpty == false
            ? callerName!
            : "Chatforia user"

        let roomName = stringValue(data["roomName"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let remoteIdentity: String? = {
            if isVideo {
                if let roomName, !roomName.isEmpty {
                    return roomName
                }

                if let backendCallId {
                    return "call_\(backendCallId)"
                }

                return nil
            }

            if let callerId {
                return String(callerId)
            }

            return displayName
        }()

        return IncomingCallPayload(
            uuid: UUID(),
            displayName: displayName,
            remoteIdentity: remoteIdentity,
            hasVideo: isVideo,
            backendCallId: backendCallId
        )
    }

    private func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }

        if let value = value as? Int {
            return String(value)
        }

        if let value = value as? NSNumber {
            return value.stringValue
        }

        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }

        if let value = value as? String {
            return Int(value)
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return nil
    }
}