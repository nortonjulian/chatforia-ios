import Foundation
import AVFoundation
import TwilioVideo

@MainActor
protocol TwilioVideoServiceDelegate: AnyObject {
    func twilioVideoDidStartConnecting(roomName: String)
    func twilioVideoDidConnect(roomName: String)
    func twilioVideoDidDisconnect(roomName: String?)
    func twilioVideoDidFail(_ message: String)

    func twilioVideoDidAddLocalVideoTrack(_ track: LocalVideoTrack)
    func twilioVideoDidRemoveLocalVideoTrack()

    func twilioVideoRemoteParticipantDidConnect(identity: String)
    func twilioVideoRemoteParticipantDidDisconnect(identity: String)

    func twilioVideoDidSubscribeToRemoteVideoTrack(_ track: RemoteVideoTrack, participantIdentity: String)
    func twilioVideoDidUnsubscribeFromRemoteVideoTrack(participantIdentity: String)

    func twilioVideoDidSubscribeToRemoteAudioTrack(participantIdentity: String)
    func twilioVideoDidUnsubscribeFromRemoteAudioTrack(participantIdentity: String)
}

@MainActor
final class TwilioVideoService: NSObject {
    static let shared = TwilioVideoService()

    weak var delegate: TwilioVideoServiceDelegate?

    private(set) var room: Room?
    private(set) var roomName: String?

    private var cameraSource: CameraSource?
    private var localVideoTrack: LocalVideoTrack?
    private var localAudioTrack: LocalAudioTrack?
    private var remoteVideoTracks: [String: RemoteVideoTrack] = [:]

    private(set) var isMuted = false
    private(set) var isCameraEnabled = true
    private(set) var isFrontCamera = true

    private override init() {
        super.init()
    }

    // MARK: - Token

    struct VideoTokenResponseDTO: Decodable {
        let token: String
    }

    func fetchVideoToken(
        authToken: String?,
        identity: String,
        room: String
    ) async throws -> String {
        struct Body: Encodable {
            let identity: String
            let room: String
        }

        let body = try JSONEncoder().encode(
            Body(identity: identity, room: room)
        )

        let response: VideoTokenResponseDTO = try await APIClient.shared.send(
            APIRequest(
                path: "video/token",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: authToken
        )

        return response.token
    }

    // MARK: - Connect / Disconnect

    func connect(
        authToken: String?,
        identity: String,
        roomName: String
    ) async throws {
        try await configureAudioSession()

        let token = try await fetchVideoToken(
            authToken: authToken,
            identity: identity,
            room: roomName
        )

        try createLocalTracks()

        self.roomName = roomName
        delegate?.twilioVideoDidStartConnecting(roomName: roomName)

        let connectOptions = ConnectOptions(token: token) { [weak self] builder in
            guard let self else { return }

            builder.roomName = roomName

            if let localAudioTrack {
                builder.audioTracks = [localAudioTrack]
            }

            if let localVideoTrack {
                builder.videoTracks = [localVideoTrack]
            }
        }

        room = TwilioVideoSDK.connect(options: connectOptions, delegate: self)
    }

    func disconnect() {
        room?.disconnect()
        cleanupAfterDisconnect(notifyDelegate: false)
        delegate?.twilioVideoDidDisconnect(roomName: roomName)
    }

    // MARK: - Controls

    func setMuted(_ muted: Bool) {
        isMuted = muted
        localAudioTrack?.isEnabled = !muted
    }

    func setCameraEnabled(_ enabled: Bool) {
        isCameraEnabled = enabled
        localVideoTrack?.isEnabled = enabled
    }

    func flipCamera() {
        guard let cameraSource else { return }

        let newPosition: AVCaptureDevice.Position = isFrontCamera ? .back : .front

        guard let device = CameraSource.captureDevice(position: newPosition) else {
            delegate?.twilioVideoDidFail("No camera available.")
            return
        }

        cameraSource.selectCaptureDevice(device) { [weak self] _, _, error in
            Task { @MainActor [weak self] in
                guard let service = self else { return }

                if let error {
                    service.delegate?.twilioVideoDidFail(error.localizedDescription)
                    return
                }

                service.isFrontCamera.toggle()
            }
        }
    }

    // MARK: - Local Track Access

    func currentLocalVideoTrack() -> LocalVideoTrack? {
        localVideoTrack
    }

    func remoteVideoTrack(for participantIdentity: String) -> RemoteVideoTrack? {
        remoteVideoTracks[participantIdentity]
    }

    // MARK: - Setup

    private func createLocalTracks() throws {
        localAudioTrack = LocalAudioTrack(options: nil, enabled: true, name: "microphone")

        let options = CameraSourceOptions { builder in
            builder.rotationTags = .keep
        }

        guard let cameraSource = CameraSource(options: options, delegate: self) else {
            throw NSError(
                domain: "TwilioVideoService",
                code: 1000,
                userInfo: [NSLocalizedDescriptionKey: "Could not create camera source."]
            )
        }

        self.cameraSource = cameraSource

        guard let device =
            CameraSource.captureDevice(position: .front) ??
            CameraSource.captureDevice(position: .back) else {
            throw NSError(
                domain: "TwilioVideoService",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "No camera available."]
            )
        }

        isFrontCamera = (device.position == .front)

        localVideoTrack = LocalVideoTrack(
            source: cameraSource,
            enabled: true,
            name: "camera"
        )

        cameraSource.startCapture(device: device) { [weak self] _, _, error in
            Task { @MainActor [weak self] in
                guard let service = self else { return }

                if let error {
                    service.delegate?.twilioVideoDidFail(error.localizedDescription)
                    return
                }

                if let track = service.localVideoTrack {
                    service.delegate?.twilioVideoDidAddLocalVideoTrack(track)
                }
            }
        }
    }

