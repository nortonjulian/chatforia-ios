import XCTest
@testable import Chatforia

@MainActor
final class SMSIncomingTranslationStoreTests: XCTestCase {
    private let incoming = SMSMessageDTO(
        id: 501, threadId: 67, direction: "in", body: "Hello", createdAt: Date()
    )
    private let outgoing = SMSMessageDTO(
        id: 502, threadId: 67, direction: "out", body: "Sent", createdAt: Date()
    )

    private func context(account: Int = 1, thread: Int = 67,
                         language: String = "es", enabled: Bool = true,
                         showOriginal: Bool = false) -> SMSIncomingTranslationContext {
        SMSIncomingTranslationContext(accountId: account, token: "token-\(account)",
                                      threadId: thread, language: language,
                                      autoTranslate: enabled,
                                      showOriginalWithTranslation: showOriginal)!
    }

    private func translated(_ message: SMSMessageDTO, language: String = "es") -> SMSIncomingTranslationResponse {
        SMSIncomingTranslationResponse(messageId: message.id,
                                       originalText: message.body ?? "", translatedText: "Hola",
                                       displayText: "Hola", targetLanguage: language,
                                       showOriginalWithTranslation: false,
                                       status: "translated", reason: nil)
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func testRequestUsesAuthenticatedMessageEndpoint() {
        let request = SMSIncomingTranslationStore.request(messageId: 501)
        XCTAssertEqual(request.path, "sms/messages/501/translation")
        XCTAssertEqual(request.method.rawValue, "POST")
        XCTAssertTrue(request.requiresAuth)
        XCTAssertNil(request.body)
    }

    func testTranslatedDisplayPreservesOriginalAndAvoidsDuplicateOrOffscreenRequests() async {
        var ids: [Int] = []
        let store = SMSIncomingTranslationStore(cache: SMSIncomingTranslationCache(), fetch: { [self] id, _ in
            ids.append(id)
            return translated(incoming)
        })
        let current = context()
        store.update(messages: [incoming, outgoing], visibleIds: [501, 502],
                     context: current, isForeground: true, identityMatches: { true })
        await settle()
        XCTAssertEqual(ids, [501])
        XCTAssertEqual(store.translatedText(for: incoming, context: current), "Hola")
        XCTAssertNil(store.translatedText(for: outgoing, context: current))
        XCTAssertEqual(incoming.body, "Hello")
        store.update(messages: [incoming, outgoing], visibleIds: [501, 502],
                     context: current, isForeground: true, identityMatches: { true })
        await settle()
        XCTAssertEqual(ids, [501])
    }

    func testPendingRetriesAreBoundedAndOriginalRemainsVisibleUntilSuccess() async {
        var attempts = 0
        let store = SMSIncomingTranslationStore(cache: SMSIncomingTranslationCache(), fetch: { [self] _, _ in
            attempts += 1
            if attempts < 3 {
                return SMSIncomingTranslationResponse(messageId: 501, originalText: "Hello",
                    translatedText: nil, displayText: "Hello", targetLanguage: "es",
                    showOriginalWithTranslation: false, status: "original", reason: "pending")
            }
            return translated(incoming)
        }, delay: { _ in })
        let current = context()
        XCTAssertEqual(store.presentation(for: incoming, context: current), .pending)
        store.update(messages: [incoming], visibleIds: [501], context: current,
                     isForeground: true, identityMatches: { true })
        XCTAssertNil(store.translatedText(for: incoming, context: current))
        await settle()
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(store.translatedText(for: incoming, context: current), "Hola")

        var bounded = 0
        let pending = SMSIncomingTranslationStore(cache: SMSIncomingTranslationCache(), fetch: { _, _ in
            bounded += 1
            return SMSIncomingTranslationResponse(messageId: 501, originalText: "Hello",
                translatedText: nil, displayText: "Hello", targetLanguage: "es",
                showOriginalWithTranslation: false, status: "original", reason: "pending")
        }, delay: { _ in })
        pending.update(messages: [incoming], visibleIds: [501], context: current,
                       isForeground: true, identityMatches: { true })
        await settle()
        XCTAssertEqual(bounded, 3)
        XCTAssertNil(pending.translatedText(for: incoming, context: current))
    }

    func testFailureAndDisabledPreferenceKeepOriginalWithoutExtraCalls() async {
        var calls = 0
        let store = SMSIncomingTranslationStore(cache: SMSIncomingTranslationCache(), fetch: { _, _ in
            calls += 1
            throw URLError(.notConnectedToInternet)
        })
        let current = context()
        store.update(messages: [incoming], visibleIds: [501], context: current,
                     isForeground: true, identityMatches: { true })
        await settle()
        XCTAssertNil(store.translatedText(for: incoming, context: current))
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.presentation(for: incoming, context: current), .original)
        store.update(messages: [incoming], visibleIds: [501], context: current,
                     isForeground: true, identityMatches: { true })
        await settle()
        XCTAssertEqual(calls, 1)
        store.update(messages: [incoming], visibleIds: [501], context: context(enabled: false),
                     isForeground: true, identityMatches: { true })
        XCTAssertNil(store.translatedText(for: incoming, context: current))
        XCTAssertEqual(calls, 1)
    }

