import SwiftUI

struct ChatListRowView: View {
    let title: String
    let subtitle: String
    let timestamp: String
    let unreadCount: Int
    var isPinned: Bool = false

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(themeManager.palette.primaryText)
                        .lineLimit(1)

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(themeManager.palette.secondaryText)
                    }

                    Spacer(minLength: 8)

                    if !timestamp.isEmpty {
                        Text(timestamp)
                            .font(.caption)
                            .foregroundStyle(themeManager.palette.secondaryText)
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .center, spacing: 8) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(themeManager.palette.secondaryText)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    UnreadBadgeView(count: unreadCount)
                }
            }
            .padding(.vertical, 4)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .listRowBackground(themeManager.palette.cardBackground)
    }

    private var avatar: some View {
        Circle()
            .fill(themeManager.palette.accent.opacity(0.14))
            .frame(width: 44, height: 44)
            .overlay(
                Circle()
                    .stroke(themeManager.palette.border.opacity(0.8), lineWidth: 1)
            )
            .overlay(avatarContent)
    }

    @ViewBuilder
    private var avatarContent: some View {
        Text(initials)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(themeManager.palette.accent)
    }
    
    private var shouldUseGenericChatIcon: Bool {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return true }
        if cleaned.lowercased().hasPrefix("chat #") { return true }
        return false
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
