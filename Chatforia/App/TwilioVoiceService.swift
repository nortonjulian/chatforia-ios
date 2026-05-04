import Foundation
import AVFoundation
import TwilioVoice

@MainActor
protocol TwilioVoiceServiceDelegate: AnyObject {
    func twilioVoiceDidStartConnecting()
    func twilioVoiceDidConnect(callSid: String?)
    func twilioVoiceDidDisconnect()
    func twilioVoiceDidFail(_ message: String)
    func twilioVoiceDidReceiveIncoming(from: String, backendCallId: Int?)
    func twilioVoiceIncomingInviteCanceled()
}

@MainActor
final class TwilioVoiceService: NSObject {
    static let shared = TwilioVoiceService()

    weak var delegate: TwilioVoiceServiceDelegate?

    private var activeCall: Call?
    private var callInvite: CallInvite?
    private var cancelledCallInvite: CancelledCallInvite?
    private var accessToken: String?
    private var pendingBackendCallId: Int?

    private(set) var isReady = false
    private(set) var isMuted = false

    override private init() {
        super.init()
    }

    func fetchToken(authToken: String?) async throws -> VoiceTokenResponseDTO {
        try await APIClient.shared.send(
            APIRequest(path: "voice/token", method: .GET, requiresAuth: true),
            token: authToken
        )
    }

    func prepare(authToken: String?) async throws {
        let response = try await fetchToken(authToken: authToken)
        self.accessToken = response.token
        self.isReady = true
    }

    func setPendingBackendCallId(_ id: Int?) {
        pendingBackendCallId = id
    }

    func startCall(to: String, accessToken: String) async throws {
        self.accessToken = accessToken
        try configureAudioSession()

        let params = ConnectOptions(accessToken: accessToken) { builder in
            builder.params = ["To": to]
        }

        delegate?.twilioVoiceDidStartConnecting()
        activeCall = TwilioVoiceSDK.connect(options: params, delegate: self)
    }

    func acceptIncomingCall() {
        guard let callInvite else {
            delegate?.twilioVoiceDidFail("No incoming call to answer.")
            return
        }

        do {
            try configureAudioSession()

            let acceptOptions = AcceptOptions(callInvite: callInvite) { _ in
            }

            activeCall = callInvite.accept(options: acceptOptions, delegate: self)
            self.callInvite = nil
        } catch {
            delegate?.twilioVoiceDidFail(error.localizedDescription)
        }
    }

    func rejectIncomingCall() {
        guard let callInvite else { return }
        callInvite.reject()
        self.callInvite = nil
        self.cancelledCallInvite = nil
        self.pendingBackendCallId = nil
    }

    func hangup() {
        activeCall?.disconnect()
        activeCall = nil
        callInvite = nil
        cancelledCallInvite = nil
        pendingBackendCallId = nil
        isMuted = false
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        activeCall?.isMuted = muted
    }

    func setSpeaker(_ enabled: Bool) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.overrideOutputAudioPort(enabled ? .speaker : .none)
        } catch {
            delegate?.twilioVoiceDidFail("Could not change audio output.")
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true)
    }
}

extension TwilioVoiceService: CallDelegate {
    nonisolated func callDidStartRinging(call: Call) {}

    nonisolated func callDidConnect(call: Call) {
        Task { @MainActor in
            self.activeCall = call
            self.delegate?.twilioVoiceDidConnect(callSid: call.sid)
        }
    }

    nonisolated func callDidDisconnect(call: Call, error: Error?) {
        Task { @MainActor in
            self.activeCall = nil
            self.isMuted = false
            if let error {
                self.delegate?.twilioVoiceDidFail(error.localizedDescription)
            } else {
                self.delegate?.twilioVoiceDidDisconnect()
            }
        }
    }

    nonisolated func callDidFailToConnect(call: Call, error: Error) {
        Task { @MainActor in
            self.activeCall = nil
            self.isMuted = false
            self.delegate?.twilioVoiceDidFail(error.localizedDescription)
        }
    }
}

extension TwilioVoiceService: NotificationDelegate {
    nonisolated func callInviteReceived(callInvite: CallInvite) {
        Task { @MainActor in
            self.callInvite = callInvite

            let from = callInvite.from ?? "Incoming Call"
            let backendCallId = self.pendingBackendCallId
            self.pendingBackendCallId = nil

            self.delegate?.twilioVoiceDidReceiveIncoming(
                from: from,
                backendCallId: backendCallId
            )
        }
    }

    nonisolated func cancelledCallInviteReceived(
        cancelledCallInvite: CancelledCallInvite,
        error: Error
    ) {
        Task { @MainActor in
            self.cancelledCallInvite = cancelledCallInvite
            self.callInvite = nil
            self.pendingBackendCallId = nil
            self.delegate?.twilioVoiceIncomingInviteCanceled()
        }
    }
}
