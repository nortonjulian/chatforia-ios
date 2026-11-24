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
/// A pending socket tone yields to APNs; a late APNs cannot sound again after
/// the socket fallback has fired.
struct IncomingNotificationLedger {
    struct Decision {
        let sound: Bool
        let visualAlert: Bool
        let banner: Bool
    }

    private struct Entry {
        var sounded = false
        var visualAlerted = false
        var apnsSeen = false
        var pendingFallback = false
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

    mutating func socket(_ key: IncomingNotificationKey, eligibleForTone: Bool,
                         now: Date = Date()) -> Decision {
        var entry = prepare(key, now: now)
        let visual = !entry.visualAlerted
        entry.visualAlerted = true
        let schedule = eligibleForTone && !entry.sounded && !entry.pendingFallback
        if schedule { entry.pendingFallback = true }
        entries[key] = entry
        return Decision(sound: schedule, visualAlert: visual, banner: false)
    }

    mutating func apns(_ key: IncomingNotificationKey, bannerEligible: Bool = false,
                       now: Date = Date()) -> Decision {
        var entry = prepare(key, now: now)
        let decision = Decision(sound: !entry.sounded,
                                visualAlert: !entry.visualAlerted,
                                banner: bannerEligible && !entry.apnsSeen)
        entry.sounded = true
        entry.visualAlerted = true
        entry.apnsSeen = true
        entry.pendingFallback = false
        entries[key] = entry
        return decision
    }

    mutating func fireFallback(_ key: IncomingNotificationKey, now: Date = Date()) -> Bool {
        prune(now: now)
        guard var entry = entries[key], entry.pendingFallback, !entry.sounded else { return false }
        entry.pendingFallback = false
        entry.sounded = true
        entry.lastSeen = now
        entries[key] = entry
        return true
    }

    mutating func cancelFallbacks() {
        for key in Array(entries.keys) where entries[key]?.pendingFallback == true {
            entries[key]?.pendingFallback = false
            entries[key]?.sounded = true
        }
    }

    mutating func cancelFallback(_ key: IncomingNotificationKey) {
        entries[key]?.pendingFallback = false
        entries[key]?.sounded = true
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
    var visibleChannel: IncomingNotificationChannel?
    var visibleConversationId: Int?

    func showsBanner(channel: IncomingNotificationChannel, conversationId: Int?) -> Bool {
        guard selectedTab == 0 else { return true }
        guard let visibleChannel, let visibleConversationId else { return false }
        return visibleChannel != channel || visibleConversationId != conversationId
    }
}

enum ForegroundNotificationSound {
    static func fileName(for code: String?) -> String {
        switch code {
        case "Vibrate.mp3": return "Chatforia_Vibrate.caf"
        case "Dreamer.mp3": return "Chatforia_Dreamer.caf"
        case "Happy Message.mp3": return "Chatforia_HappyMessage.caf"
        case "Notify.mp3": return "Chatforia_Notify.caf"
        case "Pop.mp3": return "Chatforia_Pop.caf"
        case "Pulsating Sound.mp3": return "Chatforia_PulsatingSound.caf"
        case "Text Message.mp3": return "Chatforia_TextMessage.caf"
        case "Xylophone.mp3": return "Chatforia_Xylophone.caf"
        default: return "Chatforia_Default.caf"
        }
    }
}

@MainActor
final class NotificationCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    @Published var pendingChatRoomId: Int?
    @Published var pendingSMSThreadId: Int?

    @Published private(set) var accessibilityVisualAlertMessage: String?

    private var accessibilityVisualAlertDismissTask: Task<Void, Never>?

    private let apnsTokenDefaultsKey = "apns_token"
    private var isRegisteringPushToken = false
    private var pushRegistrationRetryRequested = false
    private var hasRequestedAuthorizationThisLaunch = false
    private var foregroundAccountId: Int?
    private var foregroundActive = false
    private var foregroundScreen = ForegroundMessageScreen()
    private var incomingLedger = IncomingNotificationLedger()
    private var pendingSocketSounds: [IncomingNotificationKey: Task<Void, Never>] = [:]
    private var pendingSocketSoundIDs: [IncomingNotificationKey: UUID] = [:]
    private var pendingNativeSoundRequests = Set<String>()

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

            try await DeviceRegistrationService.shared.registerPushToken(
                pushToken,
                token: authToken
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
        cancelPendingSocketSounds()
        incomingLedger.reset()
        foregroundScreen = ForegroundMessageScreen()
        foregroundAccountId = accountId
        dismissAccessibilityVisualAlert()
    }

    func setForegroundActive(_ active: Bool) {
        foregroundActive = active
        if !active { cancelPendingSocketSounds() }
    }

    func setSelectedTab(_ tab: Int, accountId: Int) {
        guard prepareForegroundAccount(accountId) else { return }
        foregroundScreen.selectedTab = tab
    }

