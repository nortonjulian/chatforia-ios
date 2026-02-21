import Foundation
import os

public final class SendQueueManager {
    public static let shared = SendQueueManager()

    private let queueFileURL: URL
    private var jobs: [SendJob] = []
    private let fileQueue = DispatchQueue(label: "com.chatforia.sendqueue.file", qos: .utility)
    private let workerQueue = DispatchQueue(label: "com.chatforia.sendqueue.worker", qos: .userInitiated)
    private var isRunning = false
    private var isProcessing = false

    // Simple semaphore to cancel waiting backoffs
    private var currentBackoffTask: DispatchWorkItem?

    private let maxRetryCount = 10
    private let logger = Logger(subsystem: "com.chatforia", category: "SendQueue")

    private init() {
        let fm = FileManager.default
        let doc = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.queueFileURL = doc.appendingPathComponent("send_queue.json")
        loadFromDisk()
    }

    // MARK: - API

    /// Enqueue a send job. Call this *before* attempting network send.
    public func enqueue(_ job: SendJob) {
        fileQueue.async {
            if let idx = self.jobs.firstIndex(where: { $0.clientMessageId == job.clientMessageId }) {
                // existing job: update
                self.jobs[idx] = job
            } else {
                self.jobs.append(job)
            }
            self.saveToDisk()
            self.logger.debug("Enqueued job \(job.clientMessageId, privacy: .public)")
            self.startIfNeeded()
        }
    }

    public func startIfNeeded() {
        fileQueue.async {
            guard !self.isRunning else { return }
            self.isRunning = true
            self.processLoop()
        }
    }

    public func start() {
        fileQueue.async {
            self.isRunning = true
            self.processLoop()
        }
    }

    public func stop() {
        fileQueue.async {
            self.isRunning = false
            self.currentBackoffTask?.cancel()
            self.currentBackoffTask = nil
        }
    }

    /// Replay jobs (call on socket connect or app foreground)
    public func replayQueuedJobs() {
        startIfNeeded()
    }

    // Called by network layer when a server message arrives for a clientMessageId
    public func markJobSucceeded(clientMessageId: String, serverMessage: ServerMessage?) {
        fileQueue.async {
            self.jobs.removeAll { $0.clientMessageId == clientMessageId }
            self.saveToDisk()
            self.logger.debug("Job succeeded and dequeued \(clientMessageId, privacy: .public)")
        }
    }

