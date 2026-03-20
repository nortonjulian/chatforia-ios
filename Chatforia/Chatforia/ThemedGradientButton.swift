import SwiftUI

struct ThemedGradientButton: View {
    let title: String
    let action: () -> Void
    var horizontalPadding: CGFloat = 18
    var verticalPadding: CGFloat = 10
    var font: Font = .subheadline.weight(.semibold)

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .foregroundStyle(themeManager.palette.buttonForeground)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(
                    LinearGradient(
                        colors: [
                            themeManager.palette.buttonStart,
                            themeManager.palette.buttonEnd
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: themeManager.palette.buttonEnd.opacity(0.28), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}
