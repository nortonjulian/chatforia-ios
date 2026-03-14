import SwiftUI

struct LoadingStateView: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()

            Text(title)
                .font(.headline)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }
}
