import SwiftUI

struct CallHistoryView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var items: [CallRecordDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            themeManager.palette.screenBackground
                .ignoresSafeArea()

            Group {
                if isLoading && items.isEmpty {
                    ProgressView("Loading calls…")
                } else if let errorMessage, items.isEmpty {
                    contentUnavailable(
                        title: "Couldn’t load call history",
                        message: errorMessage
                    )
                } else if items.isEmpty {
                    contentUnavailable(
                        title: "No calls yet",
                        message: "Your recent calls will show up here."
                    )
                } else {
                    List {
                        ForEach(items) { item in
                            CallHistoryRowView(
                                item: item,
                                currentUserId: auth.currentUser?.id
                            )
                            .listRowBackground(themeManager.palette.cardBackground)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Calls")
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    @ViewBuilder
    private func contentUnavailable(title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private func load() async {
        guard !isLoading else { return }
        guard let token = auth.currentToken, !token.isEmpty else {
            errorMessage = "You need to be signed in."
            items = []
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            items = try await CallHistoryService.shared.fetchHistory(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

private struct CallHistoryRowView: View {
    @EnvironmentObject private var themeManager: ThemeManager

    let item: CallRecordDTO
    let currentUserId: Int?

    private var isOutgoing: Bool {
        item.callerId == currentUserId
    }

    private var otherPartyName: String {
        let other = isOutgoing ? item.callee : item.caller
        if let name = other?.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        if let username = other?.username, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return username
        }
        return isOutgoing ? "Outgoing Call" : "Incoming Call"
    }

    private var directionLabel: String {
        isOutgoing ? "Outgoing" : "Incoming"
    }

    private var statusLabel: String {
        switch item.status.uppercased() {
        case "MISSED":
            return "Missed"
        case "DECLINED":
            return "Declined"
        case "FAILED":
            return "Failed"
        case "ACTIVE":
            return "Connected"
        case "ENDED":
            return "Ended"
        case "RINGING":
            return "Ringing"
        case "INITIATED":
            return "Initiated"
        default:
            return item.status.capitalized
        }
    }

    private var timestampText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: item.createdAt)
    }

    private var durationText: String? {
        guard let durationSec = item.durationSec, durationSec > 0 else { return nil }
        let minutes = durationSec / 60
        let seconds = durationSec % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var statusColor: Color {
        switch item.status.uppercased() {
        case "MISSED", "DECLINED", "FAILED":
            return .red
        default:
            return themeManager.palette.secondaryText
        }
    }

    private var iconName: String {
        if isOutgoing {
            return "phone.arrow.up.right"
        } else {
            return item.status.uppercased() == "MISSED" ? "phone.down.fill" : "phone.arrow.down.left"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Color.black.opacity(0.08))
                .clipShape(Circle())
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 6) {
                Text(otherPartyName)
                    .font(.headline)
                    .foregroundStyle(themeManager.palette.primaryText)

                HStack(spacing: 8) {
                    Text(directionLabel)
                    Text("•")
                    Text(statusLabel)
                    if let durationText {
                        Text("•")
                        Text(durationText)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(statusColor)

                Text(timestampText)
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}
