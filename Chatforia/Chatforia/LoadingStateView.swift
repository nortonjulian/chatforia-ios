import SwiftUI

// Keep list content aligned immediately below each screen's pinned controls.
// This changes scroll content inset only; safe areas and row spacing remain native.
extension View {
    func chatforiaTopAlignedList() -> some View {
        contentMargins(.top, 0, for: .scrollContent)
    }
}

struct CompactLoadingStateView: View {
    let title: String
    var subtitle: String? = nil

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .tint(themeManager.palette.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(themeManager.palette.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

struct LoadingStateView: View {
    let title: String
    var subtitle: String? = nil

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(themeManager.palette.accent)

            Text(title)
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }
}
