import SwiftUI

struct MessageReceiptSheet: View {
    let message: MessageDTO
    let isGroupRoom: Bool

    @Environment(\.dismiss) private var dismiss

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
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section {
                        ForEach(readers, id: \.id) { user in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(uiColor: .systemGray4))
                                    .frame(width: 32, height: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayName(for: user))
                                        .font(.body)

                                    Text("Read")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text(headerTitle)
                    }
                }
            }
            .navigationTitle("Message Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
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
}
