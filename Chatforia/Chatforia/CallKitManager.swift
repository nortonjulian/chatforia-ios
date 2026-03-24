import Combine
import Foundation
import CallKit
import UIKit
import AVFoundation

@MainActor
protocol CallKitManagerDelegate: AnyObject {
    func callKitDidRequestStartCall(uuid: UUID, handle: String)
    func callKitDidRequestAnswerCall(uuid: UUID)
    func callKitDidRequestEndCall(uuid: UUID)
    func callKitDidSetMute(uuid: UUID, isMuted: Bool)
}

@MainActor
final class CallKitManager: NSObject, ObservableObject {
    weak var delegate: CallKitManagerDelegate?

    private let provider: CXProvider
    private let callController = CXCallController()

    override init() {
        let config = CXProviderConfiguration(localizedName: "Chatforia")
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.generic, .phoneNumber]
        config.includesCallsInRecents = true

        self.provider = CXProvider(configuration: config)
        super.init()
        self.provider.setDelegate(self, queue: nil)
    }

    func startOutgoingCall(uuid: UUID, handle: String, isPhoneNumber: Bool) {
        let cxHandle = CXHandle(type: isPhoneNumber ? .phoneNumber : .generic, value: handle)
        let action = CXStartCallAction(call: uuid, handle: cxHandle)
        let transaction = CXTransaction(action: action)

        callController.request(transaction) { error in
            if let error {
                print("❌ CallKit start call transaction failed:", error)
            }
        }
    }

    func reportOutgoingCallConnecting(uuid: UUID) {
        provider.reportOutgoingCall(with: uuid, startedConnectingAt: nil)
    }

    func reportOutgoingCallConnected(uuid: UUID) {
        provider.reportOutgoingCall(with: uuid, connectedAt: nil)
    }

    func endCall(uuid: UUID) {
        let action = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: action)

        callController.request(transaction) { error in
            if let error {
                print("❌ CallKit end call transaction failed:", error)
            }
        }
    }

    func setMuted(uuid: UUID, muted: Bool) {
        let action = CXSetMutedCallAction(call: uuid, muted: muted)
        let transaction = CXTransaction(action: action)

        callController.request(transaction) { error in
            if let error {
                print("❌ CallKit mute transaction failed:", error)
            }
        }
    }

    func reportCallEnded(uuid: UUID, reason: CXCallEndedReason = .remoteEnded) {
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
    }

    func reportIncomingCall(
        uuid: UUID,
        handle: String,
        hasVideo: Bool = false,
        completion: ((Error?) -> Void)? = nil
    ) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: handle)
        update.hasVideo = hasVideo
        update.localizedCallerName = handle

        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error {
                print("❌ CallKit incoming call report failed:", error)
            }
            completion?(error)
        }
    }
}

extension CallKitManager: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        print("⚠️ CallKit provider reset")
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        Task { @MainActor in
            delegate?.callKitDidRequestStartCall(
                uuid: action.callUUID,
                handle: action.handle.value
            )
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Task { @MainActor in
            delegate?.callKitDidRequestAnswerCall(uuid: action.callUUID)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor in
            delegate?.callKitDidRequestEndCall(uuid: action.callUUID)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Task { @MainActor in
            delegate?.callKitDidSetMute(uuid: action.callUUID, isMuted: action.isMuted)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        print("✅ CallKit audio session activated")
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        print("ℹ️ CallKit audio session deactivated")
    }
}
