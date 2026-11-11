#if DISAPPEARING_QA
import SwiftUI
import Combine

// This entry point is compiled only for the disposable simulator build.
private final class QADenyNetworkProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

@main
struct DisappearingQAApp: App {
    init() { URLProtocol.registerClass(QADenyNetworkProtocol.self) }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--forwarding-qa") {
                ForwardingQARoot()
            } else {
                DisappearingQARoot()
            }
        }
    }
}

@MainActor
private final class QAForwardingTokenStore: TokenStoring {
    func read() -> String? { "synthetic-forwarding-token" }
    func save(_ token: String) {}
    func clear() {}
}

@MainActor
private final class QAForwardingSocket: SocketManaging {
    func connect(token: String) {}
    func disconnect() {}
}

@MainActor
private final class QAForwardingStore {
    private var values: [Int: ForwardingSettingsDTO] = [
        1: ForwardingSettingsDTO(
            forwardingEnabledSms: true, forwardSmsToPhone: true,
            forwardPhoneNumber: "+15551110000", forwardSmsToEmail: false,
            forwardEmail: "", forwardingEnabledCalls: false,
            forwardToPhoneE164: "", forwardQuietHoursStart: 22,
            forwardQuietHoursEnd: 6),
        2: ForwardingSettingsDTO(
            forwardingEnabledSms: false, forwardSmsToPhone: false,
            forwardPhoneNumber: "", forwardSmsToEmail: false,
            forwardEmail: "", forwardingEnabledCalls: true,
            forwardToPhoneE164: "+15552220000", forwardQuietHoursStart: nil,
            forwardQuietHoursEnd: nil)
    ]

    func fetch(_ account: Int) -> ForwardingSettingsDTO {
        if ProcessInfo.processInfo.arguments.contains("--forwarding-qa-invalid"), account == 1 {
            return ForwardingSettingsDTO(
                forwardingEnabledSms: true, forwardSmsToPhone: true,
                forwardPhoneNumber: "bad", forwardSmsToEmail: false,
                forwardEmail: "", forwardingEnabledCalls: false,
                forwardToPhoneE164: "", forwardQuietHoursStart: 22,
                forwardQuietHoursEnd: nil)
        }
        return values[account] ?? .empty
    }

    func save(_ dto: ForwardingSettingsDTO, for account: Int) -> ForwardingSettingsDTO {
        values[account] = dto
        return dto
    }
}

@MainActor
private struct ForwardingQARoot: View {
    @StateObject private var auth = ForwardingQARoot.makeAuth()
    @StateObject private var theme = ThemeManager()
    @State private var store = QAForwardingStore()
    @State private var account = ProcessInfo.processInfo.arguments.contains("--forwarding-qa-account-b") ? 2 : 1

    private static func user(_ id: Int) -> UserDTO {
        let data = Data("{\"id\":\(id),\"username\":\"synthetic\",\"plan\":\"PLUS\"}".utf8)
        return try! JSONDecoder().decode(UserDTO.self, from: data)
    }

    private static func makeAuth() -> AuthStore {
        let auth = AuthStore(tokenStore: QAForwardingTokenStore(),
            socket: QAForwardingSocket(), refreshEntitlements: {},
            ensureLocalKeys: { _, _ in false }, finishLoginNotifications: {})
        auth.state = .loggedIn(user(
            ProcessInfo.processInfo.arguments.contains("--forwarding-qa-account-b") ? 2 : 1))
        return auth
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("Synthetic iOS forwarding QA · network blocked")
                .font(.caption2)
            Button("Switch synthetic account (now \(account))") {
                account = account == 1 ? 2 : 1
                auth.state = .loggedIn(Self.user(account))
            }
            NavigationStack {
                ForwardingSettingsView(
                    fetchSettings: { _ in store.fetch(account) },
                    saveSettings: { dto, _ in store.save(dto, for: account) })
            }
        }
        .environmentObject(auth)
        .environmentObject(theme)
        .task {
            if ProcessInfo.processInfo.arguments.contains("--forwarding-qa-autoswitch") {
                try? await Task.sleep(for: .seconds(5))
                account = 2
                auth.state = .loggedIn(Self.user(2))
            }
        }
    }
}

