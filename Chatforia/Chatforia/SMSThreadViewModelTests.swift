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
        let cache = SMSConversationSnapshotCache()
        cache.activateAccount(probe.accountId)
        return SMSThreadViewModel(
            fetchThread: { _, _ in thread },
            postRead: { _, ids, _ in
                probe.posts.append(ids)
                if probe.failPost { throw URLError(.notConnectedToInternet) }
            },
            refreshBadge: { probe.badgeRefreshes += 1 },
            snapshotCache: cache,
            currentIdentity: { (probe.accountId, probe.token) }
        )
    }

    private func withMessages(_ thread: SMSThreadDTO,
                              _ messages: [SMSMessageDTO]) -> SMSThreadDTO {
        SMSThreadDTO(
            id: thread.id, userId: thread.userId, createdAt: thread.createdAt,
            updatedAt: thread.updatedAt, archivedAt: thread.archivedAt,
            contactPhone: thread.contactPhone, displayName: thread.displayName,
            contactName: thread.contactName, participants: thread.participants,
            messages: messages
        )
    }

    func testReopenShowsCachedHistoryBeforeDelayedOnlineRefresh() async throws {
        let probe = ReadProbe()
        let cache = SMSConversationSnapshotCache()
        cache.activateAccount(1)
        let initial = try fixtureThread()
        let first = SMSThreadViewModel(fetchThread: { _, _ in initial },
                                       snapshotCache: cache,
                                       currentIdentity: { (probe.accountId, probe.token) })
        await first.loadThread(threadId: 67, token: probe.token)

        var completion: CheckedContinuation<SMSThreadDTO, Error>?
        let reopened = SMSThreadViewModel(
            fetchThread: { _, _ in
                try await withCheckedThrowingContinuation { completion = $0 }
            }, snapshotCache: cache,
            currentIdentity: { (probe.accountId, probe.token) }
        )
        let refresh = Task { await reopened.loadThread(threadId: 67, token: probe.token) }
        for _ in 0..<1_000 where completion == nil { await Task.yield() }
        XCTAssertNotNil(completion)
        XCTAssertEqual(reopened.messages.map(\.id), [499, 501, 500])
        XCTAssertFalse(reopened.isLoading)
        let newest = SMSMessageDTO(id: 502, threadId: 67, direction: "in", body: "new",
                                   createdAt: initial.messages[1].createdAt.addingTimeInterval(60))
        completion?.resume(returning: withMessages(initial, initial.messages + [newest]))
        await refresh.value
        XCTAssertEqual(Set(reopened.messages.map(\.id)), Set([499, 500, 501, 502]))
    }

    func testOfflineRefreshRetainsCachedHistoryAndAccountSwitchClearsIt() async throws {
        let probe = ReadProbe()
        let cache = SMSConversationSnapshotCache()
        cache.activateAccount(1)
        let initial = try fixtureThread()
        let first = SMSThreadViewModel(fetchThread: { _, _ in initial },
                                       snapshotCache: cache,
                                       currentIdentity: { (probe.accountId, probe.token) })
        await first.loadThread(threadId: 67, token: probe.token)
        let reopened = SMSThreadViewModel(
            fetchThread: { _, _ in throw URLError(.notConnectedToInternet) },
            snapshotCache: cache,
            currentIdentity: { (probe.accountId, probe.token) }
        )
        await reopened.loadThread(threadId: 67, token: probe.token)
        XCTAssertEqual(reopened.messages.count, 3)
        XCTAssertNotNil(reopened.errorText)
        probe.accountId = 2
        probe.token = "other-account"
        cache.activateAccount(2)
        XCTAssertNil(cache.snapshot(accountId: 1, threadId: 67))
        await reopened.loadThread(threadId: 67, token: probe.token)
        XCTAssertTrue(reopened.messages.isEmpty)
        cache.clear()
        XCTAssertNil(cache.snapshot(accountId: 2, threadId: 67))
    }

    func testAuthorizationFailurePurgesCachedHistoryAndVisibleRows() async throws {
        let probe = ReadProbe()
        let cache = SMSConversationSnapshotCache()
        cache.activateAccount(1)
        let initial = try fixtureThread()
        let first = SMSThreadViewModel(fetchThread: { _, _ in initial },
                                       snapshotCache: cache,
                                       currentIdentity: { (probe.accountId, probe.token) })
        await first.loadThread(threadId: 67, token: probe.token)
        let reopened = SMSThreadViewModel(
            fetchThread: { _, _ in throw APIError.unauthorized },
            snapshotCache: cache,
            currentIdentity: { (probe.accountId, probe.token) }
        )
        await reopened.loadThread(threadId: 67, token: probe.token)
        XCTAssertTrue(reopened.messages.isEmpty)
        XCTAssertNil(reopened.thread)
        XCTAssertNil(cache.snapshot(accountId: 1, threadId: 67))
    }

    func testForbiddenRefreshAlsoPurgesPreviouslyVisibleSnapshot() async throws {
        let probe = ReadProbe()
        let cache = SMSConversationSnapshotCache()
        cache.activateAccount(1)
        let initial = try fixtureThread()
        cache.store(thread: initial, messages: initial.sortedMessages, accountId: 1)
        let vm = SMSThreadViewModel(
            fetchThread: { _, _ in
                throw APIError.server(status: 403, code: nil, message: nil, body: nil)
            }, snapshotCache: cache,
            currentIdentity: { (probe.accountId, probe.token) }
        )
        await vm.loadThread(threadId: 67, token: probe.token)
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertNil(cache.snapshot(accountId: 1, threadId: 67))
    }

    func testSwitchingThreadNeverDisplaysPriorThreadOnOfflineFailure() async throws {
        let probe = ReadProbe()
        let cache = SMSConversationSnapshotCache()
        cache.activateAccount(1)
        let initial = try fixtureThread()
        let vm = SMSThreadViewModel(
            fetchThread: { id, _ in
                if id == 67 { return initial }
                throw URLError(.notConnectedToInternet)
            }, snapshotCache: cache,
            currentIdentity: { (probe.accountId, probe.token) }
        )
        await vm.loadThread(threadId: 67, token: probe.token)
        XCTAssertEqual(vm.messages.count, 3)
        await vm.loadThread(threadId: 68, token: probe.token)
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertNil(vm.thread)
        XCTAssertNotNil(cache.snapshot(accountId: 1, threadId: 67))
    }

    func testPreviousAccountDelayedResponseCannotRepopulateClearedCache() async throws {
        let probe = ReadProbe()
        let cache = SMSConversationSnapshotCache()
        cache.activateAccount(1)
        var completion: CheckedContinuation<SMSThreadDTO, Error>?
        let vm = SMSThreadViewModel(
            fetchThread: { _, _ in
                try await withCheckedThrowingContinuation { completion = $0 }
            }, snapshotCache: cache,
            currentIdentity: { (probe.accountId, probe.token) }
        )
        let load = Task { await vm.loadThread(threadId: 67, token: probe.token) }
        for _ in 0..<1_000 where completion == nil { await Task.yield() }
        XCTAssertNotNil(completion)
        probe.accountId = 2
        probe.token = "other-account"
        cache.activateAccount(2)
        completion?.resume(returning: try fixtureThread())
        await load.value
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertNil(cache.snapshot(accountId: 1, threadId: 67))
        XCTAssertNil(cache.snapshot(accountId: 2, threadId: 67))
    }

    func testIncomingDuringRefreshSurvivesOlderServerWindowWithoutDuplicates() async throws {
        let probe = ReadProbe()
        let cache = SMSConversationSnapshotCache()
        cache.activateAccount(1)
        let initial = try fixtureThread()
        let first = SMSThreadViewModel(fetchThread: { _, _ in initial },
                                       snapshotCache: cache,
                                       currentIdentity: { (probe.accountId, probe.token) })
        await first.loadThread(threadId: 67, token: probe.token)
        var completion: CheckedContinuation<SMSThreadDTO, Error>?
        let reopened = SMSThreadViewModel(
            fetchThread: { _, _ in
                try await withCheckedThrowingContinuation { completion = $0 }
            }, snapshotCache: cache,
            currentIdentity: { (probe.accountId, probe.token) }
        )
        let refresh = Task { await reopened.loadThread(threadId: 67, token: probe.token) }
        for _ in 0..<1_000 where completion == nil { await Task.yield() }
        XCTAssertNotNil(completion)
        let arrival: [String: Any] = [
            "id": 503, "threadId": 67, "direction": "in", "body": "during refresh",
            "createdAt": "2026-11-15T12:03:00Z"
        ]
        NotificationCenter.default.post(name: .socketSMSMessageNew, object: nil,
                                        userInfo: ["threadId": 67, "message": arrival])
        for _ in 0..<1_000 where !reopened.messages.contains(where: { $0.id == 503 }) {
            await Task.yield()
        }
        XCTAssertEqual(reopened.messages.filter { $0.id == 503 }.count, 1)
        completion?.resume(returning: initial)
        await refresh.value
        XCTAssertEqual(reopened.messages.filter { $0.id == 503 }.count, 1)
        XCTAssertEqual(reopened.messages.map(\.id), [499, 501, 500, 503])
        XCTAssertEqual(cache.snapshot(accountId: 1, threadId: 67)?.messages.map(\.id),
                       [499, 501, 500, 503])
    }

    func testStaleSocketEventDuringRefreshCannotRestoreServerOmittedRow() async throws {
        let probe = ReadProbe()
        let cache = SMSConversationSnapshotCache()
        cache.activateAccount(1)
        let initial = try fixtureThread()
        cache.store(thread: initial, messages: initial.sortedMessages, accountId: 1)
        var completion: CheckedContinuation<SMSThreadDTO, Error>?
        let vm = SMSThreadViewModel(
            fetchThread: { _, _ in
                try await withCheckedThrowingContinuation { completion = $0 }
            }, snapshotCache: cache,
            currentIdentity: { (probe.accountId, probe.token) }
        )
        let refresh = Task { await vm.loadThread(threadId: 67, token: probe.token) }
        for _ in 0..<1_000 where completion == nil { await Task.yield() }
        XCTAssertNotNil(completion)
        NotificationCenter.default.post(name: .socketSMSMessageNew, object: nil,
                                        userInfo: ["threadId": 67, "message": [
                                            "id": 499, "threadId": 67, "direction": "in",
                                            "body": "stale event",
                                            "createdAt": "2026-11-15T11:59:00Z"
                                        ]])
        for _ in 0..<1_000 where vm.messages.first(where: { $0.id == 499 })?.body !=
            "stale event" { await Task.yield() }
        completion?.resume(returning: withMessages(initial,
            initial.messages.filter { $0.id != 499 }))
        await refresh.value
        XCTAssertFalse(vm.messages.contains { $0.id == 499 })
        XCTAssertFalse(cache.snapshot(accountId: 1, threadId: 67)?.messages.contains {
            $0.id == 499
        } ?? true)
    }

    func testServerOmissionRemovesCachedRowAndOlderRevisionCannotUndoEdit() async throws {
        let probe = ReadProbe()
        let cache = SMSConversationSnapshotCache()
        cache.activateAccount(1)
        let initial = try fixtureThread()
        let original = try XCTUnwrap(initial.messages.first { $0.id == 501 })
        let edited = SMSMessageDTO(
            id: original.id, threadId: 67, direction: "in", body: "newer edit",
            createdAt: original.createdAt,
            editedAt: original.createdAt.addingTimeInterval(120)
        )
        cache.store(thread: initial,
                    messages: initial.messages.map { $0.id == 501 ? edited : $0 },
                    accountId: 1)
        let vm = SMSThreadViewModel(fetchThread: { _, _ in initial },
                                    snapshotCache: cache,
                                    currentIdentity: { (probe.accountId, probe.token) })
        await vm.loadThread(threadId: 67, token: probe.token)
        XCTAssertEqual(vm.messages.first(where: { $0.id == 501 })?.body, "newer edit")

        let withoutRemoved = withMessages(initial, initial.messages.filter { $0.id != 499 })
        let later = SMSThreadViewModel(fetchThread: { _, _ in withoutRemoved },
                                       snapshotCache: cache,
                                       currentIdentity: { (probe.accountId, probe.token) })
        await later.loadThread(threadId: 67, token: probe.token)
        XCTAssertFalse(later.messages.contains { $0.id == 499 })
        XCTAssertFalse(cache.snapshot(accountId: 1, threadId: 67)?.messages.contains {
            $0.id == 499
        } ?? true)
    }

    func testAcceptedOptimisticSendIsKeptOnRefreshFailureThenReplacedOnce() async throws {
        let probe = ReadProbe()
        let cache = SMSConversationSnapshotCache()
        cache.activateAccount(1)
        let initial = try fixtureThread()
        let canonical = SMSMessageDTO(
            id: 504, threadId: 67, direction: "out", body: "sent while offline",
            providerMessageId: "SM504",
            createdAt: Date()
        )
        var failRefresh = true
        let vm = SMSThreadViewModel(
            fetchThread: { _, _ in
                if failRefresh { throw URLError(.notConnectedToInternet) }
                return self.withMessages(initial, initial.messages + [canonical])
            }, snapshotCache: cache,
            currentIdentity: { (probe.accountId, probe.token) }
        )
        let optimistic = SMSMessageDTO.optimisticOutgoing(
            threadId: -1, to: "+15550000000", body: "sent while offline"
        )
        vm.messages = [optimistic]
        await vm.loadThread(threadId: 67, token: probe.token,
                            acceptedOptimisticId: optimistic.id,
                            acceptedProviderMessageId: "SM504")
        XCTAssertEqual(vm.messages.map(\.id), [optimistic.id])

        NotificationCenter.default.post(name: .socketSMSMessageNew, object: nil,
                                        userInfo: ["threadId": 67, "message": [
                                            "id": 504, "threadId": 67, "direction": "out",
                                            "body": "sent while offline", "providerMessageId": "SM504",
                                            "createdAt": "2026-11-22T12:00:00Z"
                                        ]])
        for _ in 0..<1_000 where vm.messages.contains(where: { $0.id == optimistic.id }) {
            await Task.yield()
        }
        XCTAssertFalse(vm.messages.contains { $0.id == optimistic.id })
        XCTAssertEqual(vm.messages.filter { $0.id == 504 }.count, 1)

        failRefresh = false
        await vm.loadThread(threadId: 67, token: probe.token)
        XCTAssertEqual(vm.messages.filter { $0.id == 504 }.count, 1)
        XCTAssertFalse(vm.messages.contains { $0.id == optimistic.id })
        XCTAssertEqual(cache.snapshot(accountId: 1, threadId: 67)?.messages.filter {
            $0.id == 504
        }.count, 1)
    }

    func testAcceptedOptimisticSendIsRemovedWhenCanonicalHistoryArrives() async throws {
        let probe = ReadProbe()
        let cache = SMSConversationSnapshotCache()
        cache.activateAccount(1)
        let initial = try fixtureThread()
        let canonical = SMSMessageDTO(id: 504, threadId: 67, direction: "out",
                                      body: "sent", createdAt: Date())
        let vm = SMSThreadViewModel(
            fetchThread: { _, _ in self.withMessages(initial, initial.messages + [canonical]) },
            snapshotCache: cache,
            currentIdentity: { (probe.accountId, probe.token) }
        )
        let optimistic = SMSMessageDTO.optimisticOutgoing(
            threadId: 67, to: "+15550000000", body: "sent"
        )
        vm.messages = [optimistic]
        await vm.loadThread(threadId: 67, token: probe.token,
                            acceptedOptimisticId: optimistic.id)
        XCTAssertEqual(vm.messages.filter { $0.id == 504 }.count, 1)
        XCTAssertFalse(vm.messages.contains { $0.id == optimistic.id })
    }

    func testOutOfOrderSocketEventCannotReplaceNewerCachedEdit() async throws {
        let probe = ReadProbe()
        let cache = SMSConversationSnapshotCache()
        cache.activateAccount(1)
        let initial = try fixtureThread()
        let vm = SMSThreadViewModel(fetchThread: { _, _ in initial },
                                    snapshotCache: cache,
                                    currentIdentity: { (probe.accountId, probe.token) })
        await vm.loadThread(threadId: 67, token: probe.token)
        let newer: [String: Any] = [
            "id": 501, "threadId": 67, "direction": "in", "body": "newer edit",
            "createdAt": "2026-11-15T12:00:00Z", "editedAt": "2026-11-15T12:05:00Z"
        ]
        let stale: [String: Any] = [
            "id": 501, "threadId": 67, "direction": "in", "body": "older edit",
            "createdAt": "2026-11-15T12:00:00Z", "editedAt": "2026-11-15T12:03:00Z"
        ]
        for payload in [newer, stale] {
            NotificationCenter.default.post(name: .socketSMSMessageNew, object: nil,
                                            userInfo: ["threadId": 67, "message": payload])
            for _ in 0..<1_000 where vm.messages.first(where: { $0.id == 501 })?.body !=
                "newer edit" { await Task.yield() }
        }
        XCTAssertEqual(vm.messages.first(where: { $0.id == 501 })?.body, "newer edit")
        XCTAssertEqual(cache.snapshot(accountId: 1, threadId: 67)?.messages.first {
            $0.id == 501
        }?.body, "newer edit")
    }

    func testSnapshotBoundedAndLocalDeletionCannotResurrect() throws {
        let cache = SMSConversationSnapshotCache()
        cache.activateAccount(1)
        let thread = try fixtureThread()
        cache.store(thread: thread, messages: thread.sortedMessages, accountId: 1,
                    now: Date(timeIntervalSince1970: 1_000))
        XCTAssertNil(cache.snapshot(accountId: 1, threadId: 67,
                                    now: Date(timeIntervalSince1970: 1_000 + 1_201)))
        cache.store(thread: thread, messages: thread.sortedMessages, accountId: 1)
        cache.removeMessage(501, accountId: 1, threadId: 67)
        cache.store(thread: thread, messages: thread.sortedMessages, accountId: 1)
        XCTAssertEqual(cache.snapshot(accountId: 1, threadId: 67)?.messages.map(\.id), [499, 500])

        let rows = (1...205).map { index in
            SMSMessageDTO(id: index, threadId: 67, direction: "in", body: "row",
                          createdAt: Date(timeIntervalSince1970: Double(index)))
        }
        cache.store(thread: thread, messages: rows, accountId: 1)
        XCTAssertEqual(cache.snapshot(accountId: 1, threadId: 67)?.messages.count, 200)
        XCTAssertEqual(cache.snapshot(accountId: 1, threadId: 67)?.messages.first?.id, 6)
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

@MainActor
private final class AssignedNumberSnapshotProbe: AssignedNumberSnapshotStoring {
    private var values: [String: AssignedNumberDTO] = [:]
    private func key(_ userId: Int, _ token: String) -> String { "\(userId):\(token)" }
    func number(userId: Int, token: String) -> AssignedNumberDTO? {
        values[key(userId, token)]
    }
    func save(_ number: AssignedNumberDTO, userId: Int, token: String) {
        values[key(userId, token)] = number
    }
    func clear() { values.removeAll() }
}

@MainActor
private final class AssignedNumberFetchProbe {
    var pending: [String: CheckedContinuation<MyAssignedNumberDTO, Error>] = [:]
    func fetch(_ token: String?) async throws -> MyAssignedNumberDTO {
        try await withCheckedThrowingContinuation { continuation in
            pending[token ?? ""] = continuation
        }
    }
}

@MainActor
final class PhoneNumberOfflineTests: XCTestCase {
    private func assigned(_ digits: String) -> AssignedNumberDTO {
        AssignedNumberDTO(e164: digits, status: "ASSIGNED", capabilities: nil,
                          keepLocked: true, releaseAfter: nil, holdUntil: nil)
    }

    func testLastKnownNumberPersistsAcrossStoreInstancesOnlyForSameAccountAndToken() {
        let service = "com.chatforia.qa.assigned-number.\(UUID().uuidString)"
        let account = "synthetic-assignment"
        let first = OfflineAssignedNumberStore(service: service, account: account)
        defer { first.clear() }
        first.save(assigned("+15550000001"), userId: 1, token: "account-a")
        let reopened = OfflineAssignedNumberStore(service: service, account: account)
        XCTAssertEqual(reopened.number(userId: 1, token: "account-a")?.e164, "+15550000001")
        XCTAssertNil(reopened.number(userId: 2, token: "account-a"))
        XCTAssertNil(reopened.number(userId: 1, token: "account-b"))
    }

    func testOfflineStartupPreservesOnlyMatchingLastKnownNumberWithoutPicker() async {
        let cache = AssignedNumberSnapshotProbe()
        cache.save(assigned("+15550000001"), userId: 1, token: "account-a")
        let vm = PhoneNumberViewModel(
            fetchNumber: { _ in throw URLError(.notConnectedToInternet) },
            snapshotStore: cache,
            accountIsCurrent: { _, _ in true }
        )
        await vm.loadCurrentNumber(token: "account-a", accountId: 1)
        XCTAssertEqual(vm.lookupState, .unavailable)
        XCTAssertEqual(vm.lastKnownNumber?.e164, "+15550000001")
        XCTAssertNil(vm.currentNumber)
        XCTAssertFalse(vm.canPickNumber)

        await vm.loadCurrentNumber(token: "account-b", accountId: 2)
        XCTAssertEqual(vm.lookupState, .unavailable)
        XCTAssertNil(vm.lastKnownNumber)
        XCTAssertFalse(vm.canPickNumber)
    }

    func testReconnectionVerifiesAssignmentAndOnlyConfirmedNullEnablesPicker() async {
        let cache = AssignedNumberSnapshotProbe()
        cache.save(assigned("+15550000001"), userId: 1, token: "account-a")
        var responses = 0
        let vm = PhoneNumberViewModel(
            fetchNumber: { _ in
                responses += 1
                if responses == 1 { throw URLError(.notConnectedToInternet) }
                if responses == 2 { return MyAssignedNumberDTO(number: self.assigned("+15550000001")) }
                return MyAssignedNumberDTO(number: nil)
            },
            snapshotStore: cache,
            accountIsCurrent: { _, _ in true }
        )
        await vm.loadCurrentNumber(token: "account-a", accountId: 1)
        XCTAssertEqual(vm.lookupState, .unavailable)
        await vm.loadCurrentNumber(token: "account-a", accountId: 1)
        XCTAssertEqual(vm.lookupState, .verifiedAssigned)
        XCTAssertEqual(vm.currentNumber?.e164, "+15550000001")
        XCTAssertFalse(vm.canPickNumber)
        await vm.loadCurrentNumber(token: "account-a", accountId: 1)
        XCTAssertEqual(vm.lookupState, .verifiedUnassigned)
        XCTAssertNil(vm.currentNumber)
        XCTAssertNil(cache.number(userId: 1, token: "account-a"))
        XCTAssertTrue(vm.canPickNumber)
    }

    func testLateResponseFromPreviousAccountCannotReplaceCurrentNumber() async {
        let cache = AssignedNumberSnapshotProbe()
        let fetch = AssignedNumberFetchProbe()
        var activeToken = "account-a"
        var activeId = 1
        let vm = PhoneNumberViewModel(
            fetchNumber: { try await fetch.fetch($0) },
            snapshotStore: cache,
            accountIsCurrent: { token, id in token == activeToken && id == activeId }
        )
        let old = Task { await vm.loadCurrentNumber(token: "account-a", accountId: 1) }
        for _ in 0..<100 where fetch.pending["account-a"] == nil { await Task.yield() }
        XCTAssertNotNil(fetch.pending["account-a"])
        activeToken = "account-b"
        activeId = 2
        let current = Task { await vm.loadCurrentNumber(token: "account-b", accountId: 2) }
        for _ in 0..<100 where fetch.pending["account-b"] == nil { await Task.yield() }
        XCTAssertNotNil(fetch.pending["account-b"])
        fetch.pending["account-b"]?.resume(returning: MyAssignedNumberDTO(number: assigned("+15550000002")))
        await current.value
        fetch.pending["account-a"]?.resume(returning: MyAssignedNumberDTO(number: assigned("+15550000001")))
        await old.value
        XCTAssertEqual(vm.currentNumber?.e164, "+15550000002")
        XCTAssertEqual(vm.lookupState, .verifiedAssigned)
        XCTAssertNil(cache.number(userId: 1, token: "account-a"))
    }
}
