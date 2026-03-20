import SwiftUI

struct MessageComposerView: View {
    @Binding var draft: String
    let isSending: Bool
    let onDraftChanged: () -> Void
    let onAttachmentTap: () -> Void
    let onSend: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager

    private var isDisabled: Bool {
        isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {

            // ➕ Attachment button
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

            // ✍️ Input + Send
            HStack(alignment: .bottom, spacing: 8) {

                // Text input
                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundStyle(themeManager.palette.primaryText)
                    .lineLimit(1...5)
                    .padding(.vertical, 11)
                    .padding(.leading, 12)
                    .disabled(isSending)
                    .onChange(of: draft) { _, _ in
                        onDraftChanged()
                    }

                // 🚀 Send Button (FIXED)
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
            .background(themeManager.palette.composerFieldBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(themeManager.palette.composerBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(themeManager.palette.composerBackground)
    }
}
