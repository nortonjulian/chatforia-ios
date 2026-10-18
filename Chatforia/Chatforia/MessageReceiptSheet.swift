import SwiftUI

struct MessageReceiptSheet: View {
    let message: MessageDTO
    let isGroupRoom: Bool

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"

    private var readers: [UserSummaryDTO] {
        let readBy = message.readBy ?? []
        return readBy.filter { $0.id != message.sender.id }
    }

    var body: some View {
        NavigationStack {
            List {
                if readers.isEmpty {
                    Section {
                        Text(appText("messages.noOneReadYet", languageCode: appLanguage))
                            .foregroundStyle(themeManager.palette.secondaryText)
                    }
                    .listRowBackground(themeManager.palette.cardBackground)
                } else {
                    Section {
                        ForEach(readers, id: \.id) { user in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(themeManager.palette.accent.opacity(0.16))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Text(initials(for: user))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(themeManager.palette.accent)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayName(for: user))
                                        .font(.body)
                                        .foregroundStyle(themeManager.palette.primaryText)

                                    Text(
                                        appText(
                                            "messages.messageInfo",
                                            languageCode: appLanguage
                                        )
                                    )
                                        .font(.caption)
                                        .foregroundStyle(themeManager.palette.secondaryText)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text(headerTitle)
                    }
                    .listRowBackground(themeManager.palette.cardBackground)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(themeManager.palette.screenBackground)
            .navigationTitle(appText("messages.messageInfo", languageCode: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(appText("common.done", languageCode: appLanguage)) {
                        dismiss()
                    }
                    .foregroundStyle(themeManager.palette.accent)
                }
            }
        }
    }

    private var headerTitle: String {
        if isGroupRoom {
            if readers.count == 1 {
                return appText("messages.seenByOnePerson", languageCode: appLanguage)
            }

            return GroupReceiptLabel.seenByPeopleCount(readers.count, languageCode: appLanguage)
        }

        return appText("messages.seen", languageCode: appLanguage)
    }

    private func displayName(for user: UserSummaryDTO) -> String {
        let raw = user.username?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let raw, !raw.isEmpty {
            return raw
        }

        return GroupReceiptLabel.userWithId(user.id, languageCode: appLanguage)
    }

    private func initials(for user: UserSummaryDTO) -> String {
        let name = displayName(for: user)

        let parts = name
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }

        if !parts.isEmpty {
            return parts.joined()
        }

        return String(name.prefix(1)).uppercased()
    }
}

// Scoped to receipt labels. The catalog mixes named and legacy printf tokens;
// substitute literally so participant names are never interpreted as formats.
enum GroupReceiptLabel {
    static func readByUser(_ name: String, languageCode: String) -> String {
        render(appText("messages.readByUser", languageCode: languageCode),
               token: "name", value: name, fallback: "Read by \(name)")
    }

    static func readByCount(_ count: Int, languageCode: String) -> String {
        render(appText("messages.readByCount", languageCode: languageCode),
               token: "count", value: String(count), fallback: "Read by \(count)")
    }

    static func seenByPeopleCount(_ count: Int, languageCode: String) -> String {
        render(appText("messages.seenByPeopleCount", languageCode: languageCode),
               token: "count", value: String(count), fallback: "Seen by \(count) people")
    }

    static func userWithId(_ id: Int, languageCode: String) -> String {
        render(appText("common.userWithId", languageCode: languageCode),
               token: "id", value: String(id), fallback: "User \(id)")
    }

    private static func render(_ template: String, token: String, value: String, fallback: String) -> String {
        let formats = token == "name"
            ? ["{name}", "%1$@", "%@"]
            : ["{\(token)}", "%1$lld", "%lld", "%1$ld", "%ld", "%1$d", "%d"]
        for format in formats where template.contains(format) {
            return template.replacingOccurrences(of: format, with: value)
        }
        // A missing/malformed translation must still identify its reader/count.
        return fallback
    }
}
