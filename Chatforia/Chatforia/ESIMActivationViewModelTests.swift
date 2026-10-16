import XCTest
@testable import Chatforia

@MainActor
final class ESIMActivationViewModelTests: XCTestCase {
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