    func testBackendOriginalFallbackNeverReplacesStoredSMSBody() async {
        let store = SMSIncomingTranslationStore(cache: SMSIncomingTranslationCache(), fetch: { _, _ in
            SMSIncomingTranslationResponse(messageId: 501, originalText: "Hello",
                translatedText: nil, displayText: "Hello", targetLanguage: "es",
                showOriginalWithTranslation: false, status: "original",
                reason: "allowance_exhausted")
        })
        let current = context()
        store.update(messages: [incoming], visibleIds: [501], context: current,
                     isForeground: true, identityMatches: { true })
        await settle()
        XCTAssertNil(store.translatedText(for: incoming, context: current))
        XCTAssertEqual(incoming.body, "Hello")
    }

    func testLanguageAndShowOriginalChangeDiscardOldTranslation() async {
        var requests: [String] = []
        let store = SMSIncomingTranslationStore(cache: SMSIncomingTranslationCache(), fetch: { [self] _, token in
            requests.append(token)
            return translated(incoming, language: requests.count == 1 ? "es" : "fr")
        })
        let spanish = context()
        store.update(messages: [incoming], visibleIds: [501], context: spanish,
                     isForeground: true, identityMatches: { true })
        await settle()
        XCTAssertEqual(store.translatedText(for: incoming, context: spanish), "Hola")

        let french = context(language: "fr", showOriginal: true)
        store.update(messages: [incoming], visibleIds: [501], context: french,
                     isForeground: true, identityMatches: { true })
        XCTAssertNil(store.translatedText(for: incoming, context: spanish))
        await settle()
        XCTAssertEqual(store.translatedText(for: incoming, context: french), "Hola")
        XCTAssertTrue(french.showOriginalWithTranslation)
        XCTAssertEqual(requests.count, 2)
    }

    func testAccountThreadAndLateResponsesCannotCrossContexts() async {
        var resume: CheckedContinuation<SMSIncomingTranslationResponse, Never>?
        let store = SMSIncomingTranslationStore(cache: SMSIncomingTranslationCache(), fetch: { [self] id, _ in
            if id == 501 {
                return await withCheckedContinuation { resume = $0 }
            }
            return translated(incoming)
        })
        let first = context()
        store.update(messages: [incoming], visibleIds: [501], context: first,
                     isForeground: true, identityMatches: { true })
        await settle()
        XCTAssertNotNil(resume)
        let otherAccount = context(account: 2)
        store.update(messages: [], visibleIds: [], context: otherAccount,
                     isForeground: true, identityMatches: { true })
        resume?.resume(returning: translated(incoming))
        await settle()
        XCTAssertNil(store.translatedText(for: incoming, context: first))
        XCTAssertNil(store.translatedText(for: incoming, context: otherAccount))
        let otherThread = context(thread: 68)
        store.update(messages: [incoming], visibleIds: [501], context: otherThread,
                     isForeground: true, identityMatches: { true })
        await settle()
        XCTAssertNil(store.translatedText(for: incoming, context: otherThread))
    }

    func testBackgroundAndOffscreenRowsDoNotStartTranslation() async {
        var calls = 0
        let store = SMSIncomingTranslationStore(cache: SMSIncomingTranslationCache(), fetch: { [self] _, _ in
            calls += 1
            return translated(incoming)
        })
        let current = context()
        store.update(messages: [incoming], visibleIds: [501], context: current,
                     isForeground: false, identityMatches: { true })
        store.update(messages: [incoming], visibleIds: [], context: current,
                     isForeground: true, identityMatches: { true })
        await settle()
        XCTAssertEqual(calls, 0)
    }

    func testChangedMessageBodyInvalidatesAnInFlightResult() async {
        var resumeOld: CheckedContinuation<SMSIncomingTranslationResponse, Never>?
        var calls = 0
        let edited = SMSMessageDTO(id: 501, threadId: 67, direction: "in",
                                   body: "Updated", createdAt: incoming.createdAt)
        let store = SMSIncomingTranslationStore(cache: SMSIncomingTranslationCache(), fetch: { [self] _, _ in
            calls += 1
            if calls == 1 {
                return await withCheckedContinuation { resumeOld = $0 }
            }
            return SMSIncomingTranslationResponse(messageId: 501, originalText: "Updated",
                translatedText: "Actualizado", displayText: "Actualizado",
                targetLanguage: "es", showOriginalWithTranslation: false,
                status: "translated", reason: nil)
        })
        let current = context()
        store.update(messages: [incoming], visibleIds: [501], context: current,
                     isForeground: true, identityMatches: { true })
        await settle()
        XCTAssertNotNil(resumeOld)
        store.update(messages: [edited], visibleIds: [501], context: current,
                     isForeground: true, identityMatches: { true })
        resumeOld?.resume(returning: translated(incoming))
        await settle()
        XCTAssertEqual(calls, 2)
        XCTAssertNil(store.translatedText(for: incoming, context: current))
        XCTAssertEqual(store.translatedText(for: edited, context: current), "Actualizado")
    }

