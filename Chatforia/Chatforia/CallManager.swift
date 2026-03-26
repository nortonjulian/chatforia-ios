import Foundation
import Combine
import CallKit
import TwilioVideo
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

    init() {
        twilioService.delegate = self
        twilioVideoService.delegate = self
        callKit.delegate = self
        voipPushManager.delegate = self
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
        voipPushManager.start()
        registerPendingVoIPTokenIfPossible()

        if let token = auth.currentToken, !token.isEmpty {
            Task {
                do {
                    try await twilioService.prepare(authToken: token)
                    print("✅ Twilio Voice prepared")
                } catch {
                    print("❌ Failed to prepare Twilio voice:", error)
                }
            }
        }
    }

    func startCall(to destination: CallDestination, auth: AuthStore) {
        beginOutgoingCall(to: destination, auth: auth, isVideo: false)
    }

    func startVideoCall(to destination: CallDestination, auth: AuthStore) {
        switch destination {
        case .phoneNumber:
            failCall("Video calling is only available for app users right now.")
        case .appUser, .videoRoom:
            beginOutgoingCall(to: destination, auth: auth, isVideo: true)
        }
    }

    func startGroupVideoCall(roomId: Int, displayName: String?, auth: AuthStore) {
        beginOutgoingCall(
            to: .videoRoom(
                roomId: roomId,
                roomName: "chatroom_\(roomId)",
                displayName: displayName
            ),
            auth: auth,
            isVideo: true
        )
    }

    func handleIncomingCallPayload(_ payload: IncomingCallPayload, auth: AuthStore?) {
        if activeSession?.status == .ringing || activeSession?.status == .active || activeSession?.status == .connecting {
            return
        }

        pendingAuth = auth
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
                print("❌ Failed to report incoming CallKit call:", error)
                self.failCall(error.localizedDescription)
            }
        }
    }

    private func clearPublishedVideoState() {
        localVideoTrack = nil
        remoteVideoTracks = [:]
        remoteParticipantIdentity = nil
        isVideoCameraEnabled = true
    }

    private func beginOutgoingCall(to destination: CallDestination, auth: AuthStore, isVideo: Bool) {
        lastError = nil
        pendingAuth = auth
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

        let isPhoneNumber: Bool
        switch destination {
        case .phoneNumber:
            isPhoneNumber = true
        case .appUser:
            isPhoneNumber = false
        case .videoRoom:
            isPhoneNumber = false
        }

        callKit.startOutgoingCall(
            uuid: uuid,
            handle: destination.displayName,
            isPhoneNumber: isPhoneNumber
        )
    }

    private func beginPendingOutgoingCall(uuid: UUID) {
        guard let auth = pendingAuth,
              let destination = pendingDestination else {
            failCall("Missing pending call context.")
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
            failCall("Missing auth token.")
            return
        }

        switch destination {
        case .phoneNumber(let number, let displayName):
            if isVideo {
                failCall("Video calling is only available for app users right now.")
                return
            }

            updateSession {
                $0.status = .ringing
                $0.displayName = displayName ?? number
            }
            state = .dialing(destination)

            do {
                let result = try await pstnService.startCall(to: number, token: token)

                updateSession {
                    $0.callSid = result.callSid
                    $0.status = .connecting
                }

                state = .connecting(displayName ?? number)
            } catch {
                failCall(error.localizedDescription)
            }

        case .appUser(let userId, let username):
            updateSession {
                $0.status = .connecting
                $0.displayName = username ?? "Call"
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

            do {
                let callId = try await CallService.shared.createCall(
                    calleeId: userId,
                    mode: isVideo ? "VIDEO" : "AUDIO",
                    token: token
                )

                updateSession {
                    $0.backendCallId = callId
                }

                print("✅ Backend call created:", callId)
            } catch {
                print("❌ Failed to create backend call:", error)
                failCall(error.localizedDescription)
                return
            }

            if isVideo {
                guard let currentUser = auth.currentUser else {
                    failCall("Missing current user.")
                    return
                }

                guard let backendCallId = activeSession?.backendCallId else {
                    failCall("Missing backend call ID.")
                    return
                }

                let roomName = "call_\(backendCallId)"
                state = .connecting(username ?? "Call")

                do {
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
                    state = .connecting(username ?? "Call")

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
                failCall("Room calling only supports video right now.")
                return
            }

            updateSession {
                $0.status = .connecting
                $0.displayName = displayName ?? "Group Video"
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
                failCall("Missing current user.")
                return
            }

            do {
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

    func toggleMute() {
        guard let session = activeSession else { return }
        let newMuted = !session.isMuted
        callKit.setMuted(uuid: session.id, muted: newMuted)
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
            state = .failed("Could not change audio output.")
        }
    }

    func hangup() {
        guard let session = activeSession else { return }
        callKit.endCall(uuid: session.id)
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
            print("❌ Failed to patch call status:", error)
        }
    }

    private func markMissedCall() {
        completeCall(outcome: .missed)
    }

    private func failCall(_ message: String) {
        completeCall(outcome: .failed(message))
    }

    private func finishCall(reason: CXCallEndedReason = .remoteEnded) {
        switch reason {
        case .declinedElsewhere:
            completeCall(outcome: .declined)
        case .unanswered:
            completeCall(outcome: .missed)
        case .failed:
            completeCall(outcome: .failed("Call failed."))
        default:
            completeCall(outcome: .remoteEnded)
        }
    }

    private func resetTransientState() {
        pendingAuth = nil
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
            print("⚠️ Failed to deactivate audio session:", error)
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
              let authToken = TokenStore.shared.read(),
              !authToken.isEmpty else { return }

        Task {
            do {
                try await DeviceRegistrationService.shared.registerVoIPPushToken(voipToken, token: authToken)
                print("✅ VoIP push token registered")
                await MainActor.run {
                    self.pendingVoIPToken = nil
                }
            } catch {
                print("❌ VoIP push token registration failed:", error)
            }
        }
    }

    private func completeCall(
        outcome: CallEndOutcome,
        reportToCallKit: Bool = true
    ) {
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

        clearPublishedVideoState()
        deactivateSystemAudioSessionIfPossible()

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
            }
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
    }
}

extension CallManager: CallKitManagerDelegate {
    func callKitDidRequestStartCall(uuid: UUID, handle: String) {
        guard activeSession?.id == uuid else {
            print("⚠️ UUID mismatch — ignoring start call")
            return
        }

        callKit.reportOutgoingCallConnecting(uuid: uuid)
        beginPendingOutgoingCall(uuid: uuid)
    }

    func callKitDidRequestAnswerCall(uuid: UUID) {
        guard activeSession?.id == uuid else {
            print("⚠️ CallKit answer UUID mismatch")
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
            print("⚠️ CallKit end UUID mismatch")
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
            failCall("Missing auth token.")
            return
        }

        guard let currentUser = pendingAuth?.currentUser else {
            failCall("Missing current user.")
            return
        }

        guard let backendCallId = activeSession?.backendCallId else {
            failCall("Missing backend call ID.")
            return
        }

        do {
            try await MediaPermissionManager.shared.ensureVideoCallPermissions()
            try await CallService.shared.answerCall(callId: backendCallId, token: token)

            await patchCallStatus(
                callId: backendCallId,
                token: token,
                status: "ACTIVE",
                startedAt: Date()
            )

            try await twilioVideoService.connect(
                authToken: token,
                identity: String(currentUser.id),
                roomName: "call_\(backendCallId)"
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

    func twilioVoiceDidConnect(callSid: String?) {
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
    func voipPushManagerDidUpdateToken(_ token: String) {
        pendingVoIPToken = token
        registerPendingVoIPTokenIfPossible()
    }

    func voipPushManagerDidInvalidateToken() {
        print("ℹ️ VoIP push token invalidated")
    }
}
