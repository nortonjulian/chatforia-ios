import Foundation
import XCTest
@testable import Chatforia

@MainActor
final class CreatorReferralTests: XCTestCase {
    func testOnlyCreatorLinksOnChatforiaAreAccepted() {
        XCTAssertEqual(CreatorReferralStore.code(from: URL(string: "https://chatforia.com/register?ref=creator_1")!), "CREATOR_1")
        XCTAssertEqual(CreatorReferralStore.code(from: URL(string: "https://www.chatforia.com/ref/Creator-2")!), "CREATOR-2")
        XCTAssertNil(CreatorReferralStore.code(from: URL(string: "https://other.example/register?ref=CREATOR")!))
        XCTAssertNil(CreatorReferralStore.code(from: URL(string: "https://chatforia.com/i/person123?ref=CREATOR")!))
        XCTAssertNil(CreatorReferralStore.code(from: URL(string: "https://chatforia.com/register?ref=bad%20code")!))
    }

    func testFirstTouchAndThirtyDayExpiry() {
        let suite = "CreatorReferralTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = Date(timeIntervalSince1970: 1_000_000)
        let store = CreatorReferralStore(defaults: defaults, now: { now })

        store.capture(from: URL(string: "https://chatforia.com/register?ref=FIRST")!)
        store.capture(from: URL(string: "https://chatforia.com/register?ref=SECOND")!)
        XCTAssertEqual(store.currentCode(), "FIRST")

        now.addTimeInterval(31 * 24 * 60 * 60)
        XCTAssertNil(store.currentCode())
        store.capture(from: URL(string: "https://chatforia.com/register?ref=SECOND")!)
        XCTAssertEqual(store.currentCode(), "SECOND")
        store.clear()
        XCTAssertNil(store.currentCode())
    }

    func testRegistrationRequestCarriesCreatorCode() {
        let request = RegistrationService().makeRegistrationRequest(
            username: "julian",
            email: "julian@example.com",
            password: "password123",
            referralCode: "CREATOR"
        )
        XCTAssertEqual(request.referralCode, "CREATOR")
    }
}
