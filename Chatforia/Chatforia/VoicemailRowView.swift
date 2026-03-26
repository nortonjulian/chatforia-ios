import SwiftUI

struct VoicemailRowView: View {
    let voicemail: VoicemailDTO
    let onTap: () -> Void
    let onToggleRead: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(voicemail.isRead ? Color.clear : themeManager.palette.accent)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(displayCaller)
                            .font(.subheadline.weight(voicemail.isRead ? .regular : .bold))                            .foregroundStyle(themeManager.palette.primaryText)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(dateText)
                            .font(.caption)
                            .foregroundStyle(themeManager.palette.secondaryText)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        Label("Voicemail", systemImage: "waveform")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(themeManager.palette.accent)

                        if let durationSec = voicemail.durationSec {
                            Text(AudioAttachmentCardView.formatTime(Double(durationSec)))
                                .font(.caption)
                                .foregroundStyle(themeManager.palette.secondaryText)
                        }
                    }

                    if let transcriptPreview {
                        Text(transcriptPreview)
                            .font(.caption)
                            .foregroundStyle(themeManager.palette.secondaryText)
                            .lineLimit(2)
                    } else {
                        Text(fallbackSubtitle)
                            .font(.caption)
                            .foregroundStyle(themeManager.palette.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(themeManager.palette.cardBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }

            Button(action: onToggleRead) {
                Label(voicemail.isRead ? "Unread" : "Read",
                      systemImage: voicemail.isRead ? "envelope.badge" : "checkmark.circle")
            }
            .tint(voicemail.isRead ? .orange : .blue)
        }
    }

    private var displayCaller: String {
        let trimmed = voicemail.fromNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown Caller" : trimmed
    }

    private var transcriptPreview: String? {
        guard voicemail.transcriptStatus == .complete,
              let transcript = voicemail.transcript?.trimmingCharacters(in: .whitespacesAndNewlines),
              !transcript.isEmpty else {
            return nil
        }
        return transcript
    }

    private var fallbackSubtitle: String {
        switch voicemail.transcriptStatus {
        case .pending:
            return "Transcript pending"
        case .failed:
            return "Transcript unavailable"
        case .complete:
            return "Tap to play"
        }
    }

    private var dateText: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(voicemail.createdAt) {
            formatter.timeStyle = .short
            formatter.dateStyle = .none
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .short
        }
        return formatter.string(from: voicemail.createdAt)
    }
}
