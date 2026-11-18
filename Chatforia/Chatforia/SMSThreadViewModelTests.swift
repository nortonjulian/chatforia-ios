import XCTest
@testable import Chatforia

@MainActor
final class SMSThreadViewModelTests: XCTestCase {

    func testRestrictedMmsResponseKeepsTextAndDoesNotExposeMediaURL() throws {
        let json = """
        {"id":42,"threadId":9,"direction":"in","body":"keep text","mediaUrls":[],"mediaRestricted":true,
         "createdAt":"2026-11-17T00:00:00Z"}
        """
        let dto = try JSONDecoder.tolerantISO8601Decoder().decode(SMSMessageDTO.self, from: Data(json.utf8))
        XCTAssertTrue(dto.mediaRestricted)
        XCTAssertEqual(dto.body, "keep text")
        XCTAssertTrue(dto.media.isEmpty)
    }

    func testTeenCachedMmsMediaKeepsAudioAndHidesVisualOrUnknownItems() {
        let message = SMSMessageDTO(
            id: 42, direction: "in", body: "text",
            media: [
                SMSMediaItemDTO(url: "https://example.test/photo.jpg", contentType: "image/jpeg"),
                SMSMediaItemDTO(url: "https://example.test/voice.mp3", contentType: "audio/mpeg"),
                SMSMediaItemDTO(url: "https://example.test/disguised.mp3", contentType: "image/jpeg"),
                SMSMediaItemDTO(url: "https://example.test/opaque"),
            ],
            createdAt: Date()
        )
        XCTAssertEqual(message.mediaVisibleToTeen.count, 1)
        XCTAssertTrue(message.mediaVisibleToTeen[0].isAudio)
    }

    private final class ReadProbe {
        var accountId = 1
        var token = "synthetic-token"
        var posts: [[Int]] = []
        var badgeRefreshes = 0
        var failPost = false
    }

