import SwiftUI

struct SettingsRowView: View {
    let systemImage: String
    let title: String
    let value: String

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(themeManager.palette.accent)
                .frame(width: 22)

            Text(title)
                .font(.body)
                .foregroundStyle(themeManager.palette.primaryText)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}
