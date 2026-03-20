import SwiftUI

struct ThemedGradientButton: View {
    let title: String
    let action: () -> Void
    var isFullWidth: Bool = false
    var horizontalPadding: CGFloat = 18
    var verticalPadding: CGFloat = 14
    var font: Font = .headline.weight(.semibold)
    var isDisabled: Bool = false

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .foregroundStyle(themeManager.palette.buttonForeground.opacity(isDisabled ? 0.7 : 1))
                .frame(maxWidth: isFullWidth ? .infinity : nil)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(
                    LinearGradient(
                        colors: [
                            themeManager.palette.buttonStart.opacity(isDisabled ? 0.6 : 1),
                            themeManager.palette.buttonEnd.opacity(isDisabled ? 0.6 : 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(
                    color: themeManager.palette.buttonEnd.opacity(isDisabled ? 0.10 : 0.28),
                    radius: 10,
                    x: 0,
                    y: 4
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