    private func fixtureThread() throws -> SMSThreadDTO {
        let data = Data(#"{"id":67,"userId":1,"participants":[],"messages":[{"id":501,"threadId":67,"direction":"in","body":"visible","createdAt":"2026-11-15T12:00:00Z"},{"id":500,"threadId":67,"direction":"out","body":"sent","createdAt":"2026-11-15T12:01:00Z"},{"id":499,"threadId":67,"direction":"in","body":"off screen","createdAt":"2026-11-15T11:59:00Z"}]}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SMSThreadDTO.self, from: data)
    }

    private func readModel(_ probe: ReadProbe, thread: SMSThreadDTO) -> SMSThreadViewModel {
        SMSThreadViewModel(
            fetchThread: { _, _ in thread },
            postRead: { _, ids, _ in
                probe.posts.append(ids)
                if probe.failPost { throw URLError(.notConnectedToInternet) }
            },
            refreshBadge: { probe.badgeRefreshes += 1 },
            currentIdentity: { (probe.accountId, probe.token) }
        )
    }

    func testReadRequestUsesExactAuthenticatedPostContract() throws {
        let request = try SMSThreadViewModel.readAPIRequest(threadId: 67, ids: [501, 502])
        XCTAssertEqual(request.path, "sms/threads/67/read")
        XCTAssertEqual(request.method.rawValue, "POST")
        XCTAssertTrue(request.requiresAuth)
        XCTAssertEqual(try JSONDecoder().decode([String: [Int]].self, from: request.body ?? Data()),
                       ["messageIds": [501, 502]])
    }

    func testOnlyRowsIntersectingScrollViewportAreVisible() {
        let viewport = CGRect(x: 0, y: 0, width: 320, height: 480)
        let frames: [Int: CGRect] = [
            501: CGRect(x: 10, y: 100, width: 200, height: 40),
            502: CGRect(x: 10, y: 490, width: 200, height: 40),
            503: CGRect(x: 10, y: -30, width: 200, height: 40),
            504: .zero
        ]
        XCTAssertEqual(SMSVisibleMessageRows.ids(in: frames, viewport: viewport), [501, 503])
    }

    func testHistoryFetchAndOffscreenOrOutgoingRowsNeverAcknowledge() async throws {
        let thread = try fixtureThread()
        let probe = ReadProbe()
        let vm = readModel(probe, thread: thread)

        await vm.loadThread(threadId: 67, token: probe.token)
        XCTAssertEqual(vm.messages.count, 3)
        XCTAssertTrue(probe.posts.isEmpty)
        XCTAssertEqual(probe.badgeRefreshes, 0)

        vm.messages.append(SMSMessageDTO(id: 497, threadId: 67, direction: "unknown",
                                         body: "invalid direction", createdAt: Date()))
        vm.updateVisibleMessages([497, 500], threadId: 67, accountId: 1,
                                 token: probe.token, isForeground: true)
        await vm.acknowledgeVisibleMessages()
        XCTAssertTrue(probe.posts.isEmpty)
        XCTAssertEqual(probe.badgeRefreshes, 0)

        vm.updateVisibleMessages([497, 500, 501], threadId: 67, accountId: 1,
                                 token: probe.token, isForeground: true)
        await vm.acknowledgeVisibleMessages()
        XCTAssertEqual(probe.posts, [[501]])
        XCTAssertEqual(probe.badgeRefreshes, 1)
        XCTAssertFalse(probe.posts.flatMap { $0 }.contains(499))
    }

    func testBackgroundAndFailedReadKeepUnreadUntilExactRetrySucceeds() async throws {
        let probe = ReadProbe()
        let vm = readModel(probe, thread: try fixtureThread())
        await vm.loadThread(threadId: 67, token: probe.token)

        vm.updateVisibleMessages([501], threadId: 67, accountId: 1,
                                 token: probe.token, isForeground: false)
        await vm.acknowledgeVisibleMessages()
        XCTAssertTrue(probe.posts.isEmpty)

        probe.failPost = true
        vm.updateVisibleMessages([501], threadId: 67, accountId: 1,
                                 token: probe.token, isForeground: true)
        await vm.acknowledgeVisibleMessages()
        XCTAssertEqual(probe.posts, [[501]])
        XCTAssertEqual(probe.badgeRefreshes, 0)

        probe.failPost = false
        await vm.acknowledgeVisibleMessages()
        XCTAssertEqual(probe.posts, [[501], [501]])
        XCTAssertEqual(probe.badgeRefreshes, 1)
        await vm.acknowledgeVisibleMessages()
        XCTAssertEqual(probe.posts.count, 2)
    }

    func testNewArrivalDuringAcknowledgmentNeedsItsOwnVisibleRead() async throws {
        let probe = ReadProbe()
        var firstCompletion: CheckedContinuation<Void, Error>?
        let thread = try fixtureThread()
        let vm = SMSThreadViewModel(
            fetchThread: { _, _ in thread },
            postRead: { _, ids, _ in
                probe.posts.append(ids)
                if probe.posts.count == 1 {
                    try await withCheckedThrowingContinuation {
                        (continuation: CheckedContinuation<Void, Error>) in
                        firstCompletion = continuation
                    }
                }
            },
            refreshBadge: { probe.badgeRefreshes += 1 },
            currentIdentity: { (probe.accountId, probe.token) }
        )
        await vm.loadThread(threadId: 67, token: probe.token)
        vm.updateVisibleMessages([501], threadId: 67, accountId: 1,
                                 token: probe.token, isForeground: true)
        let first = Task { await vm.acknowledgeVisibleMessages() }
        for _ in 0..<1_000 where firstCompletion == nil { await Task.yield() }
        guard firstCompletion != nil else { XCTFail("read did not begin"); return }

        vm.messages.append(SMSMessageDTO(id: 502, threadId: 67, direction: "in",
                                         body: "new", createdAt: Date()))
        vm.messages.append(SMSMessageDTO(id: 498, threadId: 67, direction: "in",
                                         body: "older but unseen", createdAt: Date()))
        vm.updateVisibleMessages([501, 502], threadId: 67, accountId: 1,
                                 token: probe.token, isForeground: true)
        await vm.acknowledgeVisibleMessages()
        XCTAssertEqual(probe.posts, [[501]], "a second worker must not claim the same visible row")
        firstCompletion?.resume()
        await first.value

        XCTAssertEqual(probe.posts, [[501], [502]])
        XCTAssertEqual(probe.badgeRefreshes, 2)
        XCTAssertFalse(probe.posts.flatMap { $0 }.contains(498))
    }

    func testAccountSwitchDiscardsLateReadAndHistoryResponses() async throws {
        let probe = ReadProbe()
        var completion: CheckedContinuation<Void, Error>?
        let thread = try fixtureThread()
        let vm = SMSThreadViewModel(
            fetchThread: { _, _ in thread },
            postRead: { _, ids, _ in
                probe.posts.append(ids)
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in
                    completion = continuation
                }
            },
            refreshBadge: { probe.badgeRefreshes += 1 },
            currentIdentity: { (probe.accountId, probe.token) }
        )
        await vm.loadThread(threadId: 67, token: probe.token)
        vm.updateVisibleMessages([501], threadId: 67, accountId: 1,
                                 token: probe.token, isForeground: true)
        let read = Task { await vm.acknowledgeVisibleMessages() }
        for _ in 0..<1_000 where completion == nil { await Task.yield() }
        guard completion != nil else { XCTFail("read did not begin"); return }
        probe.accountId = 2
        probe.token = "other-account"
        vm.updateVisibleMessages([], threadId: nil, accountId: nil,
                                 token: nil, isForeground: false)
        completion?.resume()
        await read.value
        XCTAssertEqual(probe.posts, [[501]])
        XCTAssertEqual(probe.badgeRefreshes, 0)

        var loadCompletion: CheckedContinuation<SMSThreadDTO, Error>?
        let late = SMSThreadViewModel(
            fetchThread: { _, _ in
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<SMSThreadDTO, Error>) in
                    loadCompletion = continuation
                }
            },
            currentIdentity: { (probe.accountId, probe.token) }
        )
        let load = Task { await late.loadThread(threadId: 67, token: probe.token) }
        for _ in 0..<1_000 where loadCompletion == nil { await Task.yield() }
        guard loadCompletion != nil else { XCTFail("load did not begin"); return }
        probe.accountId = 3
        loadCompletion?.resume(returning: thread)
        await load.value
        XCTAssertTrue(late.messages.isEmpty)
    }

    func testSocketMessageCannotPopulateWrongThreadOrSwitchedAccount() async throws {
        let probe = ReadProbe()
        let vm = readModel(probe, thread: try fixtureThread())
        await vm.loadThread(threadId: 67, token: probe.token)
        let message: [String: Any] = [
            "id": 503, "threadId": 67, "direction": "in",
            "body": "synthetic socket message", "createdAt": "2026-11-15T12:02:00Z"
        ]
        func send(_ threadId: Int) {
            NotificationCenter.default.post(
                name: .socketSMSMessageNew, object: nil,
                userInfo: ["threadId": threadId, "message": message]
            )
        }

        send(68)
        probe.accountId = 2
        send(67)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertFalse(vm.messages.contains(where: { $0.id == 503 }))

        probe.accountId = 1
        send(67)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(vm.messages.contains(where: { $0.id == 503 }))
    }

    func testLoadThreadWithoutTokenSetsError() async {
        let vm = SMSThreadViewModel()

        await vm.loadThread(threadId: 1, token: nil)

        XCTAssertNotNil(vm.errorText)
        XCTAssertFalse(vm.isLoading)
    }

    func testSendTextMessageReturnsNilForBlankText() async {
        let vm = SMSThreadViewModel()

        let result = await vm.sendTextMessage(
            existingThreadId: 1,
            to: "+15551234567",
            text: "   ",
            token: "token"
        )

        XCTAssertNil(result)
        XCTAssertFalse(vm.isSending)
    }

    func testSendTextMessageWithoutTokenSetsError() async {
        let vm = SMSThreadViewModel()

        let result = await vm.sendTextMessage(
            existingThreadId: 1,
            to: "+15551234567",
            text: "Hello",
            token: nil
        )

        XCTAssertNil(result)
        XCTAssertNotNil(vm.errorText)
        XCTAssertFalse(vm.isSending)
    }

    func testSendMediaMessageReturnsNilForEmptyMediaUrls() async {
        let vm = SMSThreadViewModel()

        let result = await vm.sendMediaMessage(
            existingThreadId: 1,
            to: "+15551234567",
            mediaUrls: [],
            token: "token"
        )

        XCTAssertNil(result)
        XCTAssertFalse(vm.isSending)
    }

    func testSendMediaMessageWithoutTokenSetsError() async {
        let vm = SMSThreadViewModel()

        let result = await vm.sendMediaMessage(
            existingThreadId: 1,
            to: "+15551234567",
            mediaUrls: ["https://example.com/image.jpg"],
            token: nil
        )

        XCTAssertNil(result)
        XCTAssertNotNil(vm.errorText)
        XCTAssertFalse(vm.isSending)
    }

    func testResolvedTitleUsesConversationTitleWhenNoThread() {
        let vm = SMSThreadViewModel()

        let title = vm.resolvedTitle(
            fallback: "  Mom  ",
            fallbackPhone: "+15551234567"
        )

        XCTAssertEqual(title, "Mom")
    }

    func testResolvedTitleUsesFallbackPhoneWhenTitleBlank() {
        let vm = SMSThreadViewModel()

        let title = vm.resolvedTitle(
            fallback: "   ",
            fallbackPhone: "  +15551234567  "
        )

        XCTAssertEqual(title, "+15551234567")
    }

    func testResolvedTitleDefaultsToSMSWhenNoThreadTitleOrPhone() {
        let vm = SMSThreadViewModel()

        let title = vm.resolvedTitle(
            fallback: "   ",
            fallbackPhone: nil
        )

        XCTAssertEqual(title, "SMS")
    }

    func testResolvedPhoneUsesFallbackPhoneWhenNoThread() {
        let vm = SMSThreadViewModel()

        let phone = vm.resolvedPhone(
            fallback: "  +15551234567  "
        )

        XCTAssertEqual(phone, "+15551234567")
    }

    func testResolvedPhoneReturnsNilWhenNoThreadAndFallbackBlank() {
        let vm = SMSThreadViewModel()

        let phone = vm.resolvedPhone(
            fallback: "   "
        )

        XCTAssertNil(phone)
    }
}
