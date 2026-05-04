import SwiftUI
import TwilioVideo

struct VideoCallView: View {
    @EnvironmentObject private var callManager: CallManager
    @EnvironmentObject private var themeManager: ThemeManager

    // MARK: - Remote Tile Model
    private struct RemoteTile: Identifiable, Equatable {
        let id: String
        let displayName: String
        let track: RemoteVideoTrack
    }

    private var remoteTiles: [RemoteTile] {
        callManager.remoteVideoTracks
            .map { identity, track in
                RemoteTile(
                    id: identity,
                    displayName: displayName(for: identity),
                    track: track
                )
            }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private func displayName(for identity: String) -> String {
        let trimmed = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Participant" : trimmed
    }

    // MARK: - Body
    var body: some View {
        let session = callManager.activeSession

        ZStack {
            videoLayout
                .ignoresSafeArea()

            VStack {
                topBar(session: session)
                    .padding(.top, 60)
                    .padding(.horizontal, 16)

                Spacer()

                bottomControls(session: session)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
            }

            localPreview
        }
        .statusBarHidden(true)
    }
}

// MARK: - Layout Switching
private extension VideoCallView {

    @ViewBuilder
    private var videoLayout: some View {
        switch remoteTiles.count {
        case 0:
            waitingLayout
        case 1:
            singleRemoteLayout(remoteTiles[0])
        case 2:
            twoParticipantLayout(remoteTiles)
        case 3, 4:
            gridLayout(remoteTiles, columns: 2)
        default:
            scrollGridLayout(remoteTiles, columns: 2)
        }
    }

    private var waitingLayout: some View {
        ZStack {
            LinearGradient(
                colors: [
                    themeManager.palette.screenBackground,
                    themeManager.palette.cardBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 12) {
                Image(systemName: "video.slash.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(themeManager.palette.secondaryText)

                Text("Waiting for participant…")
                    .font(.headline)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }
        }
    }

    private func singleRemoteLayout(_ tile: RemoteTile) -> some View {
        VideoRendererView(
            mirror: false,
            contentMode: .scaleAspectFill,
            remoteTrack: tile.track
        )
    }

    private func twoParticipantLayout(_ tiles: [RemoteTile]) -> some View {
        HStack(spacing: 2) {
            ForEach(tiles) { tile in
                VideoRendererView(
                    mirror: false,
                    contentMode: .scaleAspectFill,
                    remoteTrack: tile.track
                )
            }
        }
        .background(.black)
    }

    private func gridLayout(_ tiles: [RemoteTile], columns: Int) -> some View {
        let grid = Array(repeating: GridItem(.flexible(), spacing: 2), count: columns)

        return LazyVGrid(columns: grid, spacing: 2) {
            ForEach(tiles) { tile in
                VideoRendererView(
                    mirror: false,
                    contentMode: .scaleAspectFill,
                    remoteTrack: tile.track
                )
                .frame(minHeight: 180)
            }
        }
        .background(.black)
    }

    private func scrollGridLayout(_ tiles: [RemoteTile], columns: Int) -> some View {
        let grid = Array(repeating: GridItem(.flexible(), spacing: 2), count: columns)

        return ScrollView {
            LazyVGrid(columns: grid, spacing: 2) {
                ForEach(tiles) { tile in
                    VideoRendererView(
                        mirror: false,
                        contentMode: .scaleAspectFill,
                        remoteTrack: tile.track
                    )
                    .frame(height: 180)
                }
            }
        }
        .background(.black)
    }
}

// MARK: - Local Preview
private extension VideoCallView {

    var localPreview: some View {
        VStack {
            HStack {
                Spacer()

                Group {
                    if let localTrack = callManager.localVideoTrack,
                       callManager.isVideoCameraEnabled {
                        VideoRendererView(
                            mirror: true,
                            contentMode: .scaleAspectFill,
                            localTrack: localTrack
                        )
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.black.opacity(0.7))

                            VStack(spacing: 8) {
                                Image(systemName: "person.crop.rectangle")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(.white)

                                Text("Camera off")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                        }
                    }
                }
                .frame(width: 122, height: 172)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(radius: 10, y: 4)
            }

            Spacer()
        }
        .padding(.top, 78)
        .padding(.trailing, 16)
    }
}

// MARK: - Top Bar
private extension VideoCallView {

    func topBar(session: CallSession?) -> some View {
        VStack(spacing: 8) {
            Text(session?.displayName ?? "Video Call")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            Text(callManager.state.label)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Bottom Controls
private extension VideoCallView {

    func bottomControls(session: CallSession?) -> some View {
        HStack(spacing: 18) {
            VideoControlButton(
                systemName: (session?.isMuted ?? false) ? "mic.slash.fill" : "mic.fill",
                title: (session?.isMuted ?? false) ? "Unmute" : "Mute",
                isActive: session?.isMuted ?? false
            ) {
                callManager.toggleMute()
            }

            VideoControlButton(
                systemName: callManager.isVideoCameraEnabled ? "video.fill" : "video.slash.fill",
                title: "Camera"
            ) {
                callManager.toggleVideoCamera()
            }

            VideoControlButton(
                systemName: "arrow.triangle.2.circlepath.camera.fill",
                title: "Flip"
            ) {
                callManager.flipVideoCamera()
            }

            VideoControlButton(
                systemName: (session?.isSpeakerOn ?? false) ? "speaker.wave.3.fill" : "speaker.wave.2.fill",
                title: "Speaker",
                isActive: session?.isSpeakerOn ?? false
            ) {
                callManager.toggleSpeaker()
            }

            VideoControlButton(
                systemName: "phone.down.fill",
                title: "End",
                isDestructive: true
            ) {
                callManager.hangup()
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - Button
private struct VideoControlButton: View {
    let systemName: String
    let title: String
    var isActive: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 58, height: 58)
                    .background(backgroundColor)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.95))
        }
        .frame(maxWidth: .infinity)
    }

    private var backgroundColor: Color {
        if isDestructive { return .red }
        if isActive { return .blue }
        return Color.black.opacity(0.72)
    }
}
