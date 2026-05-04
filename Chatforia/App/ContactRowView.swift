import SwiftUI

struct ContactRowView: View {
    let title: String
    let subtitle: String
    let favorite: Bool

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(themeManager.palette.border)
                    .frame(width: 44, height: 44)

                Text(String(title.prefix(1)).uppercased())
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(themeManager.palette.primaryText)

                    if favorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(themeManager.palette.accent)
                    }
                }

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}
