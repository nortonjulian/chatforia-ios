import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var buttonTitle: String? = nil
    var buttonAction: (() -> Void)? = nil

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(themeManager.palette.secondaryText)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(themeManager.palette.primaryText)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .multilineTextAlignment(.center)
            }

            if let buttonTitle, let buttonAction {
                ThemedGradientButton(
                    title: buttonTitle,
                    action: buttonAction
                )
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: 360)
        .padding(24)
    }
}