@MainActor
private struct DisappearingQARoot: View {
    @StateObject private var threadVM = ChatThreadViewModel()
    @StateObject private var auth = AuthStore()
    @StateObject private var theme = ThemeManager()
    @StateObject private var settings = SettingsViewModel()
    @StateObject private var calls = CallManager()
    @State private var now = Date()
    @State private var showThread = true
    @State private var didReconnect = false
    @State private var didReopen = false
    @State private var didScroll = false

    private let deadline = Self.fixedDeadline()
    private let room = ChatRoomDTO(id: 80808, name: "Synthetic expiring chat",
        isGroup: false, updatedAt: nil, phone: nil, lastMessage: nil,
        participants: nil)

    private static func fixedDeadline() -> Date {
        let key = "disappearing.qa.deadline.20261110"
        if ProcessInfo.processInfo.arguments.contains("--qa-reset") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        if let saved = UserDefaults.standard.object(forKey: key) as? Date {
            return saved
        }
        let value = Date().addingTimeInterval(45)
        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    private func fixture() -> [MessageDTO] {
        let sender = SenderDTO(id: 9, username: "synthetic", publicKey: nil,
            avatarUrl: nil)
        let history = (1...20).map { id in
            MessageDTO(id: id,
                rawContent: id == 1 ? "Expiring scrolled history" : "Synthetic history \(id)",
                createdAt: deadline.addingTimeInterval(Double(id - 60)),
                expiresAt: id == 1 ? deadline : nil,
                sender: sender, chatRoomId: room.id)
        }
        return history + [
            MessageDTO(id: 21, rawContent: "Expiring visible text",
                createdAt: deadline.addingTimeInterval(-2), expiresAt: deadline,
                sender: sender, chatRoomId: room.id),
            MessageDTO(id: 22, rawContent: "Expiring attachment",
                attachments: [AttachmentDTO(id: 51, kind: "FILE",
                    url: "qa://local-only/attachment.txt", mimeType: "text/plain")],
                createdAt: deadline.addingTimeInterval(-1), expiresAt: deadline,
                sender: sender, chatRoomId: room.id)
        ]
    }

    private var preview: String {
        fixture().filter { $0.expiresAt.map { $0 > now } ?? true }
            .last?.rawContent ?? "No live messages"
    }

    var body: some View {
        VStack(spacing: 3) {
            Text("Synthetic iOS expiry QA · network blocked")
                .font(.caption2)
            ChatListRowView(title: "Synthetic expiring chat", subtitle: preview,
                timestamp: "", unreadCount: 0, avatarUsers: [])
                .padding(.horizontal, 12)
            Text("Reloads \(threadVM.qaReloadCount) · \(now < deadline ? "before" : "after") deadline")
                .font(.caption2)
            if showThread {
                NavigationStack {
                    ChatThreadView(room: room, qaViewModel: threadVM,
                        source: fixture)
                }
            } else {
                Text("Thread backgrounded")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environmentObject(auth)
        .environmentObject(theme)
        .environmentObject(settings)
        .environmentObject(calls)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            now = date
            if date >= deadline.addingTimeInterval(3), !didReconnect {
                didReconnect = true
                NotificationCenter.default.post(name: .socketDidReconnect, object: nil)
            }
            if date >= deadline.addingTimeInterval(7), !didReopen {
                didReopen = true
                showThread = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showThread = true }
            }
            if date >= deadline.addingTimeInterval(13), !didScroll {
                didScroll = true
                NotificationCenter.default.post(
                    name: Notification.Name("DisappearingQAScrollOldest"), object: nil)
            }
        }
    }
}
#endif
