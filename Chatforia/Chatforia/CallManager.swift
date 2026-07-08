import Foundation
import Combine
import CallKit
import TwilioVideo
import TwilioVoice
import AVFoundation

@MainActor
final class CallManager: ObservableObject {
    @Published var state: CallState = .idle
    @Published var activeSession: CallSession?
    @Published var lastError: String?
    @Published var localVideoTrack: LocalVideoTrack?
    @Published var remoteVideoTracks: [String: RemoteVideoTrack] = [:]
    @Published var remoteParticipantIdentity: String?
    @Published var isVideoCameraEnabled: Bool = true

    private let pstnService = PSTNCallService.shared
    private let twilioService = TwilioVoiceService.shared
    private let twilioVideoService = TwilioVideoService.shared
    private let callKit = CallKitManager()
    private let voipPushManager = VoIPPushManager.shared

    private var pendingAuth: AuthStore?
    private var pendingDestination: CallDestination?
    private var pendingIsVideo: Bool = false
    private var pendingIncomingPayload: IncomingCallPayload?
    private var currentUserId: Int?
    
    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
    }

    private enum CallEndOutcome: Equatable {
        case localHangup
        case remoteEnded
        case declined
        case missed
        case failed(String)
    }

    private enum FinalDisplayState {
        case ended
        case failed(String)
    }

    private var pendingEndOutcome: CallEndOutcome?
    private var finalizedCallUUID: UUID?
    private var pendingVoIPToken: String?
    private var pendingVoIPTokenData: Data?

    init() {
        twilioService.delegate = self
        twilioVideoService.delegate = self
        callKit.delegate = self
        voipPushManager.delegate = self
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSocketIncomingCall(_:)),
            name: .socketCallIncoming,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSocketCallEnded(_:)),
            name: .socketCallEnded,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSocketVideoIncoming(_:)),
            name: .socketVideoIncoming,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSocketVideoEnded(_:)),
            name: .socketVideoEnded,
            object: nil
        )
    }
    
    @objc private func handleSocketIncomingCall(_ notification: Notification) {
        guard let data = notification.userInfo else { return }

        let rawCallId = data["callId"]

        let callId: Int? = {
            if let value = rawCallId as? Int {
                return value
            }

            if let value = rawCallId as? String {
                return Int(value)
            }

            return nil
        }()

        twilioService.setPendingBackendCallId(callId)

    }
    
    @objc private func handleSocketCallEnded(_ notification: Notification) {
        guard let data = notification.userInfo else { return }

        let status = data["status"] as? String ?? "ENDED"

        disconnectVideoMediaIfNeeded()

        switch status {
        case "MISSED":
            markMissedCall()
        case "FAILED":
            failCall(appText(
                "calls.call_failed",
                languageCode: appLanguage
            ))
        case "DECLINED":
            completeCall(outcome: .declined)
        default:
            completeCall(outcome: .remoteEnded)
        }
    }
    
    @objc private func handleSocketVideoIncoming(_ notification: Notification) {
        guard let data = notification.userInfo else { return }

        let callerName = data["callerName"] as? String ?? appText(
            "calls.videoCall",
            languageCode: appLanguage
        )
        let callerId = data["callerId"] as? Int ?? 0
        let callId = data["callId"] as? Int
        let roomName = data["roomName"] as? String ?? {
            if let callId { return "call_\(callId)" }
            return "call_fallback_\(UUID().uuidString)"
        }()

        let payload = IncomingCallPayload(
            uuid: UUID(),
            displayName: callerName,
            remoteIdentity: roomName,
            hasVideo: true,
            backendCallId: callId
        )

        handleIncomingCallPayload(payload, auth: pendingAuth)

    }

    @objc private func handleSocketVideoEnded(_ notification: Notification) {
        disconnectVideoMediaIfNeeded()
        completeCall(outcome: .remoteEnded)
    }

    func toggleVideoCamera() {
        let newValue = !twilioVideoService.isCameraEnabled
        twilioVideoService.setCameraEnabled(newValue)
        isVideoCameraEnabled = newValue
    }

    func flipVideoCamera() {
        twilioVideoService.flipCamera()
    }

    func startVoIPIfNeeded(auth: AuthStore) {
        pendingAuth = auth
        currentUserId = auth.currentUser?.id

        voipPushManager.start()
        registerPendingVoIPTokenIfPossible()
    }

    func startCall(to destination: CallDestination, auth: AuthStore) {
        AnalyticsManager.shared.capture("voice_call_started", properties: [
            "direction": "outgoing",
            "destinationType": "\(destination)"
        ])

        Task {
            await beginOutgoingCall(to: destination, auth: auth, isVideo: false)
        }
    }

    func startVideoCall(to destination: CallDestination, auth: AuthStore) {
        AnalyticsManager.shared.capture("video_call_started", properties: [
            "direction": "outgoing",
            "destinationType": "\(destination)"
        ])

        switch destination {
        case .phoneNumber:
            failCall(appText(
                "calls.video_app_users_only",
                languageCode: appLanguage
            ))
        case .appUser, .videoRoom:
            Task {
                await beginOutgoingCall(to: destination, auth: auth, isVideo: true)
            }
        }
    }

    func startGroupVideoCall(roomId: Int, displayName: String?, auth: AuthStore) {
        Task {
            await beginOutgoingCall(
                to: .videoRoom(
                    roomId: roomId,
                    roomName: "chatroom_\(roomId)",
                    displayName: displayName
                ),
                auth: auth,
                isVideo: true
            )
        }
    }

    func handleIncomingCallPayload(
        _ payload: IncomingCallPayload,
        auth: AuthStore?,
        completion: ((Error?) -> Void)? = nil
    ) {
        if activeSession?.status == .ringing || activeSession?.status == .active || activeSession?.status == .connecting {
            completion?(nil)
            return
        }

        if let auth {
            pendingAuth = auth
            currentUserId = auth.currentUser?.id
        }

        pendingIncomingPayload = payload
        pendingEndOutcome = nil
        finalizedCallUUID = nil

        if payload.hasVideo {
            clearPublishedVideoState()
        }

        let destination = CallDestination.appUser(
            userId: 0,
            username: payload.displayName
        )

        activeSession = CallSession(
            id: payload.uuid,
            destination: destination,
            direction: .incoming,
            status: .ringing,
            startedAt: Date(),
            answeredAt: nil,
            endedAt: nil,
            callSid: nil,
            displayName: payload.displayName,
            remoteIdentity: payload.remoteIdentity,
            chatRoomId: nil,
            backendCallId: payload.backendCallId,
            isMuted: false,
            isSpeakerOn: payload.hasVideo,
            isVideo: payload.hasVideo
        )

        state = .ringingIncoming(payload.displayName)

        callKit.reportIncomingCall(
            uuid: payload.uuid,
            handle: payload.displayName,
            hasVideo: payload.hasVideo
        ) { error in
            if let error {
                self.failCall(error.localizedDescription)
            }

            completion?(error)
        }
    }

    func addParticipant(contact: ContactDTO) async {
        guard let session = activeSession else { return }
        guard session.canAddParticipant else { return }
        guard let callId = session.backendCallId else {
            lastError = "Missing call ID."
            return
        }
        guard let userId = contact.user?.id ?? contact.userId else {
            lastError = "This contact cannot be added to a call."
            return
        }
        guard let token = TokenStore.shared.read(), !token.isEmpty else {
            lastError = appText("error_missing_auth_token", languageCode: appLanguage)
            return
        }

        do {
            let participant = try await CallService.shared.addParticipant(
                callId: callId,
                userId: userId,
                token: token
            )

            updateSession {
                if !$0.participants.contains(where: { $0.userId == participant.userId }) {
                    $0.participants.append(participant)
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func clearPublishedVideoState() {
        localVideoTrack = nil
        remoteVideoTracks = [:]
        remoteParticipantIdentity = nil
        isVideoCameraEnabled = true
    }

    private func disconnectVideoMediaIfNeeded() {
        guard activeSession?.isVideo == true else { return }

        if twilioVideoService.hasActiveMedia {
            twilioVideoService.disconnect()
        }
    }

    private func beginOutgoingCall(to destination: CallDestination, auth: AuthStore, isVideo: Bool) async {
        lastError = nil
        pendingAuth = auth
        currentUserId = auth.currentUser?.id
        pendingEndOutcome = nil
        finalizedCallUUID = nil

        if isVideo {
            clearPublishedVideoState()
        }

        let uuid = UUID()
        let session = CallSession(
            id: uuid,
            destination: destination,
            direction: .outgoing,
            status: .starting,
            startedAt: Date(),
            answeredAt: nil,
            endedAt: nil,
            callSid: nil,
            displayName: destination.displayName,
            remoteIdentity: destination.displayName,
            chatRoomId: nil,
            backendCallId: nil,
            isMuted: false,
            isSpeakerOn: isVideo,
            isVideo: isVideo
        )

        activeSession = session
        pendingDestination = destination
        pendingIsVideo = isVideo
        state = .dialing(destination)

        if case .appUser(let userId, _) = destination {
            guard let token = auth.currentToken, !token.isEmpty else {
                failCall(appText("error_missing_auth_token", languageCode: appLanguage))
                return
            }

            do {
                if isVideo {
                    let response = try await CallService.shared.startVideoCall(
                        calleeId: userId,
                        chatRoomId: nil,
                        token: token
                    )

                    updateSession {
                        $0.backendCallId = response.callId
                        $0.remoteIdentity = response.roomName
                    }
                } else {
                    let callId = try await CallService.shared.createCall(
                        calleeId: userId,
                        mode: "AUDIO",
                        token: token
                    )

                    updateSession {
                        $0.backendCallId = callId
                    }
                }

            } catch {
                failCall(error.localizedDescription)
                return
            }
        }

        // Create external call record BEFORE CallKit, but ONLY for phone numbers
        if case .phoneNumber(let number, _) = destination {
            guard let token = auth.currentToken, !token.isEmpty else {
                failCall(appText(
                    "error_missing_auth_token",
                    languageCode: appLanguage
                ))
                return
            }

            do {

                let callId = try await CallService.shared.startExternalCall(
                    phoneNumber: number,
                    token: token
                )

                updateSession {
                    $0.backendCallId = callId
                }

            } catch {
                failCall(error.localizedDescription)
                return
            }
        }

        let callKitHandle: String
        let isPhoneNumber: Bool

        switch destination {
        case .phoneNumber(let number, _):
            callKitHandle = number
            isPhoneNumber = true

        case .appUser(let userId, _):
            callKitHandle = String(userId)
            isPhoneNumber = false

        case .videoRoom(let roomId, _, _):
            callKitHandle = "room-\(roomId)"
            isPhoneNumber = false
        }

        callKit.startOutgoingCall(
            uuid: uuid,
            handle: callKitHandle,
            isPhoneNumber: isPhoneNumber,
            onFailure: { [weak self] in
                guard let self else { return }

                Task {
                    await self.startCallAsync(
                        uuid: uuid,
                        to: destination,
                        auth: auth,
                        isVideo: isVideo
                    )
                }
            }
        )
    }
            
        private func beginPendingOutgoingCall(uuid: UUID) {
        guard let auth = pendingAuth,
              let destination = pendingDestination else {
            failCall(appText(
                "calls.missing_pending_context",
                languageCode: appLanguage
            ))
            return
        }

        Task {
            await startCallAsync(
                uuid: uuid,
                to: destination,
                auth: auth,
                isVideo: pendingIsVideo
            )
        }
    }

    private func startCallAsync(
        uuid: UUID,
        to destination: CallDestination,
        auth: AuthStore,
        isVideo: Bool
    ) async {
        guard let token = auth.currentToken, !token.isEmpty else {
            failCall(appText("error_missing_auth_token", languageCode: appLanguage))
            return
        }

        switch destination {
        case .phoneNumber(let number, let displayName):
            if isVideo {
                failCall(appText("calls.video_app_users_only", languageCode: appLanguage))
                return
            }

            updateSession {
                $0.status = .ringing
                $0.displayName = displayName ?? number
            }
            state = .dialing(destination)

            do {
                guard let backendCallId = activeSession?.backendCallId else {
                    failCall("Couldn’t start the call. Missing call record.")
                    return
                }

                updateSession {
                    $0.backendCallId = backendCallId
                    $0.status = .connecting
                    $0.displayName = displayName ?? number
                }

                twilioService.setPendingBackendCallId(backendCallId)

                let tokenResponse = try await twilioService.fetchToken(authToken: token)

                state = .connecting(displayName ?? number)

                let dialNumber = normalizedUSPhoneNumber(number)

                try await twilioService.startCall(
                    to: dialNumber,
                    accessToken: tokenResponse.token
                )

            } catch {

                failCall("Couldn’t start the call. Please try again.")
            }

        case .appUser(let userId, let username):
            updateSession {
                $0.status = .connecting
                $0.displayName = username ?? appText("calls.call", languageCode: appLanguage)
            }
            state = .fetchingToken

            if isVideo {
                do {
                    try await MediaPermissionManager.shared.ensureVideoCallPermissions()
                } catch {
                    failCall(error.localizedDescription)
                    return
                }
            }

            guard activeSession?.backendCallId != nil else {
                failCall(appText("calls.missing_backend_call_id", languageCode: appLanguage))
                return
            }

            if isVideo {
                guard let currentUser = auth.currentUser else {
                    failCall(appText("calls.missing_current_user", languageCode: appLanguage))
                    return
                }

                guard let backendCallId = activeSession?.backendCallId else {
                    failCall(appText("calls.missing_backend_call_id", languageCode: appLanguage))
                    return
                }

                let roomName = "call_\(backendCallId)"
                state = .connecting(
                    username ?? appText("calls.call", languageCode: appLanguage)
                )

                do {
                    try? await Task.sleep(nanoseconds: 500_000_000)

                    try await twilioVideoService.connect(
                        authToken: token,
                        identity: String(currentUser.id),
                        roomName: roomName
                    )
                } catch {
                    failCall(error.localizedDescription)
                }
            } else {
                do {
                    let tokenResponse = try await twilioService.fetchToken(authToken: token)
                    state = .connecting(
                        username ?? appText("calls.call", languageCode: appLanguage)
                    )

                    try await twilioService.startCall(
                        to: username ?? "",
                        accessToken: tokenResponse.token
                    )
                } catch {
                    failCall(error.localizedDescription)
                }
            }

        case .videoRoom(_, let roomName, let displayName):
            guard isVideo else {
                failCall(appText("calls.room_video_only", languageCode: appLanguage))
                return
            }

            updateSession {
                $0.status = .connecting
                $0.displayName = displayName ?? appText("calls.group_video", languageCode: appLanguage)
                $0.backendCallId = nil
            }
            state = .fetchingToken

            do {
                try await MediaPermissionManager.shared.ensureVideoCallPermissions()
            } catch {
                failCall(error.localizedDescription)
                return
            }

            guard let currentUser = auth.currentUser else {
                failCall(appText("calls.missing_current_user", languageCode: appLanguage))
                return
            }

            do {
                try? await Task.sleep(nanoseconds: 500_000_000)

                try await twilioVideoService.connect(
                    authToken: token,
                    identity: String(currentUser.id),
                    roomName: roomName
                )
            } catch {
                failCall(error.localizedDescription)
            }
        }
    }

    private func normalizedUSPhoneNumber(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }

        if digits.count == 10 {
            return "+1\(digits)"
        }

        if digits.count == 11, digits.hasPrefix("1") {
            return "+\(digits)"
        }

        if raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+") {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return raw
    }

    func toggleMute() {
        guard let session = activeSession else { return }
        let newMuted = !session.isMuted
        callKit.setMuted(uuid: session.id, muted: newMuted)
    }

    func sendDigit(_ digit: String) {
        let allowedDigits = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "#"]

        guard allowedDigits.contains(digit) else { return }
        guard activeSession?.isVideo == false else { return }
        guard case .active(_) = state else { return }

        twilioService.sendDigits(digit)
    }

    func toggleSpeaker() {
        guard activeSession != nil else { return }

        updateSession {
            $0.isSpeakerOn.toggle()
        }

        guard let isSpeakerOn = activeSession?.isSpeakerOn else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.overrideOutputAudioPort(isSpeakerOn ? .speaker : .none)
        } catch {
            state = .failed(
                appText(
                    "calls.could_not_change_audio_output",
                    languageCode: appLanguage
                )
            )
        }
    }

    func hangup() {
        AudioPlayerService.shared.stopOutgoingRingback()
        
        guard let session = activeSession else {

            twilioService.hangup()
            twilioVideoService.disconnect()

            state = .ended
            return
        }

        let sessionId = session.id
        let isVideo = session.isVideo

        pendingEndOutcome = .localHangup

        updateSession {
            $0.status = .ending
        }


        callKit.endCall(uuid: sessionId)

        if isVideo {
            twilioVideoService.disconnect()
        } else {
            twilioService.hangup()
        }

        completeCall(
            outcome: .localHangup,
            reportToCallKit: false
        )
    }
    
    func dismissEndedState() {
        switch state {
        case .ended, .failed:
            state = .idle
        default:
            break
        }
    }

    private func updateSession(_ mutate: (inout CallSession) -> Void) {
        guard var session = activeSession else { return }
        mutate(&session)
        activeSession = session
    }

    private func patchCallStatus(
        callId: Int,
        token: String,
        status: String? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        durationSec: Int? = nil,
        endReason: String? = nil,
        twilioCallSid: String? = nil
    ) async {
        struct Body: Encodable {
            let status: String?
            let startedAt: String?
            let endedAt: String?
            let durationSec: Int?
            let endReason: String?
            let twilioCallSid: String?
        }

        let iso = ISO8601DateFormatter()
        let body = Body(
            status: status,
            startedAt: startedAt.map { iso.string(from: $0) },
            endedAt: endedAt.map { iso.string(from: $0) },
            durationSec: durationSec,
            endReason: endReason,
            twilioCallSid: twilioCallSid
        )

        do {
            let encoded = try JSONEncoder().encode(body)
            let _: EmptyResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "calls/\(callId)/status",
                    method: .PATCH,
                    body: encoded,
                    requiresAuth: true
                ),
                token: token
            )
        } catch {
            debugLog("❌ Failed to patch call status:", error)
        }
    }

    private func markMissedCall() {
        completeCall(outcome: .missed)
    }

   private func failCall(_ message: String) {
        #if DEBUG
        debugLog("❌ CallManager failCall:", message)
        debugLog("❌ activeSession:", String(describing: activeSession))
        #endif
        completeCall(outcome: .failed(message))
    }

    private func finishCall(reason: CXCallEndedReason = .remoteEnded) {
        switch reason {
        case .declinedElsewhere:
            completeCall(outcome: .declined)
        case .unanswered:
            completeCall(outcome: .missed)
        case .failed:
            completeCall(
                outcome: .failed(
                    appText(
                        "calls.call_failed",
                        languageCode: appLanguage
                    )
                )
            )
        default:
            completeCall(outcome: .remoteEnded)
        }
    }

    private func resetTransientState() {
        // Keep pendingAuth so incoming calls still know the current user.
        pendingDestination = nil
        pendingIsVideo = false
        pendingIncomingPayload = nil
        pendingEndOutcome = nil
    }

    private func deactivateSystemAudioSessionIfPossible() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.overrideOutputAudioPort(.none)
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            debugLog("⚠️ Failed to deactivate audio session:", error)
        }
    }

    private func backendPayload(
        for outcome: CallEndOutcome,
        at endedAt: Date,
        session: CallSession
    ) -> (status: String, endReason: String, durationSec: Int?) {
        let duration: Int? = {
            guard let answeredAt = session.answeredAt else { return nil }
            return max(0, Int(endedAt.timeIntervalSince(answeredAt)))
        }()

        switch outcome {
        case .localHangup:
            return ("ENDED", "local_hangup", duration)
        case .remoteEnded:
            return ("ENDED", "remote_ended", duration)
        case .declined:
            return ("DECLINED", "declined", nil)
        case .missed:
            return ("MISSED", "missed", nil)
        case .failed(let message):
            return ("FAILED", message, nil)
        }
    }

    private func callKitReason(for outcome: CallEndOutcome) -> CXCallEndedReason {
        switch outcome {
        case .localHangup:
            return .remoteEnded
        case .remoteEnded:
            return .remoteEnded
        case .declined:
            return .declinedElsewhere
        case .missed:
            return .unanswered
        case .failed:
            return .failed
        }
    }

    private func finalDisplayState(for outcome: CallEndOutcome) -> FinalDisplayState {
        switch outcome {
        case .failed(let message):
            return .failed(message)
        default:
            return .ended
        }
    }

    private func registerPendingVoIPTokenIfPossible() {
        guard let voipToken = pendingVoIPToken,
            let voipTokenData = pendingVoIPTokenData,
            let authToken = TokenStore.shared.read(),
            !authToken.isEmpty else {
            return
        }


        Task {
            do {
                try await DeviceRegistrationService.shared.registerVoIPPushToken(
                    voipToken,
                    token: authToken
                )


                let voiceTokenResponse = try await twilioService.fetchToken(
                    authToken: authToken
                )

                TwilioVoiceSDK.register(
                    accessToken: voiceTokenResponse.token,
                    deviceToken: voipTokenData
                ) { error in
                    Task { @MainActor in
                        if let error {
                            debugLog("❌ Twilio VoIP registration failed:", error)
                            debugLog("❌ Twilio VoIP registration localized:", error.localizedDescription)
                            return
                        }

                        self.pendingVoIPToken = nil
                        self.pendingVoIPTokenData = nil
                    }
                }
            } catch {
                debugLog("❌ VoIP push token registration failed:", error)
            }
        }
    }

    private func completeCall(
        outcome: CallEndOutcome,
        reportToCallKit: Bool = true
    ) {
        AudioPlayerService.shared.stopOutgoingRingback()

        guard let session = activeSession else {
            state = {
                switch finalDisplayState(for: outcome) {
                case .ended: return .ended
                case .failed(let message): return .failed(message)
                }
            }()
            resetTransientState()
            return
        }

        if finalizedCallUUID == session.id {
            return
        }
        finalizedCallUUID = session.id

        let endedAt = Date()
        let backend = backendPayload(for: outcome, at: endedAt, session: session)

        updateSession {
            $0.endedAt = endedAt
            switch outcome {
            case .missed:
                $0.status = .missed
            case .declined:
                $0.status = .declined
            case .failed:
                $0.status = .failed
            default:
                $0.status = .ended
            }
        }

        if session.isVideo {
            disconnectVideoMediaIfNeeded()
        }

        clearPublishedVideoState()

        if !session.isVideo {
            deactivateSystemAudioSessionIfPossible()
        }

        if reportToCallKit {
            callKit.reportCallEnded(uuid: session.id, reason: callKitReason(for: outcome))
        }

        if let callId = session.backendCallId,
            let token = TokenStore.shared.read(),
            !token.isEmpty {
                Task {
                    await patchCallStatus(
                        callId: callId,
                        token: token,
                        status: backend.status,
                        endedAt: endedAt,
                        durationSec: backend.durationSec,
                        endReason: backend.endReason,
                        twilioCallSid: session.callSid
                    )

                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .callHistoryShouldRefresh,
                            object: nil
                        )
                    }
                }
            } else {
                NotificationCenter.default.post(
                    name: .callHistoryShouldRefresh,
                    object: nil
                )
            }

        switch finalDisplayState(for: outcome) {
        case .ended:
            state = .ended
        case .failed(let message):
            lastError = message
            state = .failed(message)
        }

        activeSession = nil
        resetTransientState()

        AnalyticsManager.shared.capture(session.isVideo ? "video_call_ended" : "voice_call_ended", properties: [
            "direction": "\(session.direction)",
            "status": backend.status,
            "endReason": backend.endReason,
            "durationSec": backend.durationSec ?? 0
        ])
    }
}

