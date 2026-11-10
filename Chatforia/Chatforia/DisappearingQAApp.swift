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
        WindowGroup { DisappearingQARoot() }
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
