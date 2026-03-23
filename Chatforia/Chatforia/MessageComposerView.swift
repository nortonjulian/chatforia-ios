import SwiftUI

struct MessageComposerView: View {
    @Binding var draft: String
    let isSending: Bool
    let onDraftChanged: () -> Void
    let onAttachmentTap: () -> Void
    let onSend: () -> Void

    let suggestions: [String]
    let isLoadingSuggestions: Bool
    let onSuggestionTap: (String) -> Void
    let onRewriteTap: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager

    init(
        draft: Binding<String>,
        isSending: Bool,
        onDraftChanged: @escaping () -> Void,
        onAttachmentTap: @escaping () -> Void,
        onSend: @escaping () -> Void,
        suggestions: [String] = [],
        isLoadingSuggestions: Bool = false,
        onSuggestionTap: @escaping (String) -> Void = { _ in },
        onRewriteTap: @escaping () -> Void = {}
    ) {
        self._draft = draft
        self.isSending = isSending
        self.onDraftChanged = onDraftChanged
        self.onAttachmentTap = onAttachmentTap
        self.onSend = onSend
        self.suggestions = suggestions
        self.isLoadingSuggestions = isLoadingSuggestions
        self.onSuggestionTap = onSuggestionTap
        self.onRewriteTap = onRewriteTap
    }

    private var isDisabled: Bool {
        isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            RiaSuggestionBar(
                suggestions: suggestions,
                isLoading: isLoadingSuggestions,
                onTap: onSuggestionTap
            )

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    onAttachmentTap()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(themeManager.palette.accent)
                        .frame(width: 30, height: 30)
                        .background(themeManager.palette.cardBackground)
                        .overlay(
                            Circle()
                                .stroke(themeManager.palette.border, lineWidth: 1)
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isSending)

                HStack(alignment: .bottom, spacing: 8) {
                    Button {
                        onRewriteTap()
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(themeManager.palette.accent)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    TextField("Message", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .foregroundStyle(themeManager.palette.primaryText)
                        .lineLimit(1...5)
                        .padding(.vertical, 11)
                        .disabled(isSending)
                        .onChange(of: draft) { _, _ in
                            onDraftChanged()
                        }

                    Button {
                        onSend()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            themeManager.palette.composerButtonStart,
                                            themeManager.palette.composerButtonEnd
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 36, height: 36)
                                .shadow(
                                    color: themeManager.palette.composerButtonEnd.opacity(0.35),
                                    radius: 8,
                                    x: 0,
                                    y: 3
                                )

                            if isSending {
                                ProgressView()
                                    .tint(themeManager.palette.composerButtonForeground)
                                    .scaleEffect(0.85)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(themeManager.palette.composerButtonForeground)
                            }
                        }
                        .opacity(isDisabled ? 0.6 : 1)
                        .scaleEffect(isDisabled ? 0.95 : 1)
                        .animation(.easeInOut(duration: 0.15), value: isDisabled)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDisabled)
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
                }
                .padding(.leading, 6)
                .background(themeManager.palette.composerFieldBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(themeManager.palette.composerBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(themeManager.palette.composerBackground)
    }
}
