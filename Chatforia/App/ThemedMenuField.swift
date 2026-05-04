import SwiftUI

struct ThemedMenuField: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let action: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.palette.primaryText)

            Button(action: action) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(value)
                            .font(.body.weight(.medium))
                            .foregroundStyle(themeManager.palette.primaryText)

                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(themeManager.palette.secondaryText)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(themeManager.palette.secondaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(themeManager.palette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(themeManager.palette.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}
