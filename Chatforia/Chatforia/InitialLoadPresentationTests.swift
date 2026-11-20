import XCTest
@testable import Chatforia

final class InitialLoadPresentationTests: XCTestCase {
    private func loading(_ loading: Bool = false, attempted: Bool = false,
                         content: Bool = false, error: Bool = false) -> Bool {
        InitialLoadPresentation.showsLoading(
            isLoading: loading, hasAttemptedLoad: attempted,
            hasContent: content, hasError: error
        )
    }

    func testFirstRenderAndInFlightRequestStayInLoadingState() {
        XCTAssertTrue(loading()) // Before the tab's .task begins.
        XCTAssertTrue(loading(true)) // Delayed first response.
    }

    func testFirstSuccessEmptyAndFailureResolveToRealStates() {
        XCTAssertFalse(loading(attempted: true, content: true))
        XCTAssertFalse(loading(attempted: true)) // Verified empty response.
        XCTAssertFalse(loading(attempted: true, error: true))
        XCTAssertFalse(loading(error: true)) // Failed before a response.
    }

    func testLoadedListStaysMountedOnTabReturnAndDuringRefresh() {
        XCTAssertFalse(loading(attempted: true, content: true))
        XCTAssertFalse(loading(true, attempted: true, content: true))
        // A populated List is never exchanged for the loading view, so its
        // existing scroll position remains owned by the same List instance.
    }
}
