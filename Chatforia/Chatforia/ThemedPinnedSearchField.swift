import SwiftUI

/// Shared search styling for the Chats and Contacts tab headers.
struct ThemedPinnedSearchField: View {
    @Binding var text: String
    let placeholder: String
    let clearAccessibilityLabel: String

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(themeManager.searchHintText)
                .accessibilityHidden(true)

            TextField(
                placeholder,
                text: $text,
                prompt: Text(placeholder)
                    .foregroundColor(themeManager.searchHintText)
            )
            .foregroundStyle(themeManager.palette.primaryText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .accessibilityLabel(placeholder)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(themeManager.searchHintText)
                }
                .accessibilityLabel(clearAccessibilityLabel)
            }
        }
        .font(.body)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(themeManager.palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// Keeps system-rendered navigation text legible on the selected app surface.
struct ThemedNavigationBar: ViewModifier {
    @EnvironmentObject private var themeManager: ThemeManager

    func body(content: Content) -> some View {
        content
            .toolbarBackground(themeManager.palette.screenBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(themeManager.navigationColorScheme, for: .navigationBar)
    }
}
