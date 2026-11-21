import XCTest
import SwiftUI
import UIKit
@testable import Chatforia

@MainActor
final class ESIMActivationViewModelTests: XCTestCase {
    func testRecentOverviewHistoryKeepsEveryRecordInManage() throws {
        let packages = try makeHistory(count: 30)
        XCTAssertEqual(
            PurchasedDataPackagesList.visiblePackages(packages, presentation: .recent).map(\.id),
            [30, 29]
        )
        XCTAssertEqual(
            PurchasedDataPackagesList.visiblePackages(packages, presentation: .complete).map(\.id),
            Array((1...30).reversed())
        )
    }

    func testMissingActivationTimeAppearsOnlyWhenItExplainsState() {
        XCTAssertTrue(PurchasedDataPackagesList.activationDateMatters(for: "AWAITING_ACTIVATION"))
        XCTAssertTrue(PurchasedDataPackagesList.activationDateMatters(for: "EXPIRY_NEEDS_REVIEW"))
        for state in ["ACTIVE", "EXPIRED", "TERMINATED", "EXHAUSTED", "PROVIDER_UNVERIFIED"] {
            XCTAssertFalse(PurchasedDataPackagesList.activationDateMatters(for: state))
        }
    }

    func testCustomerStatusWordingDoesNotClaimPaymentOrProviderConfirmation() {
        let states = [
            "AWAITING_ACTIVATION": "Not active yet",
            "AWAITING_PROVISIONING": "Data package setup not confirmed",
            "PROVISIONING_NEEDS_REVIEW": "Data package setup needs review",
            "PAYMENT_UNVERIFIED": "Payment status not confirmed",
            "PROVIDER_UNVERIFIED": "Provider status not confirmed",
            "BALANCE_NEEDS_REVIEW": "Data balance needs confirmation",
            "EXPIRY_NEEDS_REVIEW": "Expiration needs confirmation",
            "TERMINATED": "Package ended by provider"
        ]
        for (state, expected) in states {
            XCTAssertEqual(
                appText(PurchasedDataPackagesList.statusKey(for: state), languageCode: "en"),
                expected
            )
        }
    }

    func testHistoryRowsExpandAtAccessibilityTextSize() throws {
        let packages = try makeHistory(count: 2)
        let list = PurchasedDataPackagesList(
            packages: packages, errorMessage: nil, presentation: .recent
        )
        let regular = UIHostingController(rootView:
            list.environmentObject(ThemeManager()).environment(\.dynamicTypeSize, .large)
        )
        let accessibility = UIHostingController(
            rootView: list.environmentObject(ThemeManager()).environment(\.dynamicTypeSize, .accessibility3)
        )
        let width: CGFloat = 320
        let regularHeight = regular.sizeThatFits(in: CGSize(width: width, height: 10_000)).height
        let accessibilityHeight = accessibility.sizeThatFits(in: CGSize(width: width, height: 10_000)).height
        XCTAssertGreaterThan(accessibilityHeight, regularHeight)
    }

    func testCompleteHistoryCanScrollAboveTabBarAtAccessibilityTextSize() throws {
        let packages = try makeHistory(count: 30)
        let payload = ESIMActivationDTO(
            smdpAddress: nil, activationCode: nil, iccid: "89012345678901234567",
            confirmationCode: nil, planName: nil, status: "ACTIVE",
            qrCodeURL: nil, lpaUri: nil
        )
        let detail = ESIMActivationView(
            viewModel: ESIMActivationViewModel(payload: payload),
            purchasedPackages: WirelessPurchasesResponseDTO(
                packages: packages,
                replacementEligibility: WirelessReplacementEligibilityDTO(
                    eligible: false, purchaseId: nil, reason: nil
                )
            ),
            purchasesErrorMessage: nil,
            onRequestReplacement: nil
        )
        try assertFloatingTabBarClearance(detail.environmentObject(ThemeManager()))
    }

