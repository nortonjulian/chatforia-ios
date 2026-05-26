import SwiftUI

struct DateSeparatorView: View {
    let date: Date

    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"

    var body: some View {
        HStack {
            Spacer()

            Text(labelText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(themeManager.palette.secondaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(themeManager.palette.cardBackground.opacity(0.95))
                .overlay(
                    Capsule()
                        .stroke(themeManager.palette.border.opacity(0.8), lineWidth: 1)
                )
                .clipShape(Capsule())

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(labelText)
    }

    private var labelText: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return appText(
                "common.today",
                languageCode: appLanguage
            )
        }

        if calendar.isDateInYesterday(date) {
            return appText(
                "common.yesterday",
                languageCode: appLanguage
            )
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
