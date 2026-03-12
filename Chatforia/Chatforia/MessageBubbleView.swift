import SwiftUI

struct MessageBubbleView: View {
    let msg: MessageDTO
    let isMe: Bool
    let isGroupedWithPrevious: Bool
    let isGroupedWithNext: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            bubbleContent

            if shouldShowEditedLabel {
                Text("Edited")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
        .background(bubbleBackground)
        .clipShape(
            RoundedRectangle(
                cornerRadius: bubbleCornerRadius,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: bubbleCornerRadius, style: .continuous)
                .strokeBorder(strokeColor, lineWidth: strokeWidth)
        )
        .opacity((msg.deletedForAll ?? false) ? 0.8 : 1.0)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if msg.deletedForAll ?? false {
            Text("This message was deleted")
                .font(.body)
                .italic()
                .foregroundColor(.secondary)
        } else if let imageUrl = msg.imageUrl, !imageUrl.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: URL(string: imageUrl)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 220, height: 160)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 220, maxHeight: 220)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    case .failure:
                        VStack(spacing: 6) {
                            Image(systemName: "photo")
                            Text("Image unavailable")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                        .frame(width: 220, height: 160)
                    @unknown default:
                        EmptyView()
                    }
                }

                if let text = visibleText, !text.isEmpty {
                    Text(text)
                        .font(.body)
                        .foregroundColor(textColor)
                        .multilineTextAlignment(.leading)
                }
            }

        } else if let audioUrl = msg.audioUrl, !audioUrl.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Audio message", systemImage: "waveform")
                    .font(.body.weight(.medium))
                    .foregroundColor(textColor)

                if let duration = msg.audioDurationSec {
                    Text(audioDurationText(duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(audioUrl)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

        } else if msg.contentCiphertext != nil, (visibleText?.isEmpty ?? true) {
            Text("🔒 Encrypted message")
                .font(.body)
                .foregroundColor(textColor)

        } else {
            Text(visibleText ?? "—")
                .font(.body)
                .foregroundColor(textColor)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
    }

    private var visibleText: String? {
        if let translated = msg.translatedForMe, !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return translated
        }
        if let raw = msg.rawContent, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw
        }
        return nil
    }

    private var shouldShowEditedLabel: Bool {
        guard msg.deletedForAll != true else { return false }
        return msg.editedAt != nil || (msg.revision ?? 1) > 1
    }

    private var textColor: Color {
        isMe ? .white : .primary
    }

    private var bubbleBackground: some ShapeStyle {
        if isMe {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.blue, Color.blue.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
        }
    }

    private var strokeColor: Color {
        isMe ? .clear : Color.black.opacity(0.05)
    }

    private var strokeWidth: CGFloat {
        isMe ? 0 : 1
    }

    private var bubbleCornerRadius: CGFloat {
        18
    }

    private func audioDurationText(_ duration: Double) -> String {
        let total = Int(duration.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
