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
