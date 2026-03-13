import Foundation
import os

final class SendQueueManager {
    static let shared = SendQueueManager()

    private let queueFileURL: URL
    private var jobs: [SendJob] = []

    // Single state queue owns all mutable state
    private let stateQueue = DispatchQueue(label: "com.chatforia.sendqueue.state", qos: .userInitiated)

    private var isLoaded = false
    private var isRunning = false
    private var isProcessing = false
    private var currentBackoffWorkItem: DispatchWorkItem?

    private let maxRetryCount = 10
    private let logger = Logger(subsystem: "com.chatforia", category: "SendQueue")

    private init() {
        let fm = FileManager.default
        let doc = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.queueFileURL = doc.appendingPathComponent("send_queue.json")

        // Deterministic initial load
        self.loadFromDiskSync()
    }

    // MARK: - API

    func enqueue(_ job: SendJob) {
        stateQueue.async {
            self.ensureLoadedLocked()

            if let idx = self.jobs.firstIndex(where: { $0.clientMessageId == job.clientMessageId }) {
                var merged = self.jobs[idx]
                merged.bodyJSON = job.bodyJSON
                merged.attachmentsMeta = job.attachmentsMeta
                merged.localId = job.localId
                merged.state = .pending
                self.jobs[idx] = merged
            } else {
                self.jobs.append(job)
            }
            
            print("🧾 ENQUEUE job:", job.clientMessageId)
            print("🧾 queue count after enqueue:", self.jobs.count)

            self.saveToDiskLocked()
            self.logger.debug("Enqueued job \(job.clientMessageId, privacy: .public)")
            self.startProcessingLockedIfNeeded()
        }
    }

    func retryJob(clientMessageId: String) {
        stateQueue.async {
            self.ensureLoadedLocked()

            guard let idx = self.jobs.firstIndex(where: { $0.clientMessageId == clientMessageId }) else {
                return
            }

            self.jobs[idx].state = .pending
            self.jobs[idx].lastAttemptAt = Date()
            self.saveToDiskLocked()

            DispatchQueue.main.async {
                MessageStore.shared.setDeliveryState(clientMessageId: clientMessageId, state: .sending)
            }

            self.logger.debug("Retry requested for job \(clientMessageId, privacy: .public)")
            self.startProcessingLockedIfNeeded()
        }
    }


    func startIfNeeded() {
        stateQueue.async {
            print("▶️ startIfNeeded called. isRunning=\(self.isRunning) isProcessing=\(self.isProcessing)")
            self.ensureLoadedLocked()
            self.startProcessingLockedIfNeeded()
        }
    }

    func stop() {
        stateQueue.async {
            self.isRunning = false
            self.currentBackoffWorkItem?.cancel()
            self.currentBackoffWorkItem = nil
        }
    }

    func replayQueuedJobs() {
        stateQueue.async {
            print("🔁 replayQueuedJobs called. queued jobs=\(self.jobs.count)")
            self.startProcessingLockedIfNeeded()
        }
    }

    func markJobSucceeded(clientMessageId: String, serverMessage: MessageDTO?) {
        stateQueue.async {
            self.ensureLoadedLocked()
            self.jobs.removeAll { $0.clientMessageId == clientMessageId }
            self.saveToDiskLocked()
            self.logger.debug("Job succeeded and dequeued \(clientMessageId, privacy: .public)")
        }
    }

    func markJobFailed(clientMessageId: String) {
        stateQueue.async {
            self.ensureLoadedLocked()
            guard let idx = self.jobs.firstIndex(where: { $0.clientMessageId == clientMessageId }) else { return }
            self.jobs[idx].state = .failed
            self.saveToDiskLocked()
        }
    }

    // MARK: - Persistence

    private func loadFromDiskSync() {
        stateQueue.sync {
            self.ensureLoadedLocked()
        }
    }

    private func ensureLoadedLocked() {
        guard !isLoaded else { return }

        do {
            let data = try Data(contentsOf: self.queueFileURL)
            self.jobs = try JSONDecoder().decode([SendJob].self, from: data)
            self.logger.debug("Loaded \(self.jobs.count) jobs from disk.")
        } catch {
            self.jobs = []
            self.logger.debug("No send queue on disk or failed to load: \(error.localizedDescription, privacy: .public)")
        }

        self.isLoaded = true
    }

