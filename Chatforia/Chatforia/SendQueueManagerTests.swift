import XCTest
@testable import Chatforia

final class SendQueueManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()

        SendQueueManager.shared.stop()
        SendQueueManager.shared.clearPersistedSendQueueForDebug()
        SendQueueManager.shared.sendJobHandler = nil
        SendQueueManager.shared.sendSuccessCallback = nil
        SendQueueManager.shared.sendFailedCallback = nil
    }

    override func tearDown() {
        SendQueueManager.shared.stop()
        SendQueueManager.shared.clearPersistedSendQueueForDebug()
        SendQueueManager.shared.sendJobHandler = nil
        SendQueueManager.shared.sendSuccessCallback = nil
        SendQueueManager.shared.sendFailedCallback = nil

        super.tearDown()
    }

    func testSendJobDefaultsToPendingState() {
        let job = makeJob(clientMessageId: "job-1")

        XCTAssertEqual(job.clientMessageId, "job-1")
        XCTAssertEqual(job.localId, "local-1")
        XCTAssertEqual(job.retryCount, 0)
        XCTAssertNil(job.lastAttemptAt)
        XCTAssertEqual(job.state, .pending)
    }

    func testAttachmentMetaStoresValues() {
        let meta = AttachmentMeta(
            filename: "image.jpg",
            size: 12345,
            mimeType: "image/jpeg"
        )

        XCTAssertEqual(meta.filename, "image.jpg")
        XCTAssertEqual(meta.size, 12345)
        XCTAssertEqual(meta.mimeType, "image/jpeg")
    }

    func testSendJobEncodesAndDecodes() throws {
        let job = makeJob(clientMessageId: "job-encode")

        let data = try JSONEncoder().encode(job)
        let decoded = try JSONDecoder().decode(SendJob.self, from: data)

        XCTAssertEqual(decoded.clientMessageId, job.clientMessageId)
        XCTAssertEqual(decoded.localId, job.localId)
        XCTAssertEqual(decoded.retryCount, job.retryCount)
        XCTAssertEqual(decoded.state, job.state)
        XCTAssertEqual(decoded.bodyJSON, job.bodyJSON)
    }

    func testEnqueueCallsSendJobHandler() {
        let expectation = XCTestExpectation(description: "sendJobHandler called")

        SendQueueManager.shared.sendJobHandler = { job, completion in
            XCTAssertEqual(job.clientMessageId, "job-handler")
            completion(.success(serverMessage: nil))
            expectation.fulfill()
        }

        SendQueueManager.shared.enqueue(
            makeJob(clientMessageId: "job-handler")
        )

        wait(for: [expectation], timeout: 2.0)
    }

    func testSuccessfulSendCallsSuccessCallback() {
        let expectation = XCTestExpectation(description: "success callback called")

        SendQueueManager.shared.sendJobHandler = { _, completion in
            completion(.success(serverMessage: nil))
        }

        SendQueueManager.shared.sendSuccessCallback = { clientMessageId, serverMessage in
            XCTAssertEqual(clientMessageId, "job-success")
            XCTAssertNil(serverMessage)
            expectation.fulfill()
        }

        SendQueueManager.shared.enqueue(
            makeJob(clientMessageId: "job-success")
        )

        wait(for: [expectation], timeout: 2.0)
    }

    func testPermanentFailureCallsFailedCallback() {
        let expectation = XCTestExpectation(description: "failed callback called")

        SendQueueManager.shared.sendJobHandler = { _, completion in
            completion(.permanentFailure)
        }

        SendQueueManager.shared.sendFailedCallback = { clientMessageId in
            XCTAssertEqual(clientMessageId, "job-failed")
            expectation.fulfill()
        }

        SendQueueManager.shared.enqueue(
            makeJob(clientMessageId: "job-failed")
        )

        wait(for: [expectation], timeout: 2.0)
    }

    func testMarkJobSucceededDoesNotCrash() {
        SendQueueManager.shared.markJobSucceeded(
            clientMessageId: "missing-job",
            serverMessage: nil
        )

        XCTAssertTrue(true)
    }

    func testMarkJobFailedDoesNotCrashForMissingJob() {
        SendQueueManager.shared.markJobFailed(
            clientMessageId: "missing-job"
        )

        XCTAssertTrue(true)
    }

    func testStopDoesNotCrash() {
        SendQueueManager.shared.stop()

        XCTAssertTrue(true)
    }
}

// MARK: - Helpers

private func makeJob(
    clientMessageId: String
) -> SendJob {
    SendJob(
        clientMessageId: clientMessageId,
        localId: "local-1",
        bodyJSON: #"{"content":"hello"}"#.data(using: .utf8)!,
        attachmentsMeta: nil
    )
}
