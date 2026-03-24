import SwiftUI

struct ActiveCallView: View {
    @EnvironmentObject private var callManager: CallManager
    @EnvironmentObject private var themeManager: ThemeManager

    private var stateLabel: String {
        callManager.state.label
    }

    var body: some View {
        let session = callManager.activeSession

        ZStack {
            LinearGradient(
                colors: [
                    themeManager.palette.screenBackground,
                    themeManager.palette.cardBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 10) {
                    Text(session?.displayName ?? "Call")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(themeManager.palette.primaryText)
                        .multilineTextAlignment(.center)

                    Text(stateLabel)
                        .font(.headline)
                        .foregroundStyle(themeManager.palette.secondaryText)
                }

                Spacer()

                HStack(spacing: 26) {
                    CallControlButton(
                        systemName: (session?.isMuted ?? false) ? "mic.slash.fill" : "mic.fill",
                        title: (session?.isMuted ?? false) ? "Unmute" : "Mute",
                        isActive: session?.isMuted ?? false
                    ) {
                        callManager.toggleMute()
                    }

                    CallControlButton(
                        systemName: (session?.isSpeakerOn ?? false) ? "speaker.wave.3.fill" : "speaker.wave.2.fill",
                        title: "Speaker",
                        isActive: session?.isSpeakerOn ?? false
                    ) {
                        callManager.toggleSpeaker()
                    }

                    CallControlButton(
                        systemName: "phone.down.fill",
                        title: "End",
                        isDestructive: true
                    ) {
                        callManager.hangup()
                    }
                }
                .padding(.bottom, 46)
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct CallControlButton: View {
    let systemName: String
    let title: String
    var isActive: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 68, height: 68)
                    .background(backgroundColor)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }

            Text(title)
                .font(.footnote)
                .foregroundStyle(.primary)
        }
    }

    private var backgroundColor: Color {
        if isDestructive { return .red }
        if isActive { return .blue }
        return Color.black.opacity(0.72)
    }
}
