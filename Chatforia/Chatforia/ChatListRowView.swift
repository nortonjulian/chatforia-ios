import SwiftUI

struct ChatListRowView: View {
    let title: String
    let subtitle: String
    let timestamp: String
    let unreadCount: Int
    var isPinned: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    if !timestamp.isEmpty {
                        Text(timestamp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .center, spacing: 8) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    UnreadBadgeView(count: unreadCount)
                }
            }
            .padding(.vertical, 4)
        }
        .contentShape(Rectangle())
    }

    private var avatar: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.14))
            .frame(width: 44, height: 44)
            .overlay(
                Text(initials)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            )
    }

    private var initials: String {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return "C" }

        if cleaned.lowercased().hasPrefix("chat #") {
            return "C"
        }

        let parts = cleaned
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }

        if !parts.isEmpty {
            return parts.joined()
        }

        return String(cleaned.prefix(1)).uppercased()
    }
}
