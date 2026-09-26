import Foundation
import AVFoundation
import TwilioVoice

@MainActor
protocol TwilioVoiceServiceDelegate: AnyObject {
    func twilioVoiceDidStartConnecting()
    func twilioVoiceDidStartRinging()
    func twilioVoiceDidConnect(callSid: String?)
    func twilioVoiceDidDisconnect()
    func twilioVoiceDidFail(_ message: String)
    func twilioVoiceDidReceiveIncoming(
        from: String,
        backendCallId: Int?,
        completion: @escaping () -> Void
    )
    func twilioVoiceIncomingInviteCanceled()
}

@MainActor
final class TwilioVoiceService: NSObject {
    static let shared = TwilioVoiceService()

    weak var delegate: TwilioVoiceServiceDelegate?
    
    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
    }

    private var activeCall: Call?
    private let audioDevice = DefaultAudioDevice()
    private var callInvite: CallInvite?
    private var cancelledCallInvite: CancelledCallInvite?
    private var accessToken: String?
    private var pendingBackendCallId: Int?
    private var pendingIncomingPushCompletion: (() -> Void)?

    private(set) var isReady = false
    private(set) var isMuted = false

    func setCallKitAudioEnabled(_ enabled: Bool) {
        audioDevice.isEnabled = enabled
        NSLog("📞 Twilio Voice audio device enabled=%@", enabled ? "yes" : "no")
    }

    override private init() {
        super.init()
        audioDevice.isEnabled = false
        TwilioVoiceSDK.audioDevice = audioDevice
    }

    func fetchToken(authToken: String?) async throws -> VoiceTokenResponseDTO {
        struct Request: Encodable {
            let platform: String
            let pushEnvironment: String
            let deviceId: String
        }

        #if DEBUG
        let pushEnvironment = "sandbox"
        #else
        let pushEnvironment = "production"
        #endif

        let body = try JSONEncoder().encode(
            Request(
                platform: "ios",
                pushEnvironment: pushEnvironment,
                deviceId:
                    DeviceKeyManager.shared
                        .getOrCreateDeviceId()
            )
        )

        return try await APIClient.shared.send(
            APIRequest(
                path: "voice/client/token",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: authToken
        )
    }

    func prepare(authToken: String?) async throws {
        do {
            let response = try await fetchToken(authToken: authToken)
            self.accessToken = response.token
            self.isReady = true
        } catch {
            self.isReady = false
            delegate?.twilioVoiceDidFail(
                appText(
                    "calls.serviceUnavailable",
                    languageCode: appLanguage
                )
            )
            throw error
        }
    }

    func setPendingBackendCallId(_ id: Int?) {
        pendingBackendCallId = id
    }

    func handleIncomingPushNotification(
        _ data: [String: Any],
        backendCallId: Int?,
        completion: @escaping () -> Void
    ) {
        pendingBackendCallId = backendCallId
        pendingIncomingPushCompletion = completion

        NSLog("📞 Passing incoming PushKit payload to Twilio Voice")

        TwilioVoiceSDK.handleNotification(
            data,
            delegate: self,
            delegateQueue: nil
        )
    }

    func startCall(
        to: String,
        backendCallId: Int?,
        accessToken: String
    ) async throws {
        self.accessToken = accessToken
        try configureAudioSession(activate: true)

        var callParams = ["To": to]

        if let backendCallId = backendCallId {
            callParams["backendCallId"] = String(backendCallId)
        }

        let options = ConnectOptions(accessToken: accessToken) { builder in
            builder.params = callParams
        }

        delegate?.twilioVoiceDidStartConnecting()
        activeCall = TwilioVoiceSDK.connect(options: options, delegate: self)
    }

    private var incomingCallKitAudioPrepared = false

    func prepareIncomingCallKitAudioSession() throws {
        try configureAudioSession(activate: false)
        incomingCallKitAudioPrepared = true
        NSLog("✅ Incoming Voice audio session prepared before CallKit answer fulfillment")
    }

    func acceptIncomingCall(callKitUUID: UUID) {


        guard let callInvite else {
            delegate?.twilioVoiceDidFail(
                appText(
                    "calls.noIncomingCallToAnswer",
                    languageCode: appLanguage
                )
            )
            return
        }

        do {
            debugLog(
                "📞 Accepting incoming Twilio CallInvite:",
                callInvite.callSid
            )

            if !incomingCallKitAudioPrepared {
                try configureAudioSession(activate: false)
            }
            incomingCallKitAudioPrepared = false

            let acceptOptions = AcceptOptions(callInvite: callInvite) { builder in
                builder.uuid = callKitUUID
            }

            activeCall = callInvite.accept(options: acceptOptions, delegate: self)

            debugLog(
                "📞 Twilio CallInvite accept invoked; activeCall:",
                String(describing: activeCall?.sid)
            )

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

        let call = activeCall

        activeCall = nil
        callInvite = nil
        cancelledCallInvite = nil
        pendingBackendCallId = nil
        isMuted = false

        if let call {
            call.disconnect()
        } else {
            delegate?.twilioVoiceDidDisconnect()
        }
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
            delegate?.twilioVoiceDidFail(
                appText(
                    "calls.could_not_change_audio_output",
                    languageCode: appLanguage
                )
            )
        }
    }

    func sendDigits(_ digits: String) {
        let allowedDigits = Set("0123456789*#w")
        let cleanedDigits = digits.filter { allowedDigits.contains($0) }

        guard !cleanedDigits.isEmpty else { return }

        activeCall?.sendDigits(cleanedDigits)
    }

    private func configureAudioSession(activate: Bool) throws {
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothHFP, .defaultToSpeaker]
        )

        // Outgoing calls may activate immediately.
        // Incoming CallKit calls must allow CallKit to activate the session.
        if activate {
            try session.setActive(true)
        }
    }
}

