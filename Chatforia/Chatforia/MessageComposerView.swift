import SwiftUI

struct MessageComposerView: View {
    @Binding var draft: String

    @EnvironmentObject var settingsVM: SettingsViewModel
    
    let isSending: Bool
    let isSendingVoice: Bool
    let onDraftChanged: () -> Void
    let onAttachmentTap: () -> Void
    let onSend: () -> Void

    let suggestions: [String]
    let isLoadingSuggestions: Bool
    let onSuggestionTap: (String) -> Void
    let onRewriteTap: () -> Void

    let isRecordingVoice: Bool
    let recordingDurationText: String
    let voiceDraftDurationText: String?
    let onMicTap: () -> Void
    let onStopRecordingTap: () -> Void
    let onCancelRecordingTap: () -> Void
    let onCancelVoiceDraftTap: () -> Void
    let onSendVoiceDraftTap: () -> Void
    let onPlayVoiceDraftTap: () -> Void
    let isPlayingVoiceDraft: Bool
    let hasVoiceDraft: Bool

    @EnvironmentObject private var themeManager: ThemeManager

    init(
        draft: Binding<String>,
        isSending: Bool,
        isSendingVoice: Bool = false,
        onDraftChanged: @escaping () -> Void,
        onAttachmentTap: @escaping () -> Void,
        onSend: @escaping () -> Void,
        suggestions: [String] = [],
        isLoadingSuggestions: Bool = false,
        onSuggestionTap: @escaping (String) -> Void = { _ in },
        onRewriteTap: @escaping () -> Void = {},
        isRecordingVoice: Bool = false,
        recordingDurationText: String = "0:00",
        voiceDraftDurationText: String? = nil,
        onMicTap: @escaping () -> Void = {},
        onStopRecordingTap: @escaping () -> Void = {},
        onCancelRecordingTap: @escaping () -> Void = {},
        onCancelVoiceDraftTap: @escaping () -> Void = {},
        onSendVoiceDraftTap: @escaping () -> Void = {},
        onPlayVoiceDraftTap: @escaping () -> Void = {},
        isPlayingVoiceDraft: Bool = false,
        hasVoiceDraft: Bool = false
    ) {
        self._draft = draft
        self.isSending = isSending
        self.isSendingVoice = isSendingVoice
        self.onDraftChanged = onDraftChanged
        self.onAttachmentTap = onAttachmentTap
        self.onSend = onSend
        self.suggestions = suggestions
        self.isLoadingSuggestions = isLoadingSuggestions
        self.onSuggestionTap = onSuggestionTap
        self.onRewriteTap = onRewriteTap
        self.isRecordingVoice = isRecordingVoice
        self.recordingDurationText = recordingDurationText
        self.voiceDraftDurationText = voiceDraftDurationText
        self.onMicTap = onMicTap
        self.onStopRecordingTap = onStopRecordingTap
        self.onCancelRecordingTap = onCancelRecordingTap
        self.onCancelVoiceDraftTap = onCancelVoiceDraftTap
        self.onSendVoiceDraftTap = onSendVoiceDraftTap
        self.onPlayVoiceDraftTap = onPlayVoiceDraftTap
        self.isPlayingVoiceDraft = isPlayingVoiceDraft
        self.hasVoiceDraft = hasVoiceDraft
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isTextSendDisabled: Bool {
        isSending || isSendingVoice || trimmedDraft.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if settingsVM.enableSmartReplies && !suggestions.isEmpty {
                RiaSuggestionBar(
                    suggestions: suggestions,
                    isLoading: false,
                    onTap: onSuggestionTap
                )
            }

            if hasVoiceDraft {
                voiceDraftPreview
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
            }

            if isRecordingVoice {
                recordingBar
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                normalComposer
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
        }
        .background(themeManager.palette.composerBackground)
    }

    private var normalComposer: some View {
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
            .disabled(isSending || isSendingVoice || hasVoiceDraft || isRecordingVoice)

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
                .disabled(isSending || isSendingVoice || trimmedDraft.isEmpty || hasVoiceDraft || isRecordingVoice)

                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundStyle(themeManager.palette.primaryText)
                    .lineLimit(1...5)
                    .padding(.vertical, 11)
                    .disabled(isSending || isSendingVoice || hasVoiceDraft || isRecordingVoice)
                    .onChange(of: draft) { _, _ in
                        onDraftChanged()
                    }

                trailingAction
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
    }

    @ViewBuilder
    private var trailingAction: some View {
        if hasVoiceDraft {
            Button {
                onSendVoiceDraftTap()
            } label: {
                actionCircle(systemName: "arrow.up")
            }
            .buttonStyle(.plain)
            .disabled(isSending || isSendingVoice)
        } else if trimmedDraft.isEmpty {
            Button {
                onMicTap()
            } label: {
                actionCircle(systemName: "mic.fill")
            }
            .buttonStyle(.plain)
            .disabled(isSending || isSendingVoice || isRecordingVoice)
        } else {
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
                .opacity(isTextSendDisabled ? 0.6 : 1)
                .scaleEffect(isTextSendDisabled ? 0.95 : 1)
                .animation(.easeInOut(duration: 0.15), value: isTextSendDisabled)
            }
            .buttonStyle(.plain)
            .disabled(isTextSendDisabled)
        }
    }

    private var recordingBar: some View {
        HStack(spacing: 10) {
            Button(role: .destructive) {
                onCancelRecordingTap()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.red.opacity(0.9))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)

                Text("Recording…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                Spacer(minLength: 0)

                Text(recordingDurationText)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(themeManager.palette.secondaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(themeManager.palette.composerFieldBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(themeManager.palette.composerBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Button {
                onStopRecordingTap()
            } label: {
                actionCircle(systemName: "stop.fill")
            }
            .buttonStyle(.plain)
            .disabled(isSendingVoice)
        }
    }

    private var voiceDraftPreview: some View {
        HStack(spacing: 10) {
            Button {
                onPlayVoiceDraftTap()
            } label: {
                Image(systemName: isPlayingVoiceDraft ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(themeManager.palette.accent)
                    .frame(width: 32, height: 32)
                    .background(themeManager.palette.cardBackground)
                    .overlay(
                        Circle()
                            .stroke(themeManager.palette.border, lineWidth: 1)
                    )
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isSendingVoice)

            VStack(alignment: .leading, spacing: 2) {
                Text("Voice note ready")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                Text(voiceDraftDurationText ?? "0:00")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(themeManager.palette.secondaryText)
            }

            Spacer(minLength: 0)

            Button("Cancel") {
                onCancelVoiceDraftTap()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(themeManager.palette.secondaryText)
            .buttonStyle(.plain)
            .disabled(isSendingVoice)

            Button {
                onSendVoiceDraftTap()
            } label: {
                Text("Send")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(themeManager.palette.composerButtonForeground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
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
                    )
            }
            .buttonStyle(.plain)
            .disabled(isSending || isSendingVoice)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(themeManager.palette.composerFieldBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(themeManager.palette.composerBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func actionCircle(systemName: String) -> some View {
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

            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(themeManager.palette.composerButtonForeground)
        }
    }
}
