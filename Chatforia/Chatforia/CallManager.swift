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
    private var pendingIncomingCompletion: ((Error?) -> Void)?
    private var waitingForCanonicalIncomingCall = false
    private var glareIncomingWaitTask: Task<Void, Never>?
    private var outgoingIntentPending = false
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

    private enum CallStatusPatchResult {
        case success
        case answeredElsewhere
        case failed
    }

    private var pendingEndOutcome: CallEndOutcome?
    private var finalizedCallUUID: UUID?
    private var pendingVoIPToken: String?
    private var pendingVoIPTokenData: Data?
    private var isVoIPRegistrationInFlight = false
    private var transientErrorDismissTask: Task<Void, Never>?
    private var transientErrorID: UUID?

    // CallKit may activate before the video session is ready.
    // Preserve its state and apply it when media connects.
    private var isCallKitAudioSessionActive = false

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
    
    @objc private func handleSocketIncomingCall(
        _ notification: Notification
    ) {
        guard let data = notification.userInfo else {
            return
        }

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

        let callerName =
            data["callerName"] as? String ??
            data["from"] as? String ??
            appText(
                "calls.incomingCall",
                languageCode: appLanguage
            )

        let mode =
            (data["mode"] as? String)?
                .uppercased() ?? "AUDIO"

        let payload = IncomingCallPayload(
            uuid: UUID(),
            displayName: callerName,
            remoteIdentity: callerName,
            hasVideo: mode == "VIDEO",
            backendCallId: callId
        )

        /*
         * Preserve the backend ID for the Twilio CallInvite, then let
         * CallManager's glare arbitration adopt the canonical incoming
         * call from this foreground socket event.
         */
        twilioService.setPendingBackendCallId(callId)

        handleIncomingCallPayload(
            payload,
            auth: pendingAuth
        )
    }
    
    private func lifecycleCallId(
        from data: [AnyHashable: Any]
    ) -> Int? {
        if let value = data["callId"] as? Int {
            return value
        }

        if let value = data["callId"] as? NSNumber {
            return value.intValue
        }

        if let value = data["callId"] as? String {
            return Int(value)
        }

        return nil
    }

    private func shouldHandleLifecycleEvent(
        _ data: [AnyHashable: Any]
    ) -> Bool {
        guard let eventCallId =
                lifecycleCallId(from: data)
        else {
            return false
        }

        guard let currentCallId =
                activeSession?.backendCallId
        else {
            return false
        }

        return eventCallId == currentCallId
    }

    @objc private func handleSocketCallEnded(
        _ notification: Notification
    ) {
        guard let data = notification.userInfo else { return }
        guard shouldHandleLifecycleEvent(data) else { return }

        let status =
            (data["status"] as? String)?
                .uppercased() ?? "ENDED"

        if status == "ANSWERED_ELSEWHERE" {
            // This event is broadcast to every device on the callee
            // account, including the device that won the answer claim.
            guard activeSession?.answeredAt == nil else {
                return
            }

            dismissAnsweredElsewhere()
            return
        }

        disconnectVideoMediaIfNeeded()

        switch status {
        case "MISSED":
            markMissedCall()

        case "FAILED":
            failCall(
                appText(
                    "calls.call_failed",
                    languageCode: appLanguage
                )
            )

        case "DECLINED":
            AudioPlayerService.shared.stopOutgoingRingback()
            pendingEndOutcome = .declined

            if activeSession?.isVideo == true {
                twilioVideoService.disconnect()
            } else {
                twilioService.hangup()
            }

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

    @objc private func handleSocketVideoEnded(
        _ notification: Notification
    ) {
        guard let data = notification.userInfo else { return }
        guard shouldHandleLifecycleEvent(data) else { return }

        let status =
            (data["status"] as? String)?
                .uppercased() ?? "ENDED"

        if status == "ANSWERED_ELSEWHERE" {
            // The winning device has already recorded answeredAt and
            // must ignore the same-account loser-dismissal broadcast.
            guard activeSession?.answeredAt == nil else {
                return
            }

            dismissAnsweredElsewhere()
            return
        }

        disconnectVideoMediaIfNeeded()

        switch status {
        case "MISSED":
            markMissedCall()

        case "FAILED":
            failCall(
                appText(
                    "calls.call_failed",
                    languageCode: appLanguage
                )
            )

        case "DECLINED":
            pendingEndOutcome = .declined
            completeCall(outcome: .declined)

        default:
            completeCall(outcome: .remoteEnded)
        }
    }

    func toggleVideoCamera() {
        let newValue = !twilioVideoService.isCameraEnabled
        twilioVideoService.setCameraEnabled(newValue)
        isVideoCameraEnabled = newValue
    }

    func flipVideoCamera() {
        twilioVideoService.flipCamera()
    }

    private struct CallStatusWatchResponse: Decodable {
        let call: CallStatusWatchCall
    }

    private struct CallStatusWatchCall: Decodable {
        let status: String?
    }

    private var outgoingAudioAnswerWatchTask:
        Task<Void, Never>?

    func startVoIPIfNeeded(auth: AuthStore) {
        pendingAuth = auth
        currentUserId = auth.currentUser?.id

        voipPushManager.start()
        registerPendingVoIPTokenIfPossible()
    }

    func startCall(to destination: CallDestination, auth: AuthStore) {
        guard !outgoingIntentPending,
              !waitingForCanonicalIncomingCall,
              activeSession == nil else {
            return
        }

        AnalyticsManager.shared.capture("voice_call_started", properties: [
            "direction": "outgoing",
            "destinationType": "\(destination)"
        ])

        /*
         * Record the user's outgoing intent synchronously. This protects
         * the interval before microphone permission finishes.
         */
        outgoingIntentPending = true

        Task {
            await beginOutgoingCall(to: destination, auth: auth, isVideo: false)
        }
    }

    func startVideoCall(to destination: CallDestination, auth: AuthStore) {
        guard !outgoingIntentPending,
              !waitingForCanonicalIncomingCall,
              activeSession == nil else {
            return
        }

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
            outgoingIntentPending = true

            Task {
                await beginOutgoingCall(to: destination, auth: auth, isVideo: true)
            }
        }
    }

    func startGroupVideoCall(roomId: Int, displayName: String?, auth: AuthStore) {
        guard !outgoingIntentPending,
              !waitingForCanonicalIncomingCall,
              activeSession == nil else {
            return
        }

        outgoingIntentPending = true

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
        /*
         * The user has pressed Call, but beginOutgoingCall may still be
         * waiting for microphone permission and may not have created its
         * CallSession yet. Buffer the incoming call until /calls/invite
         * determines which request survives.
         */
        if outgoingIntentPending {
            if pendingIncomingPayload == nil ||
                (pendingIncomingPayload?.backendCallId == nil &&
                 payload.backendCallId != nil) {
                pendingIncomingPayload = payload
            }

            if let completion {
                pendingIncomingCompletion = completion
            }

            return
        }

        /*
         * During simultaneous cross-calling, let the backend advisory lock
         * decide which call survives. Do not replace a brand-new outgoing
         * session before its /calls/invite request resolves.
         */
        if let session = activeSession,
           session.direction == .outgoing,
           session.status == .starting {
            if pendingIncomingPayload == nil ||
                (pendingIncomingPayload?.backendCallId == nil &&
                 payload.backendCallId != nil) {
                pendingIncomingPayload = payload
            }

            if let completion {
                pendingIncomingCompletion = completion
            }

            return
        }

        /*
         * A 409 already told this client that the reciprocal call won.
         * The first canonical incoming payload may now be displayed.
         */
        if waitingForCanonicalIncomingCall {
            waitingForCanonicalIncomingCall = false
            glareIncomingWaitTask?.cancel()
            glareIncomingWaitTask = nil
        }

        if activeSession?.status == .ringing ||
            activeSession?.status == .active ||
            activeSession?.status == .connecting {
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

    private func showTransientError(_ message: String) {
        transientErrorDismissTask?.cancel()

        let errorID = UUID()
        transientErrorID = errorID

        lastError = message
        state = .failed(message)

        transientErrorDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return
            }

            guard let self,
                  self.transientErrorID == errorID else {
                return
            }

            self.lastError = nil

            if case .failed = self.state {
                self.state = .idle
            }

            self.transientErrorID = nil
            self.transientErrorDismissTask = nil
        }
    }

    private func beginOutgoingCall(to destination: CallDestination, auth: AuthStore, isVideo: Bool) async {
        transientErrorDismissTask?.cancel()
        transientErrorDismissTask = nil
        transientErrorID = nil
        lastError = nil

        if case .failed = state {
            state = .idle
        }

        do {
            if isVideo {
                try await MediaPermissionManager.shared.ensureVideoCallPermissions()
            } else {
                try await MediaPermissionManager.shared.ensureMicrophonePermission()
            }
        } catch {
            outgoingIntentPending = false
            showTransientError(error.localizedDescription)
            return
        }

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
        outgoingIntentPending = false
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
                    let callId = try await CallService.shared.createCall(
                        calleeId: userId,
                        mode: "VIDEO",
                        token: token
                    )

                    updateSession {
                        $0.backendCallId = callId
                        $0.remoteIdentity = "call_\(callId)"
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

            } catch let apiError as APIError {
                if case .server(let status, _, _, _) = apiError,
                   status == 409 {
                    resolveOutgoingGlareLoss()
                    return
                }

                failCall(apiError.localizedDescription)
                return
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
                    backendCallId: backendCallId,
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

            if isVideo {
                state = .fetchingToken
            } else {
                // Keep outgoing audio calls visually in Calling
                // while credentials and Twilio media are prepared.
                state = .dialing(destination)
            }

            if isVideo {
                do {
                    try await MediaPermissionManager.shared.ensureVideoCallPermissions()
                } catch {
                    failCall(error.localizedDescription)
                    return
                }
            }

            guard let backendCallId = activeSession?.backendCallId else {
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

                guard let callUUID = activeSession?.id else {
                    failCall(
                        appText(
                            "calls.call_failed",
                            languageCode: appLanguage
                        )
                    )
                    return
                }

                let roomName = "call_\(backendCallId)"
                state = .connecting(
                    username ?? appText("calls.call", languageCode: appLanguage)
                )

                do {
                    try? await Task.sleep(nanoseconds: 500_000_000)

                    print(
                        "📹 Preparing Twilio Video connection; " +
                        "CallKitAudioActive=\(isCallKitAudioSessionActive || callKit.isAudioSessionActive)"
                    )

                    isCallKitAudioSessionActive =
                        isCallKitAudioSessionActive ||
                        callKit.isAudioSessionActive

                    twilioVideoService.setCallKitAudioEnabled(
                        isCallKitAudioSessionActive
                    )

                    try await twilioVideoService.connect(
                        authToken: token,
                        identity: String(currentUser.id),
                        roomName: roomName,
                        callUUID: callUUID
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
                        to: String(userId),
                        backendCallId: backendCallId,
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

            guard let callUUID = activeSession?.id else {
                failCall(
                    appText(
                        "calls.call_failed",
                        languageCode: appLanguage
                    )
                )
                return
            }

            do {
                try? await Task.sleep(nanoseconds: 500_000_000)

                print(
                    "📹 Preparing Twilio Video connection; " +
                    "CallKitAudioActive=\(isCallKitAudioSessionActive || callKit.isAudioSessionActive)"
                )

                isCallKitAudioSessionActive =
                    isCallKitAudioSessionActive ||
                    callKit.isAudioSessionActive

                twilioVideoService.setCallKitAudioEnabled(
                    isCallKitAudioSessionActive
                )

                try await twilioVideoService.connect(
                    authToken: token,
                    identity: String(currentUser.id),
                    roomName: roomName,
                    callUUID: callUUID
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

    private func startOutgoingAudioAnswerWatch(
        session: CallSession
    ) {
        outgoingAudioAnswerWatchTask?.cancel()

        guard let callId = session.backendCallId,
              let token = TokenStore.shared.read(),
              !token.isEmpty else {
            return
        }

        outgoingAudioAnswerWatchTask =
            Task { [weak self] in
                guard let self else { return }

                for _ in 0..<80 {
                    guard !Task.isCancelled else {
                        return
                    }

                    guard let current = self.activeSession,
                          current.id == session.id,
                          current.direction == .outgoing,
                          current.isVideo == false,
                          current.answeredAt == nil,
                          case .appUser = current.destination else {
                        return
                    }

                    do {
                        let response:
                            CallStatusWatchResponse =
                            try await APIClient.shared.send(
                                APIRequest(
                                    path:
                                        "calls/\(callId)/status",
                                    method: .GET,
                                    requiresAuth: true
                                ),
                                token: token
                            )

                        switch response.call.status?
                            .uppercased() {
                        case "ACTIVE":
                            let answeredAt = Date()

                            AudioPlayerService.shared
                                .stopOutgoingRingback()

                            self.updateSession {
                                $0.status = .active

                                if $0.answeredAt == nil {
                                    $0.answeredAt =
                                        answeredAt
                                }
                            }

                            self.callKit
                                .reportOutgoingCallConnected(
                                    uuid: session.id
                                )

                            self.state =
                                .active(
                                    current.displayName
                                )

                            self.outgoingAudioAnswerWatchTask =
                                nil

                            return

                        case "DECLINED",
                             "MISSED",
                             "FAILED",
                             "ENDED":
                            AudioPlayerService.shared
                                .stopOutgoingRingback()

                            self.outgoingAudioAnswerWatchTask =
                                nil

                            return

                        default:
                            break
                        }
                    } catch {
                        // A temporary lookup failure should not end
                        // an otherwise valid call.
                    }

                    do {
                        try await Task.sleep(
                            nanoseconds: 250_000_000
                        )
                    } catch {
                        return
                    }
                }
            }
    }

    private func disconnectAndCompleteLocalHangup(
        session: CallSession,
        reportToCallKit: Bool
    ) {
        if session.isVideo {
            twilioVideoService.disconnect()
        } else {
            twilioService.hangup()
        }

        completeCall(
            outcome: .localHangup,
            reportToCallKit: reportToCallKit
        )
    }

    private func finishLocalHangup(
        session: CallSession,
        reportToCallKit: Bool
    ) {
        let callerCanceledBeforeAnswer =
            session.direction == .outgoing &&
            session.answeredAt == nil

        guard callerCanceledBeforeAnswer,
              let callId = session.backendCallId,
              let token = TokenStore.shared.read(),
              !token.isEmpty else {
            disconnectAndCompleteLocalHangup(
                session: session,
                reportToCallKit: reportToCallKit
            )
            return
        }

        let endedAt = Date()

        Task { [weak self] in
            guard let self else { return }

            // Persist Canceled before disconnecting Twilio.
            // This prevents the later no-answer callback from
            // winning the terminal-state race.
            await self.patchCallStatus(
                callId: callId,
                token: token,
                status: "ENDED",
                endedAt: endedAt,
                endReason: "caller_canceled",
                twilioCallSid: session.callSid
            )

            guard self.activeSession?.id ==
                    session.id else {
                return
            }

            self.disconnectAndCompleteLocalHangup(
                session: session,
                reportToCallKit: reportToCallKit
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

        guard session.status != .ending else {
            return
        }

        let isUnansweredIncoming =
            session.direction == .incoming &&
            session.answeredAt == nil

        if isUnansweredIncoming {
            pendingEndOutcome = .declined

            callKit.endCall(uuid: session.id)

            if session.isVideo {
                completeCall(
                    outcome: .declined,
                    reportToCallKit: false
                )
            } else {
                twilioService.rejectIncomingCall()

                completeCall(
                    outcome: .declined,
                    reportToCallKit: false
                )
            }

            return
        }

        pendingEndOutcome = .localHangup

        updateSession {
            $0.status = .ending
        }

        callKit.endCall(uuid: session.id)

        finishLocalHangup(
            session: session,
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

    private func resolveOutgoingGlareLoss() {
        outgoingIntentPending = false
        AudioPlayerService.shared.stopOutgoingRingback()

        let bufferedPayload = pendingIncomingPayload
        let bufferedCompletion = pendingIncomingCompletion

        /*
         * The backend rejected this outgoing attempt before CallKit or
         * Twilio media started. Clear only the local outgoing state.
         * Do not call completeCall(), resetTransientState(), or
         * twilioService.hangup(), because those paths can discard the
         * surviving incoming payload or Twilio CallInvite.
         */
        pendingIncomingPayload = nil
        pendingIncomingCompletion = nil
        pendingDestination = nil
        pendingIsVideo = false
        pendingEndOutcome = nil
        finalizedCallUUID = nil
        activeSession = nil
        state = .idle
        lastError = nil

        if let bufferedPayload {
            handleIncomingCallPayload(
                bufferedPayload,
                auth: pendingAuth,
                completion: bufferedCompletion
            )
            return
        }

        /*
         * The 409 response can arrive slightly before the winning request
         * finishes sending its incoming socket/VoIP notification.
         */
        waitingForCanonicalIncomingCall = true
        glareIncomingWaitTask?.cancel()

        glareIncomingWaitTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return
            }

            guard let self,
                  self.waitingForCanonicalIncomingCall else {
                return
            }

            self.waitingForCanonicalIncomingCall = false
            self.glareIncomingWaitTask = nil
            self.state = .idle
        }
    }

    private func updateSession(_ mutate: (inout CallSession) -> Void) {
        guard var session = activeSession else { return }
        mutate(&session)
        activeSession = session
    }

    @discardableResult
    private func patchCallStatus(
        callId: Int,
        token: String,
        status: String? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        durationSec: Int? = nil,
        endReason: String? = nil,
        twilioCallSid: String? = nil
    ) async -> CallStatusPatchResult {
        struct Body: Encodable {
            let status: String?
            let startedAt: String?
            let endedAt: String?
            let durationSec: Int?
            let endReason: String?
            let twilioCallSid: String?
            let deviceId: String
        }

        let iso = ISO8601DateFormatter()
        let body = Body(
            status: status,
            startedAt: startedAt.map { iso.string(from: $0) },
            endedAt: endedAt.map { iso.string(from: $0) },
            durationSec: durationSec,
            endReason: endReason,
            twilioCallSid: twilioCallSid,
            deviceId: DeviceIdentityStorage.shared.getOrCreateDeviceId()
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

            return .success
        } catch let apiError as APIError {
            if case .server(
                let status,
                let code,
                _,
                _
            ) = apiError,
               status == 409,
               code == "CALL_ANSWERED_ELSEWHERE" {
                return .answeredElsewhere
            }

            debugLog(
                "❌ Failed to patch call status:",
                apiError
            )

            return .failed
        } catch {
            debugLog(
                "❌ Failed to patch call status:",
                error
            )

            return .failed
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

    private func dismissAnsweredElsewhere() {
        guard let session = activeSession else {
            return
        }

        AudioPlayerService.shared.stopOutgoingRingback()

        let shouldRejectIncomingAudio =
            !session.isVideo &&
            session.answeredAt == nil

        /*
         Finalize locally before disconnecting Twilio.

         Twilio may synchronously invoke a disconnect delegate.
         completeCall records finalizedCallUUID first, preventing
         that delegate from reporting ENDED to the canonical
         backend call won by another device.
         */
        completeCall(
            outcome: .remoteEnded,
            reportToBackend: false
        )

        guard !session.isVideo else {
            return
        }

        if shouldRejectIncomingAudio {
            twilioService.rejectIncomingCall()
        } else {
            twilioService.hangup()
        }
    }

    private func failAnswerClaimLocally() {
        completeCall(
            outcome: .failed(
                appText(
                    "calls.call_failed",
                    languageCode: appLanguage
                )
            ),
            reportToBackend: false
        )
    }

    private func resetTransientState() {
        outgoingIntentPending = false
        outgoingAudioAnswerWatchTask?.cancel()
        outgoingAudioAnswerWatchTask = nil

        // Keep pendingAuth so incoming calls still know the current user.
        pendingDestination = nil
        pendingIsVideo = false
        pendingIncomingPayload = nil
        pendingIncomingCompletion = nil
        waitingForCanonicalIncomingCall = false
        glareIncomingWaitTask?.cancel()
        glareIncomingWaitTask = nil
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
            let callerCanceledBeforeAnswer =
                session.direction == .outgoing &&
                session.answeredAt == nil

            if callerCanceledBeforeAnswer {
                return (
                    "ENDED",
                    "caller_canceled",
                    nil
                )
            }

            return (
                "ENDED",
                "local_hangup",
                duration
            )

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

    private func markVideoCallAnsweredIfNeeded() {
        guard let session = activeSession,
              session.isVideo else {
            return
        }

        let now = Date()
        let answeredAt = session.answeredAt ?? now

        // Only the first genuine remote answer should patch the backend
        // and report the outgoing CallKit call as connected.
        let isFirstAnswer =
            session.answeredAt == nil

        updateSession {
            $0.status = .active

            if $0.answeredAt == nil {
                $0.answeredAt = answeredAt
            }
        }

        if isFirstAnswer,
           let callId = session.backendCallId,
           let token = TokenStore.shared.read(),
           !token.isEmpty {
            Task {
                await patchCallStatus(
                    callId: callId,
                    token: token,
                    status: "ACTIVE",
                    startedAt: answeredAt
                )
            }
        }

        if isFirstAnswer &&
            session.direction == .outgoing {
            callKit.reportOutgoingCallConnected(
                uuid: session.id
            )
        }

        state = .active(session.displayName)
    }

    private func registerPendingVoIPTokenIfPossible() {
        guard !isVoIPRegistrationInFlight,
              let voipToken = pendingVoIPToken,
              let voipTokenData = pendingVoIPTokenData,
              let authToken = TokenStore.shared.read(),
              !authToken.isEmpty
        else {
            return
        }

        isVoIPRegistrationInFlight = true
        NSLog("📞 Starting Twilio VoIP registration")

        Task {
            do {
                _ = try await DeviceRegistrationService.shared
                    .ensureCurrentDeviceRegistered(
                        userId: currentUserId ?? 0,
                        token: authToken
                    )

                try await DeviceRegistrationService.shared
                    .registerVoIPPushToken(
                        voipToken,
                        token: authToken
                    )

                let voiceTokenResponse =
                    try await twilioService.fetchToken(
                        authToken: authToken
                    )

            TwilioVoiceSDK.register(
                accessToken: voiceTokenResponse.token,
                deviceToken: voipTokenData
            ) { error in
                Task { @MainActor in
                    if let error {
                        self.isVoIPRegistrationInFlight = false

                        NSLog(
                            "❌ Twilio VoIP registration failed: %@",
                            error.localizedDescription
                        )

                        /*
                         * Retain the pending token so a later app-active
                         * event can retry registration.
                         */
                        return
                    }

                    NSLog("✅ Twilio VoIP registration succeeded")

                    do {
                        try await DeviceRegistrationService.shared
                            .confirmVoiceRegistration(
                                token: authToken
                            )

                        NSLog(
                            "✅ Backend Voice registration confirmation succeeded"
                        )
                    } catch {
                        self.isVoIPRegistrationInFlight = false

                        NSLog(
                            "❌ Backend Voice registration confirmation failed: %@",
                            error.localizedDescription
                        )

                        /*
                         * Twilio registration succeeded, but Chatforia
                         * has not yet recorded this device as authoritative.
                         * Retain the pending token for the existing retry path.
                         */
                        return
                    }

                    /*
                     * Registration is authoritative in both Twilio and
                     * Chatforia. Clear the in-flight flag before checking
                     * for a newer PushKit token so it can register now.
                     */
                    self.isVoIPRegistrationInFlight = false

                    /*
                     * PushKit may have supplied a newer token while this
                     * registration was running. Never clear that newer
                     * token; immediately register it instead.
                     */
                    guard
                        self.pendingVoIPToken == voipToken,
                        self.pendingVoIPTokenData == voipTokenData
                    else {
                        NSLog(
                            "📞 A newer VoIP token arrived; registering it"
                        )
                        self.registerPendingVoIPTokenIfPossible()
                        return
                    }

                    self.pendingVoIPToken = nil
                    self.pendingVoIPTokenData = nil
                }
            }
            } catch let replacementError
                as DeviceReplacementRequiredError {
                isVoIPRegistrationInFlight = false

                NSLog(
                    "ℹ️ VoIP registration waiting for device replacement: %@",
                    replacementError.code
                )
            } catch {
                isVoIPRegistrationInFlight = false

                NSLog(
                    "❌ VoIP registration preparation failed: %@",
                    error.localizedDescription
                )
            }
        }
    }

    private func completeCall(
        outcome: CallEndOutcome,
        reportToCallKit: Bool = true,
        reportToBackend: Bool = true
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

        if reportToBackend,
           let callId = session.backendCallId,
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
            do {
                try twilioVideoService
                    .prepareCallKitVideoAudioSession()

                NSLog(
                    "[VideoAudioTrace] Video audio prepared " +
                    "inside CallKit answer callback"
                )
            } catch {
                NSLog(
                    "[VideoAudioTrace] Video audio preparation failed: %@",
                    error.localizedDescription
                )

                failCall(error.localizedDescription)
                return
            }

            Task {
                await answerIncomingVideoCall()
            }
        } else {
            guard
                let callId =
                    activeSession?.backendCallId,
                let token =
                    TokenStore.shared.read(),
                !token.isEmpty
            else {
                failAnswerClaimLocally()
                return
            }

            Task {
                let result =
                    await patchCallStatus(
                        callId: callId,
                        token: token,
                        status: "ACTIVE",
                        startedAt: now
                    )

                guard
                    activeSession?.id == uuid
                else {
                    return
                }

                switch result {
                case .success:
                    twilioService
                        .acceptIncomingCall()

                case .answeredElsewhere:
                    dismissAnsweredElsewhere()

                case .failed:
                    failAnswerClaimLocally()
                }
            }
        }
    }

    func callKitDidRequestEndCall(uuid: UUID) {
        guard activeSession?.id == uuid else {
            return
        }

        guard let session = activeSession else { return }

        let isUnansweredIncoming =
            session.direction == .incoming &&
            session.answeredAt == nil

        if isUnansweredIncoming {
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

        guard session.status != .ending else {
            return
        }

        pendingEndOutcome = .localHangup

        updateSession {
            $0.status = .ending
        }

        finishLocalHangup(
            session: session,
            reportToCallKit: false
        )
    }

    func callKitDidSetMute(
        uuid: UUID,
        isMuted: Bool
    ) {
        updateSession {
            $0.isMuted = isMuted
        }

        if activeSession?.isVideo == true {
            twilioVideoService.setMuted(isMuted)
        } else {
            twilioService.setMuted(isMuted)
        }
    }

    func callKitDidActivateAudioSession() {
        isCallKitAudioSessionActive = true

        print(
            "✅ CallManager latched CallKit audio active; " +
            "isVideo=\(activeSession?.isVideo == true)"
        )

        if activeSession?.isVideo == true {
            twilioVideoService
                .setCallKitAudioEnabled(true)
        }
    }

    func callKitDidDeactivateAudioSession() {
        isCallKitAudioSessionActive = false

        print(
            "ℹ️ CallManager latched CallKit audio inactive"
        )

        twilioVideoService
            .setCallKitAudioEnabled(false)
    }

    func callKitProviderDidReset() {
        isCallKitAudioSessionActive = false

        print(
            "ℹ️ CallManager reset CallKit audio state"
        )

        twilioVideoService
            .setCallKitAudioEnabled(false)
    }

private func answerIncomingVideoCall() async {
        guard let session = activeSession,
              session.isVideo,
              session.direction == .incoming else {
            return
        }

        let sessionId = session.id

        guard let token = TokenStore.shared.read(),
              !token.isEmpty else {
            failCall(
                appText(
                    "error_missing_auth_token",
                    languageCode: appLanguage
                )
            )
            return
        }

        guard let userId =
                pendingAuth?.currentUser?.id ??
                currentUserId else {
            failCall(
                appText(
                    "calls.missing_current_user",
                    languageCode: appLanguage
                )
            )
            return
        }

        guard let backendCallId = session.backendCallId else {
            failCall(
                appText(
                    "calls.missing_backend_call_id",
                    languageCode: appLanguage
                )
            )
            return
        }

        let suppliedRoomName =
            session.remoteIdentity?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        let roomName =
            suppliedRoomName?.isEmpty == false
                ? suppliedRoomName!
                : "call_\(backendCallId)"

        do {
            try await MediaPermissionManager.shared
                .ensureVideoCallPermissions()

            guard activeSession?.id == sessionId,
                  finalizedCallUUID != sessionId else {
                return
            }

            let claimResult =
                await patchCallStatus(
                    callId: backendCallId,
                    token: token,
                    status: "ACTIVE",
                    startedAt: Date()
                )

            guard activeSession?.id == sessionId,
                  finalizedCallUUID != sessionId else {
                return
            }

            switch claimResult {
            case .success:
                break

            case .answeredElsewhere:
                dismissAnsweredElsewhere()
                return

            case .failed:
                failAnswerClaimLocally()
                return
            }

            try await Task.sleep(
                nanoseconds: 500_000_000
            )

            guard activeSession?.id == sessionId,
                  finalizedCallUUID != sessionId else {
                return
            }

            print(
                "📹 Preparing Twilio Video connection; " +
                "CallKitAudioActive=\(isCallKitAudioSessionActive || callKit.isAudioSessionActive)"
            )

            isCallKitAudioSessionActive =
                isCallKitAudioSessionActive ||
                callKit.isAudioSessionActive

            twilioVideoService.setCallKitAudioEnabled(
                isCallKitAudioSessionActive
            )

            try await twilioVideoService.connect(
                authToken: token,
                identity: String(userId),
                roomName: roomName,
                callUUID: sessionId
            )
        } catch is CancellationError {
            return
        } catch {
            guard activeSession?.id == sessionId,
                  finalizedCallUUID != sessionId else {
                return
            }

            failCall(error.localizedDescription)
        }
    }
}

extension CallManager: TwilioVoiceServiceDelegate {
    func twilioVoiceDidStartConnecting() {
        guard let session = activeSession else { return }

        updateSession {
            $0.status = .connecting
        }

        if session.direction == .outgoing,
           case .appUser = session.destination {
            // The recipient has not answered yet.
            state = .dialing(session.destination)
        } else {
            state = .connecting(session.displayName)
        }
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
        guard let session = activeSession else {
            return
        }

        if session.direction == .outgoing,
           session.isVideo == false,
           case .appUser = session.destination {
            updateSession {
                $0.callSid = callSid
                $0.status = .connecting
            }

            // Keep showing “Calling…” until the recipient
            // actually answers and the backend becomes ACTIVE.
            state = .dialing(
                session.destination
            )

            startOutgoingAudioAnswerWatch(
                session: session
            )

            return
        }

        // Incoming audio was explicitly accepted, and an
        // external phone call is genuinely bridged by this point.
        AudioPlayerService.shared.stopOutgoingRingback()

        let now = Date()

        updateSession {
            $0.callSid = callSid
            $0.status = .active

            if $0.answeredAt == nil {
                $0.answeredAt = now
            }
        }

        if let callId = activeSession?.backendCallId,
           let token = TokenStore.shared.read(),
           !token.isEmpty {
            Task {
                await patchCallStatus(
                    callId: callId,
                    token: token,
                    status: nil,
                    twilioCallSid: callSid
                )
            }
        }

        if session.direction == .outgoing {
            callKit.reportOutgoingCallConnected(
                uuid: session.id
            )
        }

        state = .active(session.displayName)
    }

    func twilioVoiceDidDisconnect() {
        let outcome = pendingEndOutcome ?? .remoteEnded
        completeCall(outcome: outcome)
    }

    func twilioVoiceDidFail(_ message: String) {
        completeCall(outcome: .failed(message))
    }

    func twilioVoiceDidReceiveIncoming(
        from: String,
        backendCallId: Int?,
        completion: @escaping () -> Void
    ) {
        NSLog("📞 Reporting Twilio Voice invitation to CallKit")

        let payload = IncomingCallPayload(
            uuid: UUID(),
            displayName: from,
            remoteIdentity: from,
            hasVideo: false,
            backendCallId: backendCallId
        )

        handleIncomingCallPayload(
            payload,
            auth: pendingAuth
        ) { error in
            if let error {
                NSLog(
                    "❌ CallKit incoming-call report failed: %@",
                    error.localizedDescription
                )
            } else {
                NSLog("✅ CallKit incoming-call report completed")
            }

            completion()
        }
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

        isVideoCameraEnabled =
            twilioVideoService.isCameraEnabled

        localVideoTrack =
            twilioVideoService.currentLocalVideoTrack()

        if session.direction == .incoming {
            // The recipient explicitly accepted through CallKit before
            // joining the room, so media connection completes the answer.
            markVideoCallAnsweredIfNeeded()
            return
        }

        if session.answeredAt == nil {
            // The caller has joined the room locally, but the recipient
            // has not joined yet. Keep this call in Connecting state.
            updateSession {
                $0.status = .connecting
            }

            state = .connecting(session.displayName)
        } else {
            // The remote participant may have joined immediately before
            // this local room-connected callback arrived.
            state = .active(session.displayName)
        }
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

    func twilioVideoRemoteParticipantDidConnect(
        identity: String
    ) {
        remoteParticipantIdentity = identity

        guard activeSession?.direction == .outgoing else {
            return
        }

        markVideoCallAnsweredIfNeeded()
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
