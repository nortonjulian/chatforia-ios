import SwiftUI

struct MessageReceiptSheet: View {
    let message: MessageDTO
    let isGroupRoom: Bool

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager

    private var readers: [UserSummaryDTO] {
        let readBy = message.readBy ?? []
        return readBy.filter { $0.id != message.sender.id }
    }

    var body: some View {
        NavigationStack {
            List {
                if readers.isEmpty {
                    Section {
                        Text("No one has read this message yet.")
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

                                    Text("Read")
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
            .navigationTitle("Message Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(themeManager.palette.accent)
                }
            }
        }
    }

    private var headerTitle: String {
        if isGroupRoom {
            return readers.count == 1 ? "Seen by 1 person" : "Seen by \(readers.count) people"
        } else {
            return "Seen"
        }
    }

    private func displayName(for user: UserSummaryDTO) -> String {
        let raw = user.username?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty { return raw }
        return "User \(user.id)"
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
