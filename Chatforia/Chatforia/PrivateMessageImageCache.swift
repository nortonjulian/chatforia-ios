import Foundation
import ImageIO
import UIKit

/// In-memory image objects only. Capability URLs and image bytes are never persisted.
/// Callers must obtain a fresh, viewer-authorized media grant before reading.
@MainActor
final class PrivateMessageImageCache {
    static let shared = PrivateMessageImageCache()

    struct Key: Hashable {
        let accountId: Int
        let messageId: Int
        let attachmentId: Int
        let variant: String
        let mediaReference: String
    }

    typealias Fetch = @MainActor (URL) async -> UIImage?

    private struct Entry {
        let image: UIImage
        let cost: Int
        let validUntil: Date
    }

    private struct Pending {
        let id: UUID
        let task: Task<UIImage?, Never>
    }

    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []
    private var pending: [Key: Pending] = [:]
    private var totalCost = 0
    private let maxEntries: Int
    private let maxBytes: Int
    private let lifetime: TimeInterval
    private let now: () -> Date
    private let fetch: Fetch

    init(maxEntries: Int = 32, maxBytes: Int = 24 * 1024 * 1024,
         lifetime: TimeInterval = 5 * 60,
         now: @escaping () -> Date = Date.init,
         fetch: @escaping Fetch = { url in
             do {
                 let (data, response) = try await URLSession.shared.data(from: url)
                 guard let http = response as? HTTPURLResponse,
                       (200...299).contains(http.statusCode) else { return nil }
                 // R2 uploads may have no separate thumbnail. Decode only
                 // enough pixels for the conversation bubble off the UI thread.
                 return await withCheckedContinuation { continuation in
                     DispatchQueue.global(qos: .userInitiated).async {
                         continuation.resume(returning: PrivateMessageImageCache.decodePreview(data))
                     }
                 }
             } catch { return nil }
         }) {
        self.maxEntries = max(1, maxEntries)
        self.maxBytes = max(1, maxBytes)
        self.lifetime = max(0, lifetime)
        self.now = now
        self.fetch = fetch
    }

    func image(for key: Key, authorizedURL: URL?, expiresAt: Date?) -> UIImage? {
        guard authorizedURL != nil else {
            remove(key)
            return nil
        }
        pruneExpired()
        guard let entry = entries[key] else { return nil }
        guard expiresAt.map({ now() < $0 }) ?? true else {
            remove(key)
            return nil
        }
        touch(key)
        return entry.image
    }

    func load(for key: Key, authorizedURL: URL?, expiresAt: Date?) async -> UIImage? {
        guard let authorizedURL,
              expiresAt.map({ now() < $0 }) ?? true else {
            remove(key)
            return nil
        }
        if let image = image(for: key, authorizedURL: authorizedURL, expiresAt: expiresAt) {
            return image
        }
        if let existing = pending[key] {
            let result = await existing.task.value
            return pending[key]?.id == existing.id ? result :
                image(for: key, authorizedURL: authorizedURL, expiresAt: expiresAt)
        }

        let id = UUID()
        let task = Task { await fetch(authorizedURL) }
        pending[key] = Pending(id: id, task: task)
        let decoded = await task.value
        // A logout, deletion, or denied grant may have removed this work.
        guard pending[key]?.id == id else { return nil }
        pending.removeValue(forKey: key)
        guard let decoded, expiresAt.map({ now() < $0 }) ?? true else { return nil }
        storeAuthorized(decoded, for: key, expiresAt: expiresAt)
        return decoded
    }

    func remove(_ key: Key) {
        if let entry = entries.removeValue(forKey: key) { totalCost -= entry.cost }
        order.removeAll { $0 == key }
        pending.removeValue(forKey: key)?.task.cancel()
    }

    func removeAttachment(accountId: Int, attachmentId: Int, variant: String) {
        for key in Set(entries.keys).union(pending.keys)
        where key.accountId == accountId && key.attachmentId == attachmentId &&
              key.variant == variant {
            remove(key)
        }
    }

    func removeMessage(id: Int) {
        for key in Set(entries.keys).union(pending.keys) where key.messageId == id {
            remove(key)
        }
    }

    func clear() {
        for work in pending.values { work.task.cancel() }
        pending.removeAll()
        entries.removeAll()
        order.removeAll()
        totalCost = 0
    }

    // Also used by synthetic tests; production writes follow an authorized grant.
    func storeAuthorized(_ image: UIImage, for key: Key, expiresAt: Date?) {
        let validUntil = min(now().addingTimeInterval(lifetime), expiresAt ?? .distantFuture)
        guard validUntil > now() else { return }
        let cost = image.cgImage.map { pixels in
            let (bytes, overflow) = pixels.bytesPerRow.multipliedReportingOverflow(by: pixels.height)
            return overflow ? Int.max : bytes
        } ?? max(1, Int(image.size.width * image.size.height * 4))
        guard cost <= maxBytes else { return }
        remove(key)
        entries[key] = Entry(image: image, cost: cost, validUntil: validUntil)
        totalCost += cost
        touch(key)
        while entries.count > maxEntries || totalCost > maxBytes {
            guard let oldest = order.first else { break }
            remove(oldest)
        }
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func pruneExpired() {
        for (key, entry) in entries where entry.validUntil <= now() { remove(key) }
    }

    nonisolated static func decodePreview(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
              let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 720
              ] as CFDictionary) else { return UIImage(data: data) }
        return UIImage(cgImage: pixels)
    }
}
