import Foundation
import Combine
import CallKit

@MainActor
final class CallManager: ObservableObject {
    @Published var state: CallState = .idle
    @Published var activeSession: CallSession?
    @Published var lastError: String?

    private let pstnService = PSTNCallService.shared
    private let twilioService = TwilioVoiceService.shared
    private let callKit = CallKitManager()
    private let voipPushManager = VoIPPushManager.shared

    private var pendingAuth: AuthStore?
    private var pendingDestination: CallDestination?

    init() {
        twilioService.delegate = self
        callKit.delegate = self
        voipPushManager.delegate = self
    }

    func startVoIPIfNeeded(auth: AuthStore) {
        voipPushManager.start()

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
        lastError = nil
        print("📞 Outgoing call → \(destination.displayName)")

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
            isSpeakerOn: false,
            isVideo: false
        )

        activeSession = session
        pendingAuth = auth
        pendingDestination = destination
        state = .dialing(destination)

        let isPhoneNumber: Bool
        switch destination {
        case .phoneNumber:
            isPhoneNumber = true
        case .appUser:
            isPhoneNumber = false
        }

        callKit.startOutgoingCall(
            uuid: uuid,
            handle: destination.displayName,
            isPhoneNumber: isPhoneNumber
        )
    }

    private func beginIncomingCall(from: String, uuid: UUID) {
        let destination = CallDestination.appUser(userId: 0, username: from)

        activeSession = CallSession(
            id: uuid,
            destination: destination,
            direction: .incoming,
            status: .ringing,
            startedAt: Date(),
            answeredAt: nil,
            endedAt: nil,
            callSid: nil,
            displayName: from,
            remoteIdentity: from,
            chatRoomId: nil,
            backendCallId: nil,
            isMuted: false,
            isSpeakerOn: false,
            isVideo: false
        )

        state = .ringingIncoming(from)
    }

    private func beginPendingOutgoingCall(uuid: UUID) {
        guard let auth = pendingAuth,
              let destination = pendingDestination else {
            failCall("Missing pending call context.")
            return
        }

        Task {
            await startCallAsync(uuid: uuid, to: destination, auth: auth)
        }
    }

    private func startCallAsync(uuid: UUID, to destination: CallDestination, auth: AuthStore) async {
        guard let token = auth.currentToken, !token.isEmpty else {
            failCall("Missing auth token.")
            return
        }

        switch destination {
        case .phoneNumber(let number, let displayName):
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

            do {
                let callId = try await CallService.shared.createCall(
                    calleeId: userId,
                    mode: "AUDIO",
                    token: token
                )

                updateSession {
                    $0.backendCallId = callId
                }

                print("✅ Backend call created:", callId)
            } catch {
                print("❌ Failed to create backend call:", error)
            }

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
            twilioService.setSpeaker($0.isSpeakerOn)
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
        print("📞 Missed call")

        let now = Date()

        if let callId = activeSession?.backendCallId,
           let token = TokenStore.shared.read(),
           !token.isEmpty {
            Task {
                await patchCallStatus(
                    callId: callId,
                    token: token,
                    status: "MISSED",
                    endedAt: now,
                    endReason: "missed"
                )
            }
        }

        updateSession {
            $0.status = .missed
            $0.endedAt = now
        }

        state = .ended
        activeSession = nil
        pendingAuth = nil
        pendingDestination = nil
    }

    private func failCall(_ message: String) {
        lastError = message

        let now = Date()

        updateSession {
            $0.status = .failed
            $0.endedAt = now
        }

        if let uuid = activeSession?.id {
            callKit.reportCallEnded(uuid: uuid, reason: .failed)
        }

        if let callId = activeSession?.backendCallId,
           let token = TokenStore.shared.read(),
           !token.isEmpty {
            Task {
                await patchCallStatus(
                    callId: callId,
                    token: token,
                    status: "FAILED",
                    endedAt: now,
                    endReason: message
                )
            }
        }

        state = .failed(message)
        activeSession = nil
        pendingAuth = nil
        pendingDestination = nil
    }

    private func finishCall(reason: CXCallEndedReason = .remoteEnded) {
        let now = Date()

        if let uuid = activeSession?.id {
            callKit.reportCallEnded(uuid: uuid, reason: reason)
        }

        updateSession {
            $0.status = .ended
            $0.endedAt = now
        }

        if let callId = activeSession?.backendCallId,
           let token = TokenStore.shared.read(),
           !token.isEmpty {
            let duration: Int? = {
                guard let start = activeSession?.answeredAt else { return nil }
                return max(0, Int(now.timeIntervalSince(start)))
            }()

            Task {
                await patchCallStatus(
                    callId: callId,
                    token: token,
                    status: "ENDED",
                    endedAt: now,
                    durationSec: duration,
                    endReason: "completed",
                    twilioCallSid: activeSession?.callSid
                )
            }
        }

        print("📞 Call ended")

        state = .ended
        activeSession = nil
        pendingAuth = nil
        pendingDestination = nil
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

    func callKitDidRequestEndCall(uuid: UUID) {
        guard activeSession?.id == uuid else {
            print("⚠️ CallKit end UUID mismatch")
            return
        }

        if activeSession?.direction == .incoming,
           activeSession?.status == .ringing {
            twilioService.rejectIncomingCall()

            if let callId = activeSession?.backendCallId,
               let token = TokenStore.shared.read(),
               !token.isEmpty {
                Task {
                    await patchCallStatus(
                        callId: callId,
                        token: token,
                        status: "DECLINED",
                        endedAt: Date(),
                        endReason: "declined"
                    )
                }
            }

            finishCall(reason: .declinedElsewhere)
            return
        }

        twilioService.hangup()

        updateSession {
            $0.status = .ending
        }
    }

    func callKitDidSetMute(uuid: UUID, isMuted: Bool) {
        updateSession { $0.isMuted = isMuted }
        twilioService.setMuted(isMuted)
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

        print("📞 Call connected")

        callKit.reportOutgoingCallConnected(uuid: session.id)
        state = .active(session.displayName)
    }

    func twilioVoiceDidDisconnect() {
        finishCall(reason: .remoteEnded)
    }

    func twilioVoiceDidFail(_ message: String) {
        failCall(message)
    }

    func twilioVoiceDidReceiveIncoming(from: String) {
        if activeSession?.status == .ringing {
            return
        }

        print("📞 Incoming call from \(from)")

        let uuid = UUID()
        beginIncomingCall(from: from, uuid: uuid)

        callKit.reportIncomingCall(uuid: uuid, handle: from) { error in
            if let error {
                print("❌ Failed to report incoming CallKit call:", error)
                self.failCall(error.localizedDescription)
            }
        }
    }

    func twilioVoiceIncomingInviteCanceled() {
        if activeSession?.status == .ringing {
            markMissedCall()
        } else {
            finishCall(reason: .remoteEnded)
        }
    }
}

extension CallManager: VoIPPushManagerDelegate {
    func voipPushManagerDidUpdateToken(_ token: String) {
        guard let authToken = TokenStore.shared.read(), !authToken.isEmpty else { return }

        Task {
            do {
                try await DeviceRegistrationService.shared.registerVoIPPushToken(token, token: authToken)
                print("✅ VoIP push token registered")
            } catch {
                print("❌ VoIP push token registration failed:", error)
            }
        }
    }

    func voipPushManagerDidInvalidateToken() {
        print("ℹ️ VoIP push token invalidated")
    }
}