    // Mark job as permanently failed (exposed for UI to mark message failed)
    public func markJobFailed(clientMessageId: String) {
        fileQueue.async {
            if let i = self.jobs.firstIndex(where: { $0.clientMessageId == clientMessageId }) {
                self.jobs[i].state = .failed
                self.saveToDisk()
            }
        }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        fileQueue.async {
            do {
                let data = try Data(contentsOf: self.queueFileURL)
                let decoder = JSONDecoder()
                self.jobs = try decoder.decode([SendJob].self, from: data)
                self.logger.debug("Loaded \(self.jobs.count) jobs from disk.")
            } catch {
                self.jobs = []
                self.logger.debug("No send queue on disk or failed to load: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(jobs)
            try data.write(to: queueFileURL, options: .atomic)
        } catch {
            self.logger.error("Failed to persist send queue: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Worker loop (serializes jobs, respects backoff)

    private func processLoop() {
        workerQueue.async { [weak self] in
            guard let self = self else { return }
            self.logger.debug("Starting worker loop")
            self.isProcessing = true

            while true {
                // stop condition
                var nextJob: SendJob?
                self.fileQueue.sync {
                    nextJob = self.jobs
                        .filter { $0.state == .pending || $0.state == .retrying }
                        .sorted { $0.createdAt < $1.createdAt }
                        .first
                }

                guard self.isRunning, let job = nextJob else {
                    self.logger.debug("No pending jobs or stopped.")
                    self.isProcessing = false
                    return
                }

                // attempt to send (delegate to app's NetworkClient)
                let semaphore = DispatchSemaphore(value: 0)
                var attemptResult: SendAttemptResult = .temporaryFailure // default

                // Before sending: mark as 'sending' and save
                self.fileQueue.sync {
                    if let i = self.jobs.firstIndex(where: { $0.clientMessageId == job.clientMessageId }) {
                        self.jobs[i].state = .sending
                        self.jobs[i].lastAttemptAt = Date()
                        self.saveToDisk()
                    }
                }

                // This expects your app to set `SendQueueManager.shared.sendJobHandler` to call network.
                if let handler = SendQueueManager.shared.sendJobHandler {
                    handler(job) { result in
                        attemptResult = result
                        semaphore.signal()
                    }
                    // wait for network callback
                    _ = semaphore.wait(timeout: .now() + 60) // network timeout safety
                } else {
                    self.logger.error("No sendJobHandler defined. Cannot send jobs.")
                    attemptResult = .temporaryFailure
                    semaphore.signal()
                }

                switch attemptResult {
                case .success(let serverMessage):
                    // dequeue and call insertion callback
                    self.fileQueue.sync {
                        self.jobs.removeAll { $0.clientMessageId == job.clientMessageId }
                        self.saveToDisk()
                    }
                    // notify app to insert authoritative message (insertOrReplace)
                    DispatchQueue.main.async {
                        self.sendSuccessCallback?(job.clientMessageId, serverMessage)
                    }
                    continue // process next job immediately

                case .permanentFailure:
                    // mark as failed; leave job so UI can show retry
                    self.fileQueue.sync {
                        if let i = self.jobs.firstIndex(where: { $0.clientMessageId == job.clientMessageId }) {
                            self.jobs[i].state = .failed
                            self.jobs[i].retryCount += 1
                            self.saveToDisk()
                        }
                    }
                    DispatchQueue.main.async {
                        self.sendFailedCallback?(job.clientMessageId)
                    }
                    continue

                case .temporaryFailure:
                    // backoff and retry later
                    self.fileQueue.sync {
                        if let i = self.jobs.firstIndex(where: { $0.clientMessageId == job.clientMessageId }) {
                            self.jobs[i].retryCount += 1
                            self.jobs[i].state = .retrying
                            self.saveToDisk()
                        }
                    }

                    let retryCount = job.retryCount + 1
                    if retryCount > self.maxRetryCount {
                        // treat as permanent failure
                        self.fileQueue.sync {
                            if let i = self.jobs.firstIndex(where: { $0.clientMessageId == job.clientMessageId }) {
                                self.jobs[i].state = .failed
                                self.saveToDisk()
                            }
                        }
                        DispatchQueue.main.async {
                            self.sendFailedCallback?(job.clientMessageId)
                        }
                        continue
                    }

                    let backoffSeconds = min(Double(2 << retryCount), 60.0) // exponential, cap at 60s
                    let waitTask = DispatchWorkItem { }
                    self.currentBackoffTask = waitTask
                    self.logger.debug("Temporary failure; backing off \(backoffSeconds)s for job \(job.clientMessageId, privacy: .public).")
                    let group = DispatchGroup()
                    group.enter()
                    self.workerQueue.asyncAfter(deadline: .now() + backoffSeconds) {
                        group.leave()
                    }
                    group.wait()
                    // loop continues to pick up that job again
                    continue
                }
            }
        }
    }

    // MARK: - Callbacks / Handlers the app must set

    /// Called by worker to perform network send; return via completion with SendAttemptResult.
    public var sendJobHandler: ((SendJob, @escaping (SendAttemptResult) -> Void) -> Void)?

    /// Called on success (app should insertOrReplace serverMessage into DB/UI)
    public var sendSuccessCallback: ((String, ServerMessage?) -> Void)?

    /// Called on permanent failure (app should mark message failed in UI)
    public var sendFailedCallback: ((String) -> Void)?
}

// MARK: - Supporting types

public struct SendJob: Codable, Equatable {
    public var clientMessageId: String
    public var localId: String? // local DB id if any
    public var createdAt: Date
    public var retryCount: Int
    public var lastAttemptAt: Date?
    public var bodyJSON: Data // encoded payload the server expects
    public var attachmentsMeta: [AttachmentMeta]?
    public var state: JobState

    public init(clientMessageId: String, localId: String?, bodyJSON: Data, attachmentsMeta: [AttachmentMeta]?) {
        self.clientMessageId = clientMessageId
        self.localId = localId
        self.createdAt = Date()
        self.retryCount = 0
        self.lastAttemptAt = nil
        self.bodyJSON = bodyJSON
        self.attachmentsMeta = attachmentsMeta
        self.state = .pending
    }
}

public enum JobState: String, Codable {
    case pending
    case sending
    case retrying
    case failed
}

public struct AttachmentMeta: Codable, Equatable {
    public var filename: String
    public var size: Int
    public var mimeType: String
}

// Result of attempt
public enum SendAttemptResult {
    case success(serverMessage: ServerMessage?)
    case temporaryFailure
    case permanentFailure
}

// Minimal server message placeholder (your app has its own model)
public struct ServerMessage: Codable {
    public var id: Int?
    public var clientMessageId: String?
    // Add other fields as needed
}//
//  SendQueueManager.swift
//  Chatforia
//
//  Created by Julian Norton on 2/21/26.
//

import Foundation
