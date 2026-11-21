import SwiftUI

struct UnreadBadgeView: View {
    let count: Int

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(themeManager.gradientForeground(for: .button))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    ThemedGradientFill(role: .button, startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(Capsule())
        }
    }
}
