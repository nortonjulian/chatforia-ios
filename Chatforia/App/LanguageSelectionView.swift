import SwiftUI

struct LanguageSelectionView: View {
    @Binding var selectedLanguage: String
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preferred Language")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.palette.primaryText)

            Picker("Preferred Language", selection: $selectedLanguage) {
                ForEach(AppLanguages.all) { language in
                    Text(language.name).tag(language.code)
                }
            }
            .pickerStyle(.menu)
            .tint(themeManager.palette.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(themeManager.palette.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(themeManager.palette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }
}
