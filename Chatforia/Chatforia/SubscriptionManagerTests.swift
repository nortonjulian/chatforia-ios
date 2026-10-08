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

    func testPlanEntitlementsResponseDecodesBackendAllowanceShape() throws {
        let json = #"""
        {
          "plan": "PREMIUM",
          "entitlements": {
            "riaActions": 500,
            "translationChars": 1000000,
            "hostedParticipantMinutes": 600,
            "smsMessages": 750,
            "pstnMinutes": 300,
            "forwardingMinutes": 300,
            "voicemailTranscriptionMinutes": 30,
            "cloudStorageBytes": 53687091200,
            "messageHistoryDays": null,
            "adsEnabled": false,
            "aiRewriteLevel": "FULL",
            "supportLevel": "PRIORITY"
          },
          "monthKey": "2026-10",
          "usage": {
            "riaActions": {
              "used": 12,
              "limit": 500,
              "remaining": 488
            }
          }
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder().decode(
            PlanEntitlementsResponse.self,
            from: json
        )

        XCTAssertEqual(response.plan, "PREMIUM")
        XCTAssertEqual(response.appPlan, .premium)
        XCTAssertEqual(response.entitlements.riaActions, 500)
        XCTAssertEqual(response.entitlements.cloudStorageBytes, 53_687_091_200)
        XCTAssertNil(response.entitlements.messageHistoryDays)
        XCTAssertEqual(response.usage["riaActions"]?.used, 12)
        XCTAssertEqual(response.usage["riaActions"]?.remaining, 488)
    }
}