    func testOverviewCanScrollAboveTabBarWithLongHistory() throws {
        let packages = try makeHistory(count: 30)
        let payload = ESIMActivationDTO(
            smdpAddress: nil, activationCode: nil, iccid: "89012345678901234567",
            confirmationCode: nil, planName: nil, status: "ACTIVE",
            qrCodeURL: nil, lpaUri: nil
        )
        let overview = WirelessHomeView(
            purchasedPackagesForPreview: WirelessPurchasesResponseDTO(
                packages: packages,
                replacementEligibility: WirelessReplacementEligibilityDTO(
                    eligible: false, purchaseId: nil, reason: nil
                )
            ),
            activationForPreview: payload,
            shouldLoadRemoteData: false
        )
        try assertFloatingTabBarClearance(
            overview
                .environmentObject(ThemeManager())
                .environmentObject(AuthStore())
                .environmentObject(CheckoutReturnCoordinator())
        )
    }

    private func assertFloatingTabBarClearance<Content: View>(_ content: Content) throws {
        let host = UIHostingController(rootView:
            TabView {
                NavigationStack { content }
                    .tabItem { Label("Wireless", systemImage: "antenna.radiowaves.left.and.right") }
                Text("Other").tabItem { Label("Other", systemImage: "circle") }
            }
            .environment(\.dynamicTypeSize, .accessibility2)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()

        func descendants(of view: UIView) -> [UIView] {
            [view] + view.subviews.flatMap(descendants)
        }
        let scroll = try XCTUnwrap(descendants(of: host.view)
            .compactMap { $0 as? UIScrollView }
            .first { $0.contentSize.height > $0.bounds.height })
        let tabBar = try XCTUnwrap(descendants(of: host.view)
            .compactMap { $0 as? UITabBar }.first)
        let endOffset = max(0, scroll.contentSize.height - scroll.bounds.height
                            + scroll.adjustedContentInset.bottom)
        scroll.setContentOffset(CGPoint(x: 0, y: endOffset), animated: false)
        scroll.layoutIfNeeded()
        let contentBottom = scroll.convert(CGPoint(x: 0, y: scroll.contentSize.height), to: host.view).y
        let tabBarTop = tabBar.convert(.zero, to: host.view).y
        XCTAssertLessThanOrEqual(contentBottom, tabBarTop + 2)
    }

    private func makeHistory(count: Int) throws -> [WirelessPurchasedPackageDTO] {
        let rows: [[String: Any]] = (1...count).reversed().map { id in
            ["id": id, "addonKind": "chatforia_esim_local_3", "state": "EXPIRED",
             "unlimited": false, "totalDataMb": 3_072, "remainingDataMb": 0, "paid": true]
        }
        return try JSONDecoder().decode([WirelessPurchasedPackageDTO].self,
                                        from: JSONSerialization.data(withJSONObject: rows))
    }

    func testPurchaseAndTransferLocalizationKeysResolve() {
        XCTAssertEqual(appText("esim.transfer.confirmTitle", languageCode: "en"), "Replace eSIM?")
        XCTAssertEqual(appText("esim.transfer.confirmAction", languageCode: "en"), "Replace eSIM")
        XCTAssertEqual(appText("common.cancel", languageCode: "es"), "Cancelar")
        XCTAssertEqual(
            appText("esim.purchase.historyTitle", languageCode: "en"),
            "Purchased Data Packages"
        )
        XCTAssertEqual(
            appText("esim.profileActiveSubtitle", languageCode: "en"),
            "Your eSIM profile is active. Check Wireless for each data package's status."
        )
        XCTAssertEqual(
            localizedEsimReplacementReason(
                "Multiple or pending data packages may share this eSIM. Transfer is unavailable until every remaining entitlement can be preserved.",
                languageCode: "en"
            ),
            "Multiple or pending data packages may share this eSIM. Transfer is unavailable until every remaining entitlement can be preserved."
        )
        XCTAssertEqual(
            localizedEsimReplacementReason("Unknown future reason", languageCode: "en"),
            "eSIM transfer is unavailable until package eligibility can be confirmed."
        )
    }

    func testActiveEsimHidesProvisioningDetailsAndMasksIccid() {
        let payload = ESIMActivationDTO(
            smdpAddress: "smdp.example.com",
            activationCode: "SECRET-ACTIVATION-CODE",
            iccid: "89012345678901234567",
            confirmationCode: "SECRET-CONFIRMATION-CODE",
            planName: "Local 3 GB",
            status: "ACTIVE",
            qrCodeURL: nil,
            lpaUri: "LPA:1$smdp.example.com$SECRET-ACTIVATION-CODE"
        )

        let viewModel = ESIMActivationViewModel(payload: payload)

        XCTAssertTrue(viewModel.isActive)
        XCTAssertFalse(viewModel.showsProvisioningDetails)
        XCTAssertTrue(viewModel.subtitleText.contains("eSIM profile is active"))
        XCTAssertFalse(viewModel.subtitleText.contains("data pack is active"))

        XCTAssertEqual(viewModel.displayIccidText, "•••• •••• •••• 4567")
        XCTAssertNotEqual(viewModel.displayIccidText, payload.iccid)

        // Hiding credentials is presentation-only. Keep the source data intact.
        XCTAssertEqual(
            viewModel.payload.activationCode,
            "SECRET-ACTIVATION-CODE"
        )
        XCTAssertEqual(
            viewModel.payload.lpaUri,
            "LPA:1$smdp.example.com$SECRET-ACTIVATION-CODE"
        )
    }

    func testProvisioningEsimBuildsAppleUniversalInstallLink() {
        let lpaCode = "LPA:1$smdp.example.com$ACTIVATION-CODE"
        let payload = ESIMActivationDTO(
            smdpAddress: "smdp.example.com",
            activationCode: "ACTIVATION-CODE",
            iccid: "89012345678901234567",
            confirmationCode: nil,
            planName: "Local 3 GB",
            status: "PROVISIONING",
            qrCodeURL: nil,
            lpaUri: lpaCode
        )

        let viewModel = ESIMActivationViewModel(payload: payload)

        guard
            let url = viewModel.installURL,
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )
        else {
            return XCTFail("Expected Apple eSIM Universal Link.")
        }

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "esimsetup.apple.com")
        XCTAssertEqual(
            components.path,
            "/esim_qrcode_provisioning"
        )