    private func configureAudioSession() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .videoChat,
            options: [.allowBluetoothHFP, .defaultToSpeaker]
        )
        try session.setActive(true)
    }

    private func cleanupAfterDisconnect(notifyDelegate: Bool) {
        room = nil

        remoteVideoTracks.removeAll()

        if notifyDelegate {
            delegate?.twilioVideoDidRemoveLocalVideoTrack()
        }

        cameraSource?.stopCapture()
        cameraSource = nil
        localVideoTrack = nil
        localAudioTrack = nil

        isMuted = false
        isCameraEnabled = true
        isFrontCamera = true
    }
}

// MARK: - RoomDelegate

extension TwilioVideoService: RoomDelegate {
    nonisolated func roomDidConnect(room: Room) {
        Task { @MainActor in
            self.room = room
            self.delegate?.twilioVideoDidConnect(roomName: room.name)

            for participant in room.remoteParticipants {
                self.delegate?.twilioVideoRemoteParticipantDidConnect(identity: participant.identity)
                participant.delegate = self
            }
        }
    }

    nonisolated func roomDidDisconnect(room: Room, error: Error?) {
        Task { @MainActor in
            let disconnectedRoomName = self.roomName

            self.cleanupAfterDisconnect(notifyDelegate: true)

            if let error {
                self.delegate?.twilioVideoDidFail(error.localizedDescription)
            } else {
                self.delegate?.twilioVideoDidDisconnect(roomName: disconnectedRoomName)
            }

            self.roomName = nil
        }
    }

    nonisolated func roomDidFailToConnect(room: Room, error: Error) {
        Task { @MainActor in
            self.cleanupAfterDisconnect(notifyDelegate: true)
            self.roomName = nil
            self.delegate?.twilioVideoDidFail(error.localizedDescription)
        }
    }

    nonisolated func participantDidConnect(room: Room, participant: RemoteParticipant) {
        participant.delegate = self

        Task { @MainActor in
            self.delegate?.twilioVideoRemoteParticipantDidConnect(identity: participant.identity)
        }
    }

    nonisolated func participantDidDisconnect(room: Room, participant: RemoteParticipant) {
        Task { @MainActor in
            self.remoteVideoTracks.removeValue(forKey: participant.identity)
            self.delegate?.twilioVideoDidUnsubscribeFromRemoteVideoTrack(participantIdentity: participant.identity)
            self.delegate?.twilioVideoRemoteParticipantDidDisconnect(identity: participant.identity)
        }
    }

