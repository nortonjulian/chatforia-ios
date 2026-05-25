import SwiftUI

struct RiaRewriteSheet: View {
    let draft: String
    let isLoading: Bool
    let options: [String]
    let errorText: String?
    let disabledReason: String?
    let onToneTap: (String) -> Void
    let onSelectRewrite: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager

    private let tones = ["friendly", "shorter", "professional", "clearer"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "ria.rewrite.original"))
                    .font(.headline)
                    .foregroundStyle(themeManager.palette.primaryText)

                Text(draft)
                    .font(.body)
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(themeManager.palette.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(String(localized: "ria.rewrite.choose_tone"))
                    .font(.headline)
                    .foregroundStyle(themeManager.palette.primaryText)

                HStack(spacing: 8) {
                    ForEach(tones, id: \.self) { tone in
                        Button(String(localized: "ria.rewrite.tone.\(tone)")) {
                            onToneTap(tone)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoading)
                    }
                }

                if isLoading {
                    ProgressView(String(localized: "ria.rewrite.rewriting"))
                        .padding(.top, 8)
                } else if let disabledReason, !disabledReason.isEmpty {
                    Text(disabledReason)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .padding(.top, 8)
                } else if let errorText, !errorText.isEmpty {
                    Text(errorText)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(.top, 8)
                } else if !options.isEmpty {
                    Text(String(localized: "ria.rewrite.suggestions"))
                        .font(.headline)
                        .foregroundStyle(themeManager.palette.primaryText)

                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(options, id: \.self) { option in
                                Button {
                                    onSelectRewrite(option)
                                    dismiss()
                                } label: {
                                    Text(option)
                                        .font(.body)
                                        .foregroundStyle(themeManager.palette.primaryText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .background(themeManager.palette.cardBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    Text(String(localized: "ria.rewrite.empty"))
                        .font(.subheadline)
                        .foregroundStyle(themeManager.palette.secondaryText)
                        .padding(.top, 8)
                }

                Spacer()
            }
            .padding()
            .background(themeManager.palette.screenBackground)
            .navigationTitle(String(localized: "ria.rewrite.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