extension CallManager: CallKitManagerDelegate {
    func callKitDidRequestStartCall(uuid: UUID, handle: String) {
        guard activeSession?.id == uuid else {
            return
        }

        callKit.reportOutgoingCallConnecting(uuid: uuid)
        beginPendingOutgoingCall(uuid: uuid)
    }

    func callKitDidRequestAnswerCall(uuid: UUID) {
        guard activeSession?.id == uuid else {

            return
        }

        let now = Date()

        updateSession {
            $0.status = .connecting
            $0.answeredAt = now
        }

        if let name = activeSession?.displayName {
            state = .connecting(name)
        }

        if activeSession?.isVideo == true {
            Task {
                await answerIncomingVideoCall()
            }
        } else {
            if let callId = activeSession?.backendCallId,
               let token = TokenStore.shared.read(),
               !token.isEmpty {
                Task {
                    await patchCallStatus(
                        callId: callId,
                        token: token,
                        status: "ACTIVE",
                        startedAt: now
                    )
                }
            }

            twilioService.acceptIncomingCall()
        }
    }

    func callKitDidRequestEndCall(uuid: UUID) {
        guard activeSession?.id == uuid else {
            return
        }

        guard let session = activeSession else { return }

        if session.direction == .incoming, session.status == .ringing {
            pendingEndOutcome = .declined

            if session.isVideo {
                completeCall(outcome: .declined, reportToCallKit: false)
                return
            } else {
                twilioService.rejectIncomingCall()
                completeCall(outcome: .declined, reportToCallKit: false)
                return
            }
        }

        pendingEndOutcome = .localHangup

        updateSession {
            $0.status = .ending
        }

       if session.isVideo {
            twilioVideoService.disconnect()
        } else {
            twilioService.hangup()
        }

        completeCall(
            outcome: .localHangup,
            reportToCallKit: false
        )
    }

