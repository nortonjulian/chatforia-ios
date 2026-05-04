import SwiftUI

struct ThemedToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(themeManager.palette.primaryText)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(themeManager.palette.secondaryText)
                }
            }

            Spacer(minLength: 12)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(themeManager.palette.accent)
        }
        .padding(.vertical, 4)
    }
}