extension TwilioVoiceService: CallDelegate {
    nonisolated func callDidStartRinging(call: Call) {
        Task { @MainActor in
            self.delegate?.twilioVoiceDidStartRinging()
        }
    }

    nonisolated func callDidConnect(call: Call) {
        NSLog("✅ Twilio callDidConnect: %@", String(describing: call.sid))
        Task { @MainActor in
            self.activeCall = call
            self.delegate?.twilioVoiceDidConnect(callSid: call.sid)
        }
    }

    nonisolated func callDidDisconnect(call: Call, error: Error?) {
        NSLog("ℹ️ Twilio callDidDisconnect: %@", String(describing: error))
        Task { @MainActor in
            #if DEBUG
            if let error {
                debugLog("❌ Twilio disconnect error:", error)
                debugLog("❌ Twilio disconnect localized:", error.localizedDescription)
            } else {
                debugLog("✅ Twilio disconnected cleanly")
            }
            #endif

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
        NSLog("❌ Twilio callDidFailToConnect: %@", error.localizedDescription)
        Task { @MainActor in
            debugLog("❌ Twilio call failed to connect:", error)
            debugLog(
                "❌ Twilio call failed localized:",
                error.localizedDescription
            )
            debugLog(
                "❌ Twilio failed call SID:",
                call.sid ?? "nil"
            )

            self.activeCall = nil
            self.isMuted = false
            self.delegate?.twilioVoiceDidFail(error.localizedDescription)
        }
    }
}

extension TwilioVoiceService: NotificationDelegate {
    nonisolated func callInviteReceived(callInvite: CallInvite) {
        MainActor.assumeIsolated {
            NSLog("📞 Twilio Voice call invite received")

            self.callInvite = callInvite

            let customParameters =
                callInvite.customParameters ?? [:]

            let customCallerName =
                customParameters["callerName"]?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

            let from =
                customCallerName?.isEmpty == false
                    ? customCallerName!
                    : (
                        callInvite.from ??
                        appText(
                            "calls.incomingCall",
                            languageCode: appLanguage
                        )
                    )

            let parameterBackendCallId =
                customParameters["backendCallId"]
                    .flatMap(Int.init)

            let backendCallId =
                self.pendingBackendCallId ??
                parameterBackendCallId
            let pushCompletion =
                self.pendingIncomingPushCompletion

            self.pendingBackendCallId = nil
            self.pendingIncomingPushCompletion = nil

            guard let delegate = self.delegate else {
                NSLog(
                    "⚠️ Twilio call invite received without a delegate"
                )
                pushCompletion?()
                return
            }

            delegate.twilioVoiceDidReceiveIncoming(
                from: from,
                backendCallId: backendCallId,
                completion: {
                    pushCompletion?()
                }
            )
        }
    }

    nonisolated func cancelledCallInviteReceived(
        cancelledCallInvite: CancelledCallInvite,
        error: Error
    ) {
        Task { @MainActor in
            let pushCompletion =
                self.pendingIncomingPushCompletion

            self.cancelledCallInvite = cancelledCallInvite
            self.callInvite = nil
            self.pendingBackendCallId = nil
            self.pendingIncomingPushCompletion = nil

            self.delegate?.twilioVoiceIncomingInviteCanceled()
            pushCompletion?()
        }
    }
}
