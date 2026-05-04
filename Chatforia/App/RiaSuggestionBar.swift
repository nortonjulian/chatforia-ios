import SwiftUI

struct RiaSuggestionBar: View {
    let suggestions: [String]
    let isLoading: Bool
    let onTap: (String) -> Void

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        if isLoading || !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if isLoading && suggestions.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule()
                                .fill(themeManager.palette.cardBackground)
                                .frame(width: 120, height: 34)
                                .overlay(
                                    Capsule()
                                        .stroke(themeManager.palette.border, lineWidth: 1)
                                )
                                .redacted(reason: .placeholder)
                        }
                    } else {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                onTap(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.subheadline)
                                    .foregroundStyle(themeManager.palette.primaryText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(themeManager.palette.cardBackground)
                                    .overlay(
                                        Capsule()
                                            .stroke(themeManager.palette.border, lineWidth: 1)
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }
        }
    }
}
