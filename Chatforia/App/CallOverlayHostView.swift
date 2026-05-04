import SwiftUI

struct CallOverlayHostView: View {
    @EnvironmentObject private var callManager: CallManager

    var body: some View {
        Group {
            if callManager.state.isInCallFlow || callManager.activeSession != nil {
                if let session = callManager.activeSession {
                    if session.isVideo {
                        VideoCallView()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(999)
                    } else {
                        ActiveCallView()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(999)
                    }
                } else {
                    ActiveCallView()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(999)
                }
            } else if case .failed(let message) = callManager.state {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 24)
                        .onTapGesture {
                            callManager.dismissEndedState()
                        }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: callManager.state.label)
    }
}
