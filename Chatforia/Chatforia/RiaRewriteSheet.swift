import SwiftUI

struct RiaRewriteSheet: View {
    let draft: String
    let isLoading: Bool
    let options: [String]
    let onToneTap: (String) -> Void
    let onSelectRewrite: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager

    private let tones = ["friendly", "shorter", "professional", "clearer"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Original")
                    .font(.headline)
                    .foregroundStyle(themeManager.palette.primaryText)

                Text(draft)
                    .font(.body)
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(themeManager.palette.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("Choose a tone")
                    .font(.headline)
                    .foregroundStyle(themeManager.palette.primaryText)

                HStack(spacing: 8) {
                    ForEach(tones, id: \.self) { tone in
                        Button(tone.capitalized) {
                            onToneTap(tone)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if isLoading {
                    ProgressView("Rewriting…")
                        .padding(.top, 8)
                } else if !options.isEmpty {
                    Text("Suggestions")
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
                }

                Spacer()
            }
            .padding()
            .background(themeManager.palette.screenBackground)
            .navigationTitle("Rewrite with Ria")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
