import Foundation
import Combine
import UserNotifications
import UIKit

enum IncomingNotificationChannel: String, Hashable {
    case chat
    case sms
}

struct IncomingNotificationKey: Hashable {
    let accountId: Int
    let channel: IncomingNotificationChannel
    let messageId: Int
}

/// Foreground APNs and socket events share this short-lived, bounded ledger.
/// APNs owns audio. Socket delivery may show a foreground-only in-app banner
/// after a short grace period; late APNs cannot show a second banner.
struct IncomingNotificationLedger {
    struct Decision {
        let sound: Bool
        let visualAlert: Bool
        let banner: Bool
        let scheduleFallbackBanner: Bool
    }

    private struct Entry {
        var visualAlerted = false
        var apnsSeen = false
        var pendingFallbackBanner = false
        var fallbackBannerShown = false
        var lastSeen: Date
    }

    private var entries: [IncomingNotificationKey: Entry] = [:]
    private var order: [IncomingNotificationKey] = []
    private let limit = 512
    private let lifetime: TimeInterval = 5 * 60

    var count: Int { entries.count }

    mutating func reset() {
        entries.removeAll()
        order.removeAll()
    }

    mutating func socket(_ key: IncomingNotificationKey, now: Date = Date()) -> Decision {
        var entry = prepare(key, now: now)
        let visual = !entry.visualAlerted
        entry.visualAlerted = true
        let schedule = !entry.apnsSeen && !entry.pendingFallbackBanner && !entry.fallbackBannerShown
        if schedule { entry.pendingFallbackBanner = true }
        entries[key] = entry
        return Decision(sound: false, visualAlert: visual, banner: false,
                        scheduleFallbackBanner: schedule)
    }

    mutating func apns(_ key: IncomingNotificationKey, bannerEligible: Bool = false,
                       now: Date = Date()) -> Decision {
        var entry = prepare(key, now: now)
        let decision = Decision(sound: !entry.apnsSeen,
                                visualAlert: !entry.visualAlerted,
                                banner: bannerEligible && !entry.apnsSeen && !entry.fallbackBannerShown,
                                scheduleFallbackBanner: false)
        entry.visualAlerted = true
        entry.apnsSeen = true
        entry.pendingFallbackBanner = false
        entries[key] = entry
        return decision
    }

    mutating func fireFallbackBanner(_ key: IncomingNotificationKey,
                                     bannerEligible: Bool, now: Date = Date()) -> Bool {
        prune(now: now)
        guard var entry = entries[key], entry.pendingFallbackBanner, !entry.apnsSeen else {
            return false
        }
        entry.pendingFallbackBanner = false
        entry.fallbackBannerShown = bannerEligible
        entry.lastSeen = now
        entries[key] = entry
        return bannerEligible
    }

    mutating func cancelFallbackBanners() {
        for key in Array(entries.keys) where entries[key]?.pendingFallbackBanner == true {
            entries[key]?.pendingFallbackBanner = false
        }
    }

    mutating func cancelFallbackBanner(_ key: IncomingNotificationKey) {
        entries[key]?.pendingFallbackBanner = false
    }

    private mutating func prepare(_ key: IncomingNotificationKey, now: Date) -> Entry {
        prune(now: now)
        if var entry = entries[key] {
            entry.lastSeen = now
            order.removeAll { $0 == key }
            order.append(key)
            return entry
        }
        order.append(key)
        while order.count > limit {
            entries.removeValue(forKey: order.removeFirst())
        }
        return Entry(lastSeen: now)
    }

    private mutating func prune(now: Date) {
        order.removeAll { key in
            guard let entry = entries[key] else { return true }
            if now.timeIntervalSince(entry.lastSeen) > lifetime {
                entries.removeValue(forKey: key)
                return true
            }
            return false
        }
    }
}

struct ForegroundMessageScreen {
    var selectedTab = -1
    var chatsListVisible = false
    var visibleChannel: IncomingNotificationChannel?
    var visibleConversationId: Int?

    func showsBanner(channel: IncomingNotificationChannel, conversationId: Int?) -> Bool {
        guard selectedTab == 0 else { return true }
        if let visibleChannel, let visibleConversationId,
           visibleChannel == channel, visibleConversationId == conversationId { return false }
        return !chatsListVisible
    }
}