    func setVisibleConversation(channel: IncomingNotificationChannel, id: Int,
                                accountId: Int) {
        guard prepareForegroundAccount(accountId), id > 0 else { return }
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
                              accountId: Int, eligibleForTone: Bool) {
        guard foregroundActive, UIApplication.shared.applicationState == .active,
              foregroundAccountId == accountId, accountId > 0, messageId > 0,
              UserDefaults.standard.integer(forKey: "chatforia.currentUserId") == accountId,
              TokenStore.shared.read() != nil else { return }

        let key = IncomingNotificationKey(accountId: accountId, channel: channel,
                                          messageId: messageId)
        let decision = incomingLedger.socket(key, eligibleForTone: eligibleForTone)
        if decision.visualAlert { postVisualAlert() }
        guard decision.sound else { return }

        pendingSocketSounds[key]?.cancel()
        let operationID = UUID()
        pendingSocketSoundIDs[key] = operationID
        pendingSocketSounds[key] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard let self else { return }
            defer {
                if self.pendingSocketSoundIDs[key] == operationID {
                    self.pendingSocketSounds[key] = nil
                    self.pendingSocketSoundIDs[key] = nil
                }
            }
            guard !Task.isCancelled, self.foregroundActive,
                  UIApplication.shared.applicationState == .active,
                  self.foregroundAccountId == accountId,
                  UserDefaults.standard.integer(forKey: "chatforia.currentUserId") == accountId,
                  TokenStore.shared.read() != nil,
                  self.incomingLedger.fireFallback(key) else { return }
            self.requestNativeForegroundSound(for: key)
        }
        if pendingSocketSounds.count > 512,
           let overflowKey = pendingSocketSounds.keys.first(where: { $0 != key }) {
            pendingSocketSounds.removeValue(forKey: overflowKey)?.cancel()
            pendingSocketSoundIDs[overflowKey] = nil
            incomingLedger.cancelFallback(overflowKey)
        }
    }

    private func cancelPendingSocketSounds() {
        for task in pendingSocketSounds.values { task.cancel() }
        pendingSocketSounds.removeAll()
        pendingSocketSoundIDs.removeAll()
        incomingLedger.cancelFallbacks()
        let requestIDs = Array(pendingNativeSoundRequests)
        pendingNativeSoundRequests.removeAll()
        if !requestIDs.isEmpty {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: requestIDs)
            UNUserNotificationCenter.current()
                .removeDeliveredNotifications(withIdentifiers: requestIDs)
        }
    }

    private func requestNativeForegroundSound(for key: IncomingNotificationKey) {
        let requestID = "chatforia.foreground-tone.\(key.accountId).\(key.channel.rawValue).\(key.messageId)"
        let content = UNMutableNotificationContent()
        let selectedCode = UserDefaults.standard.string(forKey: "chatforia.messageTone")
        let allowedCode: String? = {
            guard let selectedCode,
                  let plan = SubscriptionManager.shared.backendEntitlements?.appPlan,
                  !AppMessageTones.isAvailable(selectedCode, for: plan) else {
                return selectedCode
            }
            return "Default.mp3"
        }()
        content.sound = UNNotificationSound(named: UNNotificationSoundName(
            rawValue: ForegroundNotificationSound.fileName(for: allowedCode)
        ))
        content.userInfo = [
            "type": "foreground_socket_tone",
            "accountId": key.accountId,
            "messageId": key.messageId,
            "channel": key.channel.rawValue,
        ]
        if pendingNativeSoundRequests.count >= 512,
           let evicted = pendingNativeSoundRequests.first {
            pendingNativeSoundRequests.remove(evicted)
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [evicted])
        }
        pendingNativeSoundRequests.insert(requestID)
        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            guard let self, let error else { return }
            let message = error.localizedDescription
            Task { @MainActor in
                self.pendingNativeSoundRequests.remove(requestID)
                debugLog("❌ foreground message sound request failed:", message)
            }
        }
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
        pendingSocketSounds.removeValue(forKey: key)?.cancel()
        pendingSocketSoundIDs[key] = nil
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

        if notificationType == "foreground_socket_tone" {
            Task { @MainActor in
                let requestID = notification.request.identifier
                let accountId = Self.positiveID(
                    notification.request.content.userInfo["accountId"]
                )
                let shouldSound = self.pendingNativeSoundRequests.remove(requestID) != nil
                    && self.foregroundActive
                    && UIApplication.shared.applicationState == .active
                    && accountId == self.foregroundAccountId
                    && accountId == UserDefaults.standard.integer(forKey: "chatforia.currentUserId")
                    && TokenStore.shared.read() != nil
                completionHandler(shouldSound ? [.sound] : [])
            }
            return
        }

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
