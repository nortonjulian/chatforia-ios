import SwiftUI
import AVKit

struct FullscreenVideoView: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isDraggingDown = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onTapGesture {
                        // toggle controls handled automatically by VideoPlayer
                    }
            }

            VStack {
                HStack {
                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding()

                Spacer()
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 50 {
                        isDraggingDown = true
                    }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        dismiss()
                    }
                    isDraggingDown = false
                }
        )
        .onAppear {
            let p = AVPlayer(url: url)
            p.play()
            player = p
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
