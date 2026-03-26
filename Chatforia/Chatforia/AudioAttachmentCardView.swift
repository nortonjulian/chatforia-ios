import SwiftUI
import AVFoundation

struct AudioAttachmentCardView: View {
    let urlString: String
    let title: String
    let durationSec: Double?
    let isMe: Bool
    let maxWidth: CGFloat
    let onPlaybackStarted: (() -> Void)?

    @EnvironmentObject private var themeManager: ThemeManager
    @StateObject private var playback = AudioPlaybackViewModel()

    init(
        urlString: String,
        title: String,
        durationSec: Double?,
        isMe: Bool,
        maxWidth: CGFloat,
        onPlaybackStarted: (() -> Void)? = nil
    ) {
        self.urlString = urlString
        self.title = title
        self.durationSec = durationSec
        self.isMe = isMe
        self.maxWidth = maxWidth
        self.onPlaybackStarted = onPlaybackStarted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    let wasPlaying = playback.isPlaying
                    playback.togglePlayback(urlString: urlString)

                    if !wasPlaying {
                        onPlaybackStarted?()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(buttonFill)
                            .frame(width: 36, height: 36)

                        if playback.isLoading {
                            ProgressView()
                                .scaleEffect(0.75)
                                .tint(buttonForeground)
                        } else {
                            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(buttonForeground)
                        }
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryText)

                    HStack(spacing: 6) {
                        Text(currentTimeText)
                        Text("•")
                        Text(totalDurationText)
                    }
                    .font(.caption)
                    .foregroundStyle(secondaryText)
                }

                Spacer(minLength: 8)
            }

            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(progressTrack)

                        Capsule()
                            .fill(progressFill)
                            .frame(width: max(6, geo.size.width * playback.progress))
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(stateText)
                        .font(.caption2)
                        .foregroundStyle(secondaryText)

                    Spacer()

                    if playback.isLoading {
                        ProgressView()
                            .scaleEffect(0.75)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onDisappear {
            playback.tearDown()
        }
    }

    private var currentTimeText: String {
        Self.formatTime(playback.currentTime)
    }

    private var totalDurationText: String {
        let resolved = playback.displayDuration(fallback: durationSec)
        return Self.formatTime(resolved)
    }

    private var stateText: String {
        if playback.isLoading {
            return "Loading…"
        }
        return playback.isPlaying ? "Playing" : "Tap to play"
    }

    private var primaryText: Color {
        isMe ? themeManager.palette.bubbleOutgoingText : themeManager.palette.primaryText
    }

    private var secondaryText: Color {
        isMe
            ? themeManager.palette.bubbleOutgoingText.opacity(0.8)
            : themeManager.palette.secondaryText
    }

    private var buttonFill: Color {
        isMe ? themeManager.palette.bubbleOutgoingStart : themeManager.palette.accent
    }

    private var buttonForeground: Color {
        isMe ? themeManager.palette.bubbleOutgoingText : themeManager.palette.composerButtonForeground
    }

    private var cardBackground: Color {
        isMe ? themeManager.palette.bubbleOutgoingStart.opacity(0.18) : themeManager.palette.cardBackground
    }

    private var cardBorder: Color {
        isMe
            ? themeManager.palette.bubbleOutgoingEnd.opacity(0.25)
            : themeManager.palette.border
    }

    private var progressTrack: Color {
        isMe
            ? themeManager.palette.bubbleOutgoingText.opacity(0.18)
            : themeManager.palette.border.opacity(0.7)
    }

    private var progressFill: Color {
        isMe ? themeManager.palette.bubbleOutgoingEnd : themeManager.palette.accent
    }

    static func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let secs = total % 60
        return "\(minutes):" + String(format: "%02d", secs)
    }
}