    private func saveToDiskLocked() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(jobs)
            try data.write(to: queueFileURL, options: .atomic)
        } catch {
            self.logger.error("Failed to persist send queue: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Worker

    private func startProcessingLockedIfNeeded() {
        guard !isProcessing else {
            isRunning = true
            return
        }

        isRunning = true
        isProcessing = true

        stateQueue.async {
            self.processNextLocked()
        }
    }

    private func processNextLocked() {
        guard isRunning else {
            isProcessing = false
            return
        }
        
        print("⚙️ ABOUT TO PROCESS next job. queued jobs=\(jobs.count)")
        guard let job = nextRunnableJobLocked() else {
            isProcessing = false
            logger.debug("No pending jobs or stopped.")
            return
        }

        if let idx = jobs.firstIndex(where: { $0.clientMessageId == job.clientMessageId }) {
            jobs[idx].state = .sending
            jobs[idx].lastAttemptAt = Date()
            saveToDiskLocked()
        }

        DispatchQueue.main.async {
            MessageStore.shared.setDeliveryState(clientMessageId: job.clientMessageId, state: .sending)
        }

        guard let handler = self.sendJobHandler else {
            logger.error("No sendJobHandler defined. Cannot send jobs.")
            handleTemporaryFailureLocked(for: job, reason: "missing sendJobHandler")
            return
        }

        let jobForSend = job

        logger.debug("Calling sendJobHandler for \(jobForSend.clientMessageId, privacy: .public)")
        
        
        print("📤 CALLING sendJobHandler for:", jobForSend.clientMessageId)
        handler(jobForSend) { result in
            self.stateQueue.async {
                print("✅/❌ sendJobHandler completion for \(jobForSend.clientMessageId): \(result)")
                switch result {
                case .success(let serverMessage):
                    self.handleSuccessLocked(for: jobForSend, serverMessage: serverMessage)

                case .permanentFailure:
                    self.handlePermanentFailureLocked(for: jobForSend)

                case .temporaryFailure:
                    self.handleTemporaryFailureLocked(for: jobForSend, reason: "temporary failure")
                }
            }
        }
    }

    private func nextRunnableJobLocked() -> SendJob? {
        jobs
            .filter { $0.state == .pending || $0.state == .retrying }
            .sorted { $0.createdAt < $1.createdAt }
            .first
    }

    private func handleSuccessLocked(for job: SendJob, serverMessage: MessageDTO?) {
        jobs.removeAll { $0.clientMessageId == job.clientMessageId }
        saveToDiskLocked()

        DispatchQueue.main.async {
            MessageStore.shared.setDeliveryState(clientMessageId: job.clientMessageId, state: .sent)
            self.sendSuccessCallback?(job.clientMessageId, serverMessage)
        }

        processNextLocked()
    }

    private func handlePermanentFailureLocked(for job: SendJob) {
        if let idx = jobs.firstIndex(where: { $0.clientMessageId == job.clientMessageId }) {
            jobs[idx].state = .failed
            jobs[idx].retryCount += 1
            saveToDiskLocked()
        }

        DispatchQueue.main.async {
            MessageStore.shared.setDeliveryState(clientMessageId: job.clientMessageId, state: .failed)
            self.sendFailedCallback?(job.clientMessageId)
        }

        processNextLocked()
    }

    private func handleTemporaryFailureLocked(for job: SendJob, reason: String) {
        guard let idx = jobs.firstIndex(where: { $0.clientMessageId == job.clientMessageId }) else {
            processNextLocked()
            return
        }

        jobs[idx].retryCount += 1

        if jobs[idx].retryCount > maxRetryCount {
            jobs[idx].state = .failed
            saveToDiskLocked()

            DispatchQueue.main.async {
                MessageStore.shared.setDeliveryState(clientMessageId: job.clientMessageId, state: .failed)
                self.sendFailedCallback?(job.clientMessageId)
            }

            processNextLocked()
            return
        }

        jobs[idx].state = .retrying
        saveToDiskLocked()

        let retryCount = jobs[idx].retryCount
        let backoffSeconds = min(pow(2.0, Double(retryCount)), 60.0)

        logger.debug("Temporary failure (\(reason, privacy: .public)); backing off \(backoffSeconds)s for job \(job.clientMessageId, privacy: .public)")

        currentBackoffWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            self.stateQueue.async {
                if self.currentBackoffWorkItem?.isCancelled == true {
                    self.processNextLocked()
                    return
                }

                if let idx = self.jobs.firstIndex(where: { $0.clientMessageId == job.clientMessageId }) {
                    self.jobs[idx].state = .pending
                    self.saveToDiskLocked()
                }

                self.processNextLocked()
            }
        }

        currentBackoffWorkItem = workItem
        stateQueue.asyncAfter(deadline: .now() + backoffSeconds, execute: workItem)
    }

    // MARK: - Callbacks / Handlers

    var sendJobHandler: ((SendJob, @escaping (SendAttemptResult) -> Void) -> Void)?
    var sendSuccessCallback: ((String, MessageDTO?) -> Void)?
    var sendFailedCallback: ((String) -> Void)?
}

struct SendJob: Codable, Equatable {
    public var clientMessageId: String
    public var localId: String?
    public var createdAt: Date
    public var retryCount: Int
    public var lastAttemptAt: Date?
    public var bodyJSON: Data
    public var attachmentsMeta: [AttachmentMeta]?
    public var state: JobState

    init(clientMessageId: String, localId: String?, bodyJSON: Data, attachmentsMeta: [AttachmentMeta]?) {
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

enum JobState: String, Codable {
    case pending
    case sending
    case retrying
    case failed
}

struct AttachmentMeta: Codable, Equatable {
    public var filename: String
    public var size: Int
    public var mimeType: String
}

enum SendAttemptResult {
    case success(serverMessage: MessageDTO?)
    case temporaryFailure
    case permanentFailure
}

extension SendQueueManager {
    static var isConfiguredForHandlers: Bool = false
}