    nonisolated func recordingStarted(room: Room) {}
    nonisolated func recordingStopped(room: Room) {}
    nonisolated func dominantSpeakerDidChange(room: Room, dominantSpeaker: RemoteParticipant?) {}
}

// MARK: - RemoteParticipantDelegate

extension TwilioVideoService: RemoteParticipantDelegate {
    nonisolated func remoteParticipantDidPublishVideoTrack(
        participant: RemoteParticipant,
        publication: RemoteVideoTrackPublication
    ) {}

    nonisolated func remoteParticipantDidUnpublishVideoTrack(
        participant: RemoteParticipant,
        publication: RemoteVideoTrackPublication
    ) {}

    nonisolated func remoteParticipantDidPublishAudioTrack(
        participant: RemoteParticipant,
        publication: RemoteAudioTrackPublication
    ) {}

    nonisolated func remoteParticipantDidUnpublishAudioTrack(
        participant: RemoteParticipant,
        publication: RemoteAudioTrackPublication
    ) {}

    nonisolated func remoteParticipantDidEnableVideoTrack(
        participant: RemoteParticipant,
        publication: RemoteVideoTrackPublication
    ) {}

    nonisolated func remoteParticipantDidDisableVideoTrack(
        participant: RemoteParticipant,
        publication: RemoteVideoTrackPublication
    ) {}

    nonisolated func remoteParticipantDidEnableAudioTrack(
        participant: RemoteParticipant,
        publication: RemoteAudioTrackPublication
    ) {}

    nonisolated func remoteParticipantDidDisableAudioTrack(
        participant: RemoteParticipant,
        publication: RemoteAudioTrackPublication
    ) {}

    nonisolated func didSubscribeToVideoTrack(
        videoTrack: RemoteVideoTrack,
        publication: RemoteVideoTrackPublication,
        participant: RemoteParticipant
    ) {
        Task { @MainActor in
            self.remoteVideoTracks[participant.identity] = videoTrack
            self.delegate?.twilioVideoDidSubscribeToRemoteVideoTrack(
                videoTrack,
                participantIdentity: participant.identity
            )
        }
    }

    nonisolated func didUnsubscribeFromVideoTrack(
        videoTrack: RemoteVideoTrack,
        publication: RemoteVideoTrackPublication,
        participant: RemoteParticipant
    ) {
        Task { @MainActor in
            self.remoteVideoTracks.removeValue(forKey: participant.identity)
            self.delegate?.twilioVideoDidUnsubscribeFromRemoteVideoTrack(
                participantIdentity: participant.identity
            )
        }
    }

    nonisolated func didSubscribeToAudioTrack(
        audioTrack: RemoteAudioTrack,
        publication: RemoteAudioTrackPublication,
        participant: RemoteParticipant
    ) {
        Task { @MainActor in
            self.delegate?.twilioVideoDidSubscribeToRemoteAudioTrack(
                participantIdentity: participant.identity
            )
        }
    }

    nonisolated func didUnsubscribeFromAudioTrack(
        audioTrack: RemoteAudioTrack,
        publication: RemoteAudioTrackPublication,
        participant: RemoteParticipant
    ) {
        Task { @MainActor in
            self.delegate?.twilioVideoDidUnsubscribeFromRemoteAudioTrack(
                participantIdentity: participant.identity
            )
        }
    }

    nonisolated func didFailToSubscribeToVideoTrack(
        publication: RemoteVideoTrackPublication,
        error: Error,
        participant: RemoteParticipant
    ) {
        Task { @MainActor in
            self.delegate?.twilioVideoDidFail(error.localizedDescription)
        }
    }

    nonisolated func didFailToSubscribeToAudioTrack(
        publication: RemoteAudioTrackPublication,
        error: Error,
        participant: RemoteParticipant
    ) {
        Task { @MainActor in
            self.delegate?.twilioVideoDidFail(error.localizedDescription)
        }
    }
}

// MARK: - CameraSourceDelegate

extension TwilioVideoService: CameraSourceDelegate {
    nonisolated func cameraSourceDidFail(source: CameraSource, error: Error) {
        Task { @MainActor in
            self.delegate?.twilioVideoDidFail(error.localizedDescription)
        }
    }
}
