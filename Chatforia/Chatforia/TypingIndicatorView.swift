import SwiftUI
import Combine

struct TypingIndicatorView: View {
    let text: String

    @State private var phase = 0
    private let timer = Timer.publish(every: 0.32, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                dot(0)
                dot(1)
                dot(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(uiColor: .secondarySystemBackground))
            )

            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }

    private func dot(_ index: Int) -> some View {
        Circle()
            .fill(Color.secondary.opacity(opacityForDot(index)))
            .frame(width: 6, height: 6)
            .scaleEffect(scaleForDot(index))
            .animation(.easeInOut(duration: 0.25), value: phase)
    }

    private func opacityForDot(_ index: Int) -> Double {
        phase == index ? 1.0 : 0.35
    }

    private func scaleForDot(_ index: Int) -> CGFloat {
        phase == index ? 1.1 : 0.9
    }
}
