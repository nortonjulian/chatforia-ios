import SwiftUI

struct LoadingStateView: View {
    let title: String
    var subtitle: String? = nil

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(themeManager.palette.accent)

            Text(title)
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }
}
