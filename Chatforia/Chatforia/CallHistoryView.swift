import SwiftUI

struct CallHistoryView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var callManager: CallManager
    
    @State private var items: [CallRecordDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedSegment: CallsSegment = .recents
    @State private var showDialer = false
    @State private var savedContacts: [ContactDTO] = []
    
    @State private var selectedRoom: ChatRoomDTO?
    @State private var showSelectedRoom = false
    @State private var selectedSMSConversation: ConversationDTO?
    @State private var showSelectedSMS = false
    @StateObject private var startChatVM = StartChatViewModel()
    
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
        .navigationDestination(isPresented: $showSelectedRoom) {
            if let room = selectedRoom {
                ChatThreadView(room: room, randomSession: nil)
            }
        }
        .navigationDestination(isPresented: $showSelectedSMS) {
            if let conversation = selectedSMSConversation {
                SMSThreadView(conversation: conversation)
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
                        
                        let otherUser = (item.callerId == auth.currentUser?.id)
                            ? item.callee
                            : item.caller
                        
                        CallHistoryRowView(
                            item: item,
                            currentUserId: auth.currentUser?.id,
                            contacts: savedContacts,

                            onRedial: {
                                if let phone = item.externalPhone,
                                   !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                                    let displayName =
                                        resolvedContactName(for: phone) ??
                                        phone

                                    callManager.startCall(
                                        to: .phoneNumber(phone, displayName: displayName),
                                        auth: auth
                                    )
                                }
                            },

                            onMessage: {
                                Task {
                                    await handleMessage(for: item)
                                }
                            },

                            onVideo: otherUser == nil ? nil : {
                                guard let otherUser else { return }

                                callManager.startVideoCall(
                                    to: .appUser(
                                        userId: otherUser.id,
                                        username: otherUser.displayName ?? otherUser.username ?? "User"
                                    ),
                                    auth: auth
                                )
                            }
                        )
                        .listRowBackground(themeManager.palette.cardBackground)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    await delete(item)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                Task {
                                    await handleMessage(for: item)
                                }
                            } label: {
                                Label("Message", systemImage: "message.fill")
                            }
                            .tint(themeManager.palette.accent)
                        }
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
    
    private func delete(_ item: CallRecordDTO) async {
        guard let token = auth.currentToken, !token.isEmpty else { return }
        
        do {
            try await CallService.shared.deleteCall(callId: item.id, token: token)
            items.removeAll { $0.id == item.id }
        } catch {
            print("❌ Failed to delete call:", error)
        }
    }
    
    private func handleMessage(for item: CallRecordDTO) async {
        do {
            let otherUser = (item.callerId == auth.currentUser?.id) ? item.callee : item.caller

            if let user = otherUser {
                let destination = try await startChatVM.createOrOpenDirectChat(targetUserId: user.id)

                switch destination {
                case .chat(let room):
                    selectedRoom = room
                    showSelectedRoom = true

                case .sms(let conversation):
                    selectedSMSConversation = conversation
                    showSelectedSMS = true
                }

                return
            }

            if let rawPhone = item.externalPhone,
               let phone = PhoneContactsService.normalizePhone(rawPhone),
               !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                let matchedName = resolvedContactName(for: phone)

                let contact = ContactSearchResultDTO(
                    id: item.id,
                    alias: nil,
                    favorite: nil,
                    externalPhone: phone,
                    externalName: matchedName,
                    createdAt: nil,
                    userId: nil,
                    user: nil
                )

                let destination = try await startChatVM.destinationForContactResult(contact)

                switch destination {
                case .chat(let room):
                    selectedRoom = room
                    showSelectedRoom = true

                case .sms(let conversation):
                    selectedSMSConversation = conversation
                    showSelectedSMS = true
                }
            }
        } catch {
            print("❌ Failed to open message thread:", error)
        }
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
            async let fetchedCalls = CallHistoryService.shared.fetchHistory(token: token)
            async let fetchedContacts = ContactsService.shared.fetchContacts(token: token)
            
            let calls = try await fetchedCalls
            let contactsResponse = try await fetchedContacts
            
            savedContacts = contactsResponse.items
            
            items = calls.sorted {
                ($0.endedAt ?? $0.startedAt ?? $0.createdAt) > ($1.endedAt ?? $1.startedAt ?? $1.createdAt)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func normalizedDigits(_ value: String) -> String {
        value.filter(\.isNumber)
    }

    private func resolvedContactName(for phone: String) -> String? {
        let target = normalizedDigits(phone)

        return savedContacts.first(where: {
            guard let external = $0.externalPhone else { return false }
            return normalizedDigits(external) == target
        }).flatMap { contact in
            if let alias = contact.alias?.trimmingCharacters(in: .whitespacesAndNewlines), !alias.isEmpty {
                return alias
            }
            if let username = contact.user?.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
                return username
            }
            if let externalName = contact.externalName?.trimmingCharacters(in: .whitespacesAndNewlines), !externalName.isEmpty {
                return externalName
            }
            return nil
        }
    }
    
    private struct CallHistoryRowView: View {
        @EnvironmentObject private var themeManager: ThemeManager
        
        let item: CallRecordDTO
        let currentUserId: Int?
        let contacts: [ContactDTO]
        let onRedial: () -> Void
        let onMessage: () -> Void
        let onVideo: (() -> Void)?
        
        private func normalizedDigits(_ value: String) -> String {
            value.filter(\.isNumber)
        }

        private var matchedContactName: String? {
            guard let external = item.externalPhone else { return nil }
            let target = normalizedDigits(external)

            return contacts.first(where: {
                guard let phone = $0.externalPhone else { return false }
                return normalizedDigits(phone) == target
            }).flatMap { contact in
                if let alias = contact.alias?.trimmingCharacters(in: .whitespacesAndNewlines), !alias.isEmpty {
                    return alias
                }
                if let username = contact.user?.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
                    return username
                }
                if let externalName = contact.externalName?.trimmingCharacters(in: .whitespacesAndNewlines), !externalName.isEmpty {
                    return externalName
                }
                return nil
            }
        }
        
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

            if let matchedContactName,
               !matchedContactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return matchedContactName
            }

            if let external = item.externalPhone,
               !external.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return external
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
            item.endedAt ?? item.startedAt ?? item.createdAt
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
                
                HStack(spacing: 10) {

                    if let onVideo {
                        Button(action: onVideo) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(themeManager.palette.buttonForeground)
                                .frame(width: 36, height: 36)
                                .background(themeManager.palette.accent)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    // 📞 PHONE (existing)
                    Button(action: onRedial) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(themeManager.palette.buttonForeground)
                            .frame(width: 36, height: 36)
                            .background(themeManager.palette.accent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(item.externalPhone == nil ? 0.45 : 1.0)
                    .disabled(item.externalPhone == nil)
                }
            }
            .padding(.vertical, 10)
        }
    }
}