struct ChatsListPresentation {
    static func isVisible(room: Bool, sms: Bool, ria: Bool,
                          startChat: Bool, matching: Bool, modal: Bool) -> Bool {
        !(room || sms || ria || startChat || matching || modal)
    }
}

@MainActor
final class NotificationCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    @Published var pendingChatRoomId: Int?
    @Published var pendingSMSThreadId: Int?

    @Published private(set) var accessibilityVisualAlertMessage: String?
    @Published private(set) var foregroundFallbackBanner: IncomingNotificationKey?

    private var accessibilityVisualAlertDismissTask: Task<Void, Never>?
    private var fallbackBannerDismissTask: Task<Void, Never>?

    private let apnsTokenDefaultsKey = "apns_token"
    private var isRegisteringPushToken = false
    private var pushRegistrationRetryRequested = false
    private var hasRequestedAuthorizationThisLaunch = false
    private var foregroundAccountId: Int?
    private var foregroundActive = false
    private var foregroundScreen = ForegroundMessageScreen()
    private var accessibilityVisualAlertsEnabled = false
    private var incomingLedger = IncomingNotificationLedger()
    private var pendingSocketBanners: [IncomingNotificationKey: Task<Void, Never>] = [:]
    private var pendingSocketBannerIDs: [IncomingNotificationKey: UUID] = [:]

    private override init() {
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        // Prompt at most once per launch, but do not suppress subsequent APNs
        // registration requests: Apple can rotate the token independently.
        if !hasRequestedAuthorizationThisLaunch {
            hasRequestedAuthorizationThisLaunch = true
            do {
                _ = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                debugLog("❌ notification auth failed:", error)
            }
        }

        // Ask APNs for the current token even when the user has previously
        // answered the alert permission prompt. Never rely on a cached token
        // as the only source of truth.
        UIApplication.shared.registerForRemoteNotifications()
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        debugLog("✅ APNs credentials received")

        UserDefaults.standard.set(token, forKey: apnsTokenDefaultsKey)

        Task {
            await retryPushRegistrationIfPossible()
        }
    }

    func refreshBadgeState() async {
        guard let authToken = TokenStore.shared.read(),
              !authToken.isEmpty else {
            return
        }
        let accountId = UserDefaults.standard.integer(forKey: "chatforia.currentUserId")

        do {
            let badgeState =
                try await BadgeStateService.shared.fetchBadgeState(
                    token: authToken
                )

            guard TokenStore.shared.read() == authToken,
                  UserDefaults.standard.integer(forKey: "chatforia.currentUserId") == accountId
            else { return }

            let badgeCount = max(0, badgeState.total)

            if #available(iOS 16.0, *) {
                try await UNUserNotificationCenter.current()
                    .setBadgeCount(badgeCount)
            } else {
                UIApplication.shared.applicationIconBadgeNumber = badgeCount
            }

            debugLog(
                "🔢 badge state refreshed:",
                "conversations=\(badgeState.unreadConversations)",
                "missedCalls=\(badgeState.missedCalls)",
                "voicemails=\(badgeState.unreadVoicemails)",
                "total=\(badgeCount)"
            )
        } catch {
            debugLog("❌ badge state refresh failed:", error)
        }
    }

    func retryPushRegistrationIfPossible() async {
        guard let pushToken = UserDefaults.standard.string(forKey: apnsTokenDefaultsKey),
              !pushToken.isEmpty else {
            return
        }

        await registerPushTokenIfPossible(pushToken)
    }

    @discardableResult
    func handleBackgroundNotification(
        _ userInfo: [AnyHashable: Any]
    ) -> Bool {
        let notificationType =
            (userInfo["type"] as? String)?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .lowercased()

        let callLifecycleTypes: Set<String> = [
            "call_ended",
            "call_answered_elsewhere",
        ]

        guard
            let notificationType,
            callLifecycleTypes.contains(
                notificationType
            )
        else {
            return false
        }

        NotificationCenter.default.post(
            name: .socketCallEnded,
            object: nil,
            userInfo: userInfo
        )

        return true
    }

    func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        let notificationType =
            (userInfo["type"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

        if notificationType == "sms_message" {
            if let threadId = userInfo["threadId"] as? Int,
               threadId > 0 {
                pendingSMSThreadId = threadId
                return
            }

            if let threadIdNumber = userInfo["threadId"] as? NSNumber,
               threadIdNumber.intValue > 0 {
                pendingSMSThreadId = threadIdNumber.intValue
                return
            }

            if let threadIdString = userInfo["threadId"] as? String,
               let threadId = Int(threadIdString),
               threadId > 0 {
                pendingSMSThreadId = threadId
                return
            }

            return
        }

        if let roomId = userInfo["chatRoomId"] as? Int {
            pendingChatRoomId = roomId
            return
        }

        if let roomIdString = userInfo["chatRoomId"] as? String,
           let roomId = Int(roomIdString) {
            pendingChatRoomId = roomId
        }
    }

    func showAccessibilityVisualAlert(_ message: String = "New message") {
        accessibilityVisualAlertDismissTask?.cancel()

        accessibilityVisualAlertMessage = message

        accessibilityVisualAlertDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))

            guard !Task.isCancelled else { return }
            self?.accessibilityVisualAlertMessage = nil
        }
    }

    func dismissAccessibilityVisualAlert() {
        accessibilityVisualAlertDismissTask?.cancel()
        accessibilityVisualAlertDismissTask = nil
        accessibilityVisualAlertMessage = nil
    }

    // A completed network request only proves registration for the identity
    // and APNs token used when it started, not a subsequently changed account.
    static func registrationStillCurrent(
        attemptedUserId: Int,
        attemptedPushToken: String,
        currentUserId: Int,
        currentPushToken: String?
    ) -> Bool {
        attemptedUserId > 0
            && attemptedUserId == currentUserId
            && attemptedPushToken == currentPushToken
    }

    private func registerPushTokenIfPossible(_ pushToken: String) async {
        guard !isRegisteringPushToken else {
            // A new token or account may arrive during an in-flight registration.
            // Retry after completion rather than silently dropping that event.
            pushRegistrationRetryRequested = true
            return
        }

        let currentUserId =
            UserDefaults.standard.integer(
                forKey: "chatforia.currentUserId"
            )

        guard currentUserId > 0 else {
            return
        }

        // Reconcile on each foreground/login attempt, even for an unchanged
        // token: the server may have lost its registration since last success.
        guard let authToken = TokenStore.shared.read(), !authToken.isEmpty else {
            return
        }

        isRegisteringPushToken = true
        defer {
            isRegisteringPushToken = false
            if pushRegistrationRetryRequested {
                pushRegistrationRetryRequested = false
                Task { await self.retryPushRegistrationIfPossible() }
            }
        }

        do {
            _ = try await DeviceRegistrationService.shared.ensureCurrentDeviceRegistered(
                userId: currentUserId,
                token: authToken
            )

            guard TokenStore.shared.read() == authToken,
                  UserDefaults.standard.integer(forKey: "chatforia.currentUserId") == currentUserId,
                  UserDefaults.standard.string(forKey: apnsTokenDefaultsKey) == pushToken else {
                pushRegistrationRetryRequested = true
                return
            }

            try await DeviceRegistrationService.shared.registerPushToken(
                pushToken,
                token: authToken,
                userId: currentUserId
            )

            // Login/account changes can occur while the network calls are in flight.
            // Never cache success for a different account or a newer APNs token.
            let activeUserId = UserDefaults.standard.integer(
                forKey: "chatforia.currentUserId"
            )
            let activePushToken = UserDefaults.standard.string(
                forKey: apnsTokenDefaultsKey
            )
            if Self.registrationStillCurrent(
                attemptedUserId: currentUserId,
                attemptedPushToken: pushToken,
                currentUserId: activeUserId,
                currentPushToken: activePushToken
            ) {
                debugLog("✅ APNs device registration reconciled")
            } else {
                pushRegistrationRetryRequested = true
            }

        } catch {
            debugLog("❌ push token registration failed:", error)
        }
    }

    func beginForegroundSession(accountId: Int?) {
        guard foregroundAccountId != accountId else { return }
        cancelPendingSocketPresentation()
        incomingLedger.reset()
        foregroundScreen = ForegroundMessageScreen()
        foregroundAccountId = accountId
        dismissAccessibilityVisualAlert()
    }

    func setForegroundActive(_ active: Bool) {
        foregroundActive = active
        if !active { cancelPendingSocketPresentation() }
    }

    func setAccessibilityVisualAlertsEnabled(_ enabled: Bool) {
        accessibilityVisualAlertsEnabled = enabled
        if enabled { dismissForegroundFallbackBanner() }
    }

    func setSelectedTab(_ tab: Int, accountId: Int) {
        guard prepareForegroundAccount(accountId) else { return }
        if foregroundScreen.selectedTab != tab { dismissForegroundFallbackBanner() }
        foregroundScreen.selectedTab = tab
    }

    func setChatsListVisible(_ visible: Bool, accountId: Int) {
        guard prepareForegroundAccount(accountId) else { return }
        if foregroundScreen.chatsListVisible != visible { dismissForegroundFallbackBanner() }
        foregroundScreen.chatsListVisible = visible
        if visible {
            foregroundScreen.visibleChannel = nil
            foregroundScreen.visibleConversationId = nil
        }
    }

    func setVisibleConversation(channel: IncomingNotificationChannel, id: Int,
                                accountId: Int) {
        guard prepareForegroundAccount(accountId), id > 0 else { return }
        dismissForegroundFallbackBanner()
        foregroundScreen.chatsListVisible = false
        foregroundScreen.visibleChannel = channel
        foregroundScreen.visibleConversationId = id
    }

    private func prepareForegroundAccount(_ accountId: Int) -> Bool {
        guard accountId > 0,
              UserDefaults.standard.integer(forKey: "chatforia.currentUserId") == accountId,
              TokenStore.shared.read() != nil else { return false }
        if foregroundAccountId != accountId { beginForegroundSession(accountId: accountId) }
        return true
    }

    func clearVisibleConversation(channel: IncomingNotificationChannel, id: Int,
                                  accountId: Int) {
        guard foregroundAccountId == accountId,
              foregroundScreen.visibleChannel == channel,
              foregroundScreen.visibleConversationId == id else { return }
        foregroundScreen.visibleChannel = nil
        foregroundScreen.visibleConversationId = nil
    }

    func receiveSocketMessage(channel: IncomingNotificationChannel, messageId: Int,
                              conversationId: Int?, accountId: Int) {
        guard foregroundActive, UIApplication.shared.applicationState == .active,
              foregroundAccountId == accountId, accountId > 0, messageId > 0,
              UserDefaults.standard.integer(forKey: "chatforia.currentUserId") == accountId,
              TokenStore.shared.read() != nil else { return }

        let key = IncomingNotificationKey(accountId: accountId, channel: channel,
                                          messageId: messageId)
        let decision = incomingLedger.socket(key)
        if decision.visualAlert { postVisualAlert() }
        guard decision.scheduleFallbackBanner else { return }

        pendingSocketBanners[key]?.cancel()
        let operationID = UUID()
        pendingSocketBannerIDs[key] = operationID
        pendingSocketBanners[key] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard let self else { return }
            defer {
                if self.pendingSocketBannerIDs[key] == operationID {
                    self.pendingSocketBanners[key] = nil
                    self.pendingSocketBannerIDs[key] = nil
                }
            }
            guard !Task.isCancelled, self.foregroundActive,
                  UIApplication.shared.applicationState == .active,
                  self.foregroundAccountId == accountId,
                  UserDefaults.standard.integer(forKey: "chatforia.currentUserId") == accountId,
                  TokenStore.shared.read() != nil else { return }
            let eligible = self.foregroundScreen.showsBanner(
                channel: channel, conversationId: conversationId
            )
            guard self.incomingLedger.fireFallbackBanner(key, bannerEligible: eligible) else {
                return
            }
            self.presentForegroundFallbackBanner(for: key)
        }
        if pendingSocketBanners.count > 512,
           let overflowKey = pendingSocketBanners.keys.first(where: { $0 != key }) {
            pendingSocketBanners.removeValue(forKey: overflowKey)?.cancel()
            pendingSocketBannerIDs[overflowKey] = nil
            incomingLedger.cancelFallbackBanner(overflowKey)
        }
    }

    private func cancelPendingSocketPresentation() {
        for task in pendingSocketBanners.values { task.cancel() }
        pendingSocketBanners.removeAll()
        pendingSocketBannerIDs.removeAll()
        incomingLedger.cancelFallbackBanners()
        dismissForegroundFallbackBanner()
    }

    private func presentForegroundFallbackBanner(for key: IncomingNotificationKey) {
        guard !accessibilityVisualAlertsEnabled else { return }
        fallbackBannerDismissTask?.cancel()
        foregroundFallbackBanner = key
        fallbackBannerDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, self?.foregroundFallbackBanner == key else { return }
            self?.foregroundFallbackBanner = nil
        }
    }

    func dismissForegroundFallbackBanner() {
        fallbackBannerDismissTask?.cancel()
        fallbackBannerDismissTask = nil
        foregroundFallbackBanner = nil
    }

    private func postVisualAlert() {
        NotificationCenter.default.post(name: .foregroundMessageVisualAlert, object: nil)
    }

    private func foregroundPresentation(userInfo: [AnyHashable: Any],
                                        channel: IncomingNotificationChannel,
                                        accountId: Int) -> UNNotificationPresentationOptions {
        let conversationId = Self.positiveID(
            userInfo[channel == .sms ? "threadId" : "chatRoomId"]
        )
        let showBanner = foregroundScreen.showsBanner(channel: channel,
                                                      conversationId: conversationId)
        var options: UNNotificationPresentationOptions = [.badge]

        guard let messageId = Self.positiveID(userInfo["messageId"]),
              foregroundActive, foregroundAccountId == accountId,
              UIApplication.shared.applicationState == .active else {
            // Older SMS pushes have no ID. Preserve their native sound until
            // the backend carrying persisted IDs is deployed.
            if showBanner { options.insert(.banner) }
            options.insert(.sound)
            postVisualAlert()
            return options
        }

        let key = IncomingNotificationKey(accountId: accountId, channel: channel,
                                          messageId: messageId)
        let decision = incomingLedger.apns(key, bannerEligible: showBanner)
        pendingSocketBanners.removeValue(forKey: key)?.cancel()
        pendingSocketBannerIDs[key] = nil
        if decision.visualAlert { postVisualAlert() }
        if decision.banner { options.insert(.banner) }
        if decision.sound { options.insert(.sound) }
        return options
    }

    nonisolated static func positiveID(_ value: Any?) -> Int? {
        if let number = value as? NSNumber,
           String(cString: number.objCType) == "c" { return nil }
        let id = (value as? Int) ?? (value as? String).flatMap(Int.init)
        guard let id, id > 0 else { return nil }
        return id
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        let notificationType =
            (userInfo["type"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

        let senderId: Int? = {
            if let value = userInfo["senderId"] as? Int {
                return value
            }

            if let value = userInfo["senderId"] as? NSNumber {
                return value.intValue
            }

            if let value = userInfo["senderId"] as? String {
                return Int(value)
            }

            return nil
        }()

        let currentUserId =
            UserDefaults.standard.integer(
                forKey: "chatforia.currentUserId"
            )

        let isMessageNotification =
            notificationType == "message_new"
                || notificationType == "message:new"

        let isSMSNotification =
            notificationType == "sms_message"

        if notificationType == "badge_state_changed" {
            completionHandler([.badge])
            return
        }

        if isMessageNotification,
           currentUserId > 0,
           senderId == currentUserId {
            completionHandler([])
            return
        }

        if isMessageNotification || isSMSNotification {
            let channel: IncomingNotificationChannel = isSMSNotification ? .sms : .chat
            Task { @MainActor in
                let userInfo = notification.request.content.userInfo
                guard currentUserId > 0,
                      UserDefaults.standard.integer(forKey: "chatforia.currentUserId") == currentUserId,
                      TokenStore.shared.read() != nil else {
                    completionHandler([])
                    return
                }
                NotificationCenter.default.post(name: .foregroundMessageNotification,
                                                object: nil, userInfo: userInfo)
                completionHandler(self.foregroundPresentation(
                    userInfo: userInfo, channel: channel, accountId: currentUserId
                ))
            }
            return
        }

        completionHandler([.banner, .sound, .badge])
    }

    nonisolated static func chatMessageId(in userInfo: [AnyHashable: Any]) -> Int? {
        let value = userInfo["messageId"]
        let id = (value as? Int) ?? (value as? String).flatMap(Int.init)
        guard let id, id > 0 else { return nil }
        return id
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            self.handleNotificationUserInfo(response.notification.request.content.userInfo)
        }
        completionHandler()
    }
}
