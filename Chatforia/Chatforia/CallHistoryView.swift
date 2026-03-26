import SwiftUI

struct CallHistoryView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var items: [CallRecordDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedSegment: CallsSegment = .recents
    @State private var showDialer = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Calls Section", selection: $selectedSegment) {
                ForEach(CallsSegment.allCases) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            ZStack {
                themeManager.palette.screenBackground
                    .ignoresSafeArea()

                switch selectedSegment {
                case .recents:
                    recentsContent

                case .voicemail:
                    VoicemailInboxView()
                }
            }
        }
        .navigationTitle("Calls")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showDialer = true
                } label: {
                    Image(systemName: "circle.grid.3x3.fill")
                }
                .accessibilityLabel("Open dial pad")
            }
        }
        .sheet(isPresented: $showDialer) {
            NavigationStack {
                DialerView()
            }
        }
    }
    
    @ViewBuilder
    private var recentsContent: some View {
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
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    @ViewBuilder
    private func contentUnavailable(title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "phone")
                .font(.system(size: 28))
                .foregroundStyle(themeManager.palette.accent)

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(themeManager.palette.primaryText)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            let fetched = try await CallHistoryService.shared.fetchHistory(token: token)

            items = fetched.sorted {
                ($0.startedAt ?? $0.createdAt) > ($1.startedAt ?? $1.createdAt)
            }
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

        if let displayName = other?.displayName,
           !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }

        if let username = other?.username,
           !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        case "ENDED":
            return "Completed"
        default:
            return directionLabel
        }
    }

    private var displayTimestamp: Date {
        item.startedAt ?? item.createdAt
    }

    private var timestampText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: displayTimestamp)
    }

    private var durationText: String? {
        guard let durationSec = item.durationSec, durationSec > 0 else { return nil }

        let hours = durationSec / 3600
        let minutes = (durationSec % 3600) / 60
        let seconds = durationSec % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
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
                .background(themeManager.palette.cardBackground)
                .clipShape(Circle())
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 6) {
                Text(otherPartyName)
                    .font(.system(size: 17, weight: item.status.uppercased() == "MISSED" ? .bold : .semibold))
                    .foregroundStyle(
                        item.status.uppercased() == "MISSED"
                        ? Color.red
                        : themeManager.palette.primaryText
                    )
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
        .padding(.vertical, 10)
    }
}