    func testCacheReusesTranslationImmediatelyAfterReopeningButIsolatesAccountAndLanguage() async {
        let cache = SMSIncomingTranslationCache()
        let current = context()
        let first = SMSIncomingTranslationStore(cache: cache, fetch: { [self] _, _ in
            translated(incoming)
        })
        first.update(messages: [incoming], visibleIds: [501], context: current,
                     isForeground: true, identityMatches: { true })
        await settle()
        XCTAssertEqual(first.presentation(for: incoming, context: current), .translated("Hola"))
        first.reset()

        var repeatedCalls = 0
        let reopened = SMSIncomingTranslationStore(cache: cache, fetch: { [self] _, _ in
            repeatedCalls += 1
            return translated(incoming)
        })
        XCTAssertEqual(reopened.presentation(for: incoming, context: current), .translated("Hola"))
        reopened.update(messages: [incoming], visibleIds: [501], context: current,
                        isForeground: true, identityMatches: { true })
        await settle()
        XCTAssertEqual(repeatedCalls, 0)
        XCTAssertEqual(reopened.presentation(for: incoming, context: context(account: 2)), .pending)
        XCTAssertEqual(reopened.presentation(for: incoming, context: context(language: "fr")), .pending)
        XCTAssertEqual(reopened.presentation(for: incoming, context: context(enabled: false)), .original)
    }

    func testSyntheticColdLatencyAndWarmCacheHitOnThreadReopen() async {
        let cache = SMSIncomingTranslationCache()
        let current = context()
        let completed = expectation(description: "mock translation completed")
        var fetches = 0
        let cold = SMSIncomingTranslationStore(cache: cache, fetch: { [self] _, _ in
            fetches += 1
            try await Task.sleep(nanoseconds: 150_000_000)
            completed.fulfill()
            return translated(incoming)
        })
        let started = ProcessInfo.processInfo.systemUptime
        cold.update(messages: [incoming], visibleIds: [501], context: current,
                    isForeground: true, identityMatches: { true })
        XCTAssertEqual(cold.presentation(for: incoming, context: current), .pending)
        await fulfillment(of: [completed], timeout: 3)
        await settle()
        let coldMilliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        XCTAssertEqual(cold.presentation(for: incoming, context: current), .translated("Hola"))
        XCTAssertEqual(fetches, 1)

        let reopened = SMSIncomingTranslationStore(cache: cache, fetch: { [self] _, _ in
            fetches += 1
            return translated(incoming)
        })
        let warmStarted = ProcessInfo.processInfo.systemUptime
        XCTAssertEqual(reopened.presentation(for: incoming, context: current), .translated("Hola"))
        reopened.update(messages: [incoming], visibleIds: [501], context: current,
                        isForeground: true, identityMatches: { true })
        await settle()
        let warmMilliseconds = (ProcessInfo.processInfo.systemUptime - warmStarted) * 1_000
        XCTAssertEqual(fetches, 1, "a warm thread must not request translation again")
        print(String(format: "SMS_SYNTHETIC_LATENCY cold_ms=%.1f warm_ms=%.1f fetches=%d",
                     coldMilliseconds, warmMilliseconds, fetches))
    }

    func testPreviewTranslationWithTrimmedBodyReusesCacheInThreadWithExactOriginal() async {
        let cache = SMSIncomingTranslationCache()
        let preview = SMSIncomingTranslationStore(allowTrimmedOriginal: true, cache: cache,
            fetch: { _, _ in
                SMSIncomingTranslationResponse(messageId: 501, originalText: " Hello ",
                    translatedText: "Hola", displayText: "Hola", targetLanguage: "es",
                    showOriginalWithTranslation: false, status: "translated", reason: nil)
            })
        let current = context()
        preview.update(messages: [incoming], visibleIds: [501], context: current,
                       isForeground: true, identityMatches: { true })
        await settle()
        XCTAssertEqual(preview.presentation(for: incoming, context: current), .translated("Hola"))

        var repeatedCalls = 0
        let threadMessage = SMSMessageDTO(id: 501, threadId: 67, direction: "in",
                                          body: " Hello ", createdAt: incoming.createdAt)
        let thread = SMSIncomingTranslationStore(cache: cache, fetch: { _, _ in
            repeatedCalls += 1
            throw URLError(.badServerResponse)
        })
        XCTAssertEqual(thread.presentation(for: threadMessage, context: current), .translated("Hola"))
        thread.update(messages: [threadMessage], visibleIds: [501], context: current,
                      isForeground: true, identityMatches: { true })
        await settle()
        XCTAssertEqual(repeatedCalls, 0)
    }
}