    func callKitDidSetMute(uuid: UUID, isMuted: Bool) {
        updateSession { $0.isMuted = isMuted }

        if activeSession?.isVideo == true {
            twilioVideoService.setMuted(isMuted)
        } else {
            twilioService.setMuted(isMuted)
        }
    }

    private func answerIncomingVideoCall() async {
        guard let token = TokenStore.shared.read(), !token.isEmpty else {
            failCall(appText("error_missing_auth_token", languageCode: appLanguage))
            return
        }

        guard let userId = pendingAuth?.currentUser?.id ?? currentUserId else {
            failCall(appText("calls.missing_current_user", languageCode: appLanguage))
            return
        }

        guard let backendCallId = activeSession?.backendCallId else {
            failCall(appText("calls.missing_backend_call_id", languageCode: appLanguage))
            return
        }

        do {
            try await MediaPermissionManager.shared.ensureVideoCallPermissions()

            await patchCallStatus(
                callId: backendCallId,
                token: token,
                status: "ACTIVE",
                startedAt: Date()
            )

            let roomName = activeSession?.remoteIdentity ?? "call_\(backendCallId)"

            try? await Task.sleep(nanoseconds: 500_000_000)

            try await twilioVideoService.connect(
                authToken: token,
                identity: String(userId),
                roomName: roomName
            )
            
        } catch {
            failCall(error.localizedDescription)
        }
    }
}

