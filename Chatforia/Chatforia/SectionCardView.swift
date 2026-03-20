import SwiftUI

struct SectionCardView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    @EnvironmentObject private var themeManager: ThemeManager

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(themeManager.palette.secondaryText)
                .tracking(0.8)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    themeManager.palette.cardBackground

                    // 🔥 subtle theme glow overlay (feels more like web)
                    LinearGradient(
                        colors: [
                            themeManager.palette.accent.opacity(0.06),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(themeManager.palette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(
                color: themeManager.palette.accent.opacity(0.08),
                radius: 8,
                x: 0,
                y: 4
            )
        }
    }
}