        let cardData = components.queryItems?
            .first(where: { $0.name == "carddata" })?
            .value

        XCTAssertEqual(cardData, lpaCode)
        XCTAssertTrue(viewModel.canInstall)
    }

    func testInstallLinkCanBuildLpaFromSmdpAndActivationCode() {
        let payload = ESIMActivationDTO(
            smdpAddress: "smdp.example.com",
            activationCode: "ACTIVATION-CODE",
            iccid: "89012345678901234567",
            confirmationCode: nil,
            planName: "Local 3 GB",
            status: "PROVISIONING",
            qrCodeURL: nil,
            lpaUri: nil
        )

        let viewModel = ESIMActivationViewModel(payload: payload)

        guard
            let url = viewModel.installURL,
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )
        else {
            return XCTFail("Expected Apple eSIM Universal Link.")
        }

        let cardData = components.queryItems?
            .first(where: { $0.name == "carddata" })?
            .value

        XCTAssertEqual(
            cardData,
            "LPA:1$smdp.example.com$ACTIVATION-CODE"
        )
        XCTAssertTrue(viewModel.canInstall)
    }

    func testActiveEsimCannotInstallAgain() {
        let payload = ESIMActivationDTO(
            smdpAddress: "smdp.example.com",
            activationCode: "ACTIVATION-CODE",
            iccid: "89012345678901234567",
            confirmationCode: nil,
            planName: "Local 3 GB",
            status: "ACTIVE",
            qrCodeURL: nil,
            lpaUri: "LPA:1$smdp.example.com$ACTIVATION-CODE"
        )

        let viewModel = ESIMActivationViewModel(payload: payload)

        XCTAssertFalse(viewModel.canInstall)
        XCTAssertNil(viewModel.installURL)
        XCTAssertFalse(viewModel.showsProvisioningDetails)
    }

    func testProvisioningEsimStillAllowsProvisioningDetails() {
        let payload = ESIMActivationDTO(
            smdpAddress: "smdp.example.com",
            activationCode: "ACTIVATION-CODE",
            iccid: "89012345678901234567",
            confirmationCode: nil,
            planName: "Local 3 GB",
            status: "PROVISIONING",
            qrCodeURL: nil,
            lpaUri: "LPA:1$smdp.example.com$ACTIVATION-CODE"
        )

        let viewModel = ESIMActivationViewModel(payload: payload)

        XCTAssertFalse(viewModel.isActive)
        XCTAssertTrue(viewModel.showsProvisioningDetails)
        XCTAssertEqual(viewModel.displayIccidText, "•••• •••• •••• 4567")
    }
}