extension CallManager: TwilioVoiceServiceDelegate {
    func twilioVoiceDidStartConnecting() {
        guard let name = activeSession?.displayName else { return }

        updateSession { $0.status = .connecting }
        state = .connecting(name)
    }

    func twilioVoiceDidStartRinging() {
        guard let session = activeSession,
            session.direction == .outgoing,
            session.isVideo == false else {
            return
        }

        updateSession {
            $0.status = .ringing
        }

        AudioPlayerService.shared.playOutgoingRingback()
    }

    func twilioVoiceDidConnect(callSid: String?) {
        AudioPlayerService.shared.stopOutgoingRingback()

        guard let session = activeSession else { return }

        let now = Date()

        updateSession {
            $0.callSid = callSid
            $0.status = .active
            $0.answeredAt = now
        }

        if let callId = activeSession?.backendCallId,
           let token = TokenStore.shared.read(),
           !token.isEmpty {
            Task {
                await patchCallStatus(
                    callId: callId,
                    token: token,
                    status: "ACTIVE",
                    startedAt: now,
                    twilioCallSid: callSid
                )
            }
        }

        callKit.reportOutgoingCallConnected(uuid: session.id)
        state = .active(session.displayName)
    }

    func twilioVoiceDidDisconnect() {
        let outcome = pendingEndOutcome ?? .remoteEnded
        completeCall(outcome: outcome)
    }

