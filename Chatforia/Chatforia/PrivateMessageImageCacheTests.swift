import XCTest
import UIKit
@testable import Chatforia

@MainActor
final class PrivateMessageImageCacheTests: XCTestCase {
    private let grant = URL(string: "https://api.chatforia.com/private-media/file?token=synthetic")!
    private let pixel = UIImage(systemName: "photo")!

    private func key(account: Int = 1, message: Int = 10,
                     attachment: Int = 20, reference: String = "uploads/u1/photo")
        -> PrivateMessageImageCache.Key {
        .init(accountId: account, messageId: message, attachmentId: attachment,
              variant: "thumb", mediaReference: reference)
    }

    func testReopeningUsesDecodedPixelsOnlyAfterFreshGrant() async {
        var fetches = 0
        let cache = PrivateMessageImageCache(fetch: { _ in
            fetches += 1
            return self.pixel
        })
        let identity = key()
        XCTAssertNil(cache.image(for: identity, authorizedURL: nil, expiresAt: nil))
        let first = await cache.load(for: identity, authorizedURL: grant, expiresAt: nil)
        XCTAssertNotNil(first)
        XCTAssertEqual(fetches, 1)
        XCTAssertNotNil(cache.image(for: identity, authorizedURL: grant, expiresAt: nil))
        let reopened = await cache.load(for: identity, authorizedURL: grant, expiresAt: nil)
        XCTAssertNotNil(reopened)
        XCTAssertEqual(fetches, 1, "a reopened view must not download the same pixels again")
        XCTAssertNil(cache.image(for: identity, authorizedURL: nil, expiresAt: nil))
        XCTAssertNil(cache.image(for: identity, authorizedURL: grant, expiresAt: nil))
    }

    func testAccountAndMediaIdentityAreIsolated() {
        let cache = PrivateMessageImageCache()
        cache.storeAuthorized(pixel, for: key(), expiresAt: nil)
        XCTAssertNil(cache.image(for: key(account: 2), authorizedURL: grant, expiresAt: nil))
        XCTAssertNil(cache.image(for: key(reference: "uploads/u1/new-photo"),
                                 authorizedURL: grant, expiresAt: nil))
        XCTAssertNotNil(cache.image(for: key(), authorizedURL: grant, expiresAt: nil))
    }

    func testTimeAndMessageExpiryAndBoundedEviction() {
        var time = Date(timeIntervalSince1970: 1_800_000_000)
        let cache = PrivateMessageImageCache(maxEntries: 1, lifetime: 30, now: { time })
        cache.storeAuthorized(pixel, for: key(), expiresAt: nil)
        time.addTimeInterval(31)
        XCTAssertNil(cache.image(for: key(), authorizedURL: grant, expiresAt: nil))

        let expiry = time.addingTimeInterval(5)
        cache.storeAuthorized(pixel, for: key(), expiresAt: expiry)
        time.addTimeInterval(6)
        XCTAssertNil(cache.image(for: key(), authorizedURL: grant, expiresAt: expiry))

        cache.storeAuthorized(pixel, for: key(), expiresAt: nil)
        cache.storeAuthorized(pixel, for: key(message: 11), expiresAt: nil)
        XCTAssertNil(cache.image(for: key(), authorizedURL: grant, expiresAt: nil))
        XCTAssertNotNil(cache.image(for: key(message: 11), authorizedURL: grant, expiresAt: nil))
    }

    func testDeletionAndDeniedGrantRemoveOnlyAffectedMedia() {
        let cache = PrivateMessageImageCache()
        cache.storeAuthorized(pixel, for: key(), expiresAt: nil)
        cache.storeAuthorized(pixel, for: key(message: 11), expiresAt: nil)
        cache.removeMessage(id: 10)
        XCTAssertNil(cache.image(for: key(), authorizedURL: grant, expiresAt: nil))
        XCTAssertNotNil(cache.image(for: key(message: 11), authorizedURL: grant, expiresAt: nil))
        cache.removeAttachment(accountId: 1, attachmentId: 20, variant: "thumb")
        XCTAssertNil(cache.image(for: key(message: 11), authorizedURL: grant, expiresAt: nil))
    }

    func testConcurrentViewsShareOneDownloadAndClearRejectsLatePixels() async {
        var downloads = 0
        var completion: CheckedContinuation<UIImage?, Never>?
        let cache = PrivateMessageImageCache(fetch: { _ in
            downloads += 1
            return await withCheckedContinuation { completion = $0 }
        })
        let first = Task { await cache.load(for: key(), authorizedURL: grant, expiresAt: nil) }
        for _ in 0..<1_000 where completion == nil { await Task.yield() }
        XCTAssertNotNil(completion)
        let second = Task { await cache.load(for: key(), authorizedURL: grant, expiresAt: nil) }
        await Task.yield()
        completion?.resume(returning: pixel)
        let firstImage = await first.value
        let secondImage = await second.value
        XCTAssertNotNil(firstImage)
        XCTAssertNotNil(secondImage)
        XCTAssertEqual(downloads, 1)

        var lateCompletion: CheckedContinuation<UIImage?, Never>?
        let revocable = PrivateMessageImageCache(fetch: { _ in
            await withCheckedContinuation { lateCompletion = $0 }
        })
        let late = Task { await revocable.load(for: key(), authorizedURL: grant, expiresAt: nil) }
        for _ in 0..<1_000 where lateCompletion == nil { await Task.yield() }
        XCTAssertNotNil(lateCompletion)
        revocable.clear()
        lateCompletion?.resume(returning: pixel)
        let lateImage = await late.value
        XCTAssertNil(lateImage)
        XCTAssertNil(revocable.image(for: key(), authorizedURL: grant, expiresAt: nil))
    }

    func testLargeSourceIsDownsampledForBoundedConversationPreview() {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 2_000, height: 1_000))
            .image { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2_000, height: 1_000)) }
        let bytes = source.jpegData(compressionQuality: 0.9)!
        let preview = PrivateMessageImageCache.decodePreview(bytes)
        XCTAssertNotNil(preview)
        XCTAssertLessThanOrEqual(preview?.cgImage?.width ?? Int.max, 720)
        XCTAssertLessThanOrEqual(preview?.cgImage?.height ?? Int.max, 720)
    }

    func testUnchangedMessageRefreshRetainsPixelsAndRemovalEvictsThem() async {
        let cache = PrivateMessageImageCache.shared
        cache.clear()
        let message = MessageDTO(
            id: 950, attachments: [AttachmentDTO(id: 951, kind: "IMAGE",
                                                 url: "uploads/u1/photo")],
            createdAt: Date(),
            sender: SenderDTO(id: 1, username: "synthetic", publicKey: nil, avatarUrl: nil),
            chatRoomId: 950
        )
        let identity = key(message: 950, attachment: 951)
        MessageStore.shared.replaceMessages(forRoomId: 950, with: [message])
        _ = MessageStore.shared.currentWindow() // Wait for the store's barrier.
        cache.storeAuthorized(pixel, for: identity, expiresAt: nil)

        MessageStore.shared.replaceMessages(forRoomId: 950, with: [message])
        _ = MessageStore.shared.currentWindow()
        await flushMainQueue()
        XCTAssertNotNil(cache.image(for: identity, authorizedURL: grant, expiresAt: nil))

        MessageStore.shared.removeMessage(id: 950)
        _ = MessageStore.shared.currentWindow()
        await flushMainQueue()
        XCTAssertNil(cache.image(for: identity, authorizedURL: grant, expiresAt: nil))
        MessageStore.shared.clearAll()
        cache.clear()
    }

    private func flushMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

}
