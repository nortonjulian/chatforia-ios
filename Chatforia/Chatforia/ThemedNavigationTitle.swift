import SwiftUI

struct ThemedNavigationTitle: View {
    let title: String

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        Text(title)
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(themeManager.palette.titleAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .accessibilityAddTraits(.isHeader)
    }
}