    func twilioVoiceDidFail(_ message: String) {
        completeCall(outcome: .failed(message))
    }

    func twilioVoiceDidReceiveIncoming(from: String, backendCallId: Int?) {
        let payload = IncomingCallPayload(
            uuid: UUID(),
            displayName: from,
            remoteIdentity: from,
            hasVideo: false,
            backendCallId: backendCallId
        )

        handleIncomingCallPayload(payload, auth: pendingAuth)
    }

    func twilioVoiceIncomingInviteCanceled() {
        guard let session = activeSession else { return }

        if finalizedCallUUID == session.id {
            return
        }

        if pendingEndOutcome == .declined {
            return
        }

        if session.status == .ringing && session.direction == .incoming {
            completeCall(outcome: .missed)
        } else {
            completeCall(outcome: .remoteEnded)
        }
    }
}

extension CallManager: TwilioVideoServiceDelegate {
    func twilioVideoDidStartConnecting(roomName: String) {
        guard let name = activeSession?.displayName else { return }
        updateSession { $0.status = .connecting }
        state = .connecting(name)
    }

    func twilioVideoDidConnect(roomName: String) {
        guard let session = activeSession else { return }

        let now = Date()

        updateSession {
            $0.status = .active
            if $0.answeredAt == nil {
                $0.answeredAt = now
            }
        }

        isVideoCameraEnabled = twilioVideoService.isCameraEnabled
        localVideoTrack = twilioVideoService.currentLocalVideoTrack()

        if let callId = activeSession?.backendCallId,
           let token = TokenStore.shared.read(),
           !token.isEmpty {
            Task {
                await patchCallStatus(
                    callId: callId,
                    token: token,
                    status: "ACTIVE",
                    startedAt: now
                )
            }
        }

        callKit.reportOutgoingCallConnected(uuid: session.id)
        state = .active(session.displayName)
    }

