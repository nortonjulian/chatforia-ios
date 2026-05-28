import XCTest
@testable import Chatforia

@MainActor
final class SubscriptionManagerTests: XCTestCase {

    func testPlanInfoForPlusMonthly() {
        let result = SubscriptionManager.shared.planInfo(for: "plus.monthly")

        XCTAssertEqual(result.plan, "plus")
        XCTAssertEqual(result.billingPeriod, "monthly")
    }

    func testPlanInfoForPremiumMonthly() {
        let result = SubscriptionManager.shared.planInfo(for: "premium.monthly")

        XCTAssertEqual(result.plan, "premium")
        XCTAssertEqual(result.billingPeriod, "monthly")
    }

    func testPlanInfoForPremiumAnnual() {
        let result = SubscriptionManager.shared.planInfo(for: "premium.annual")

        XCTAssertEqual(result.plan, "premium")
        XCTAssertEqual(result.billingPeriod, "annual")
    }

    func testPlanInfoForUnknownProduct() {
        let result = SubscriptionManager.shared.planInfo(for: "random.product")

        XCTAssertEqual(result.plan, "unknown")
        XCTAssertEqual(result.billingPeriod, "unknown")
    }
}
