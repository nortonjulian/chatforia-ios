import SwiftUI

struct ThemedNavigationTitle: View {
    let title: String

    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"

    var body: some View {
        Text(appText(title, languageCode: appLanguage))
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(themeManager.palette.titleAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .accessibilityAddTraits(.isHeader)
    }
}