    func twilioVideoDidDisconnect(roomName: String?) {
        let outcome = pendingEndOutcome ?? .remoteEnded
        completeCall(outcome: outcome)
    }

    func twilioVideoDidFail(_ message: String) {
        #if DEBUG
        debugLog("❌ CallManager twilioVideoDidFail:", message)
        debugLog("❌ activeSession before video fail:", String(describing: activeSession))
        #endif
        completeCall(outcome: .failed(message))
    }

    func twilioVideoDidAddLocalVideoTrack(_ track: LocalVideoTrack) {
        localVideoTrack = track
    }

    func twilioVideoDidRemoveLocalVideoTrack() {
        localVideoTrack = nil
    }

    func twilioVideoRemoteParticipantDidConnect(identity: String) {
        remoteParticipantIdentity = identity
    }

    func twilioVideoRemoteParticipantDidDisconnect(identity: String) {
        if remoteParticipantIdentity == identity {
            remoteParticipantIdentity = nil
        }
        remoteVideoTracks.removeValue(forKey: identity)
    }

    func twilioVideoDidSubscribeToRemoteVideoTrack(
        _ track: RemoteVideoTrack,
        participantIdentity: String
    ) {
        remoteParticipantIdentity = participantIdentity
        remoteVideoTracks[participantIdentity] = track
    }

    func twilioVideoDidUnsubscribeFromRemoteVideoTrack(participantIdentity: String) {
        remoteVideoTracks.removeValue(forKey: participantIdentity)
    }

    func twilioVideoDidSubscribeToRemoteAudioTrack(participantIdentity: String) {
        // no-op for now
    }

    func twilioVideoDidUnsubscribeFromRemoteAudioTrack(participantIdentity: String) {
        // no-op for now
    }
    
}

extension CallManager: VoIPPushManagerDelegate {
    func voipPushManagerDidUpdateToken(_ token: String, tokenData: Data) {
        pendingVoIPToken = token
        pendingVoIPTokenData = tokenData
        registerPendingVoIPTokenIfPossible()
    }

    func voipPushManagerDidInvalidateToken() {
        debugLog("ℹ️ VoIP push token invalidated")
    }

    func voipPushManagerDidReceiveIncomingCall(
        _ payload: IncomingCallPayload,
        completion: @escaping () -> Void
    ) {
        handleIncomingCallPayload(payload, auth: pendingAuth) { error in
            if let error {
                debugLog("❌ Failed to report VoIP incoming call to CallKit:", error)
            }

            completion()
        }
    }
}