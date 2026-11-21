import SwiftUI
import UIKit

struct ThemedTextField: View {
    let title: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil

    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"

    var body: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(appText(title, languageCode: appLanguage))
                .foregroundColor(themeManager.cardSecondaryText)
        )
        .keyboardType(keyboard)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .textContentType(contentType)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(themeManager.palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(themeManager.palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(themeManager.palette.primaryText)
        .tint(themeManager.cardActionText)
        .accessibilityLabel(appText(title, languageCode: appLanguage))
    }
}
