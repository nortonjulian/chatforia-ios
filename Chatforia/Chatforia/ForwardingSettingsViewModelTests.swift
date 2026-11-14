import XCTest
@testable import Chatforia

@MainActor
final class ForwardingSettingsViewModelTests: XCTestCase {

    func testLoadCopiesDTOIntoState() {
        let vm = ForwardingSettingsViewModel()
        let dto = makeDTO()

        vm.load(from: dto)

        XCTAssertEqual(vm.forwardingEnabledSms, dto.forwardingEnabledSms)
        XCTAssertEqual(vm.forwardSmsToPhone, dto.forwardSmsToPhone)
        XCTAssertEqual(vm.forwardPhoneNumber, dto.forwardPhoneNumber)
        XCTAssertEqual(vm.forwardSmsToEmail, dto.forwardSmsToEmail)
        XCTAssertEqual(vm.forwardEmail, dto.forwardEmail)
        XCTAssertEqual(vm.forwardingEnabledCalls, dto.forwardingEnabledCalls)
        XCTAssertEqual(vm.forwardToPhoneE164, dto.forwardToPhoneE164)
        XCTAssertEqual(vm.forwardQuietHoursStart, dto.forwardQuietHoursStart)
        XCTAssertEqual(vm.forwardQuietHoursEnd, dto.forwardQuietHoursEnd)
    }

    func testMakeRequestTrimsEmailAndNormalizesPhones() {
        let vm = ForwardingSettingsViewModel()

        vm.forwardingEnabledSms = true
        vm.forwardSmsToPhone = true
        vm.forwardPhoneNumber = " +1 (555) 123-4567 "
        vm.forwardSmsToEmail = true
        vm.forwardEmail = "  test@example.com  "
        vm.forwardingEnabledCalls = true
        vm.forwardToPhoneE164 = " +1 (555) 987-6543 "
        vm.forwardQuietHoursStart = 22
        vm.forwardQuietHoursEnd = 7

        let request = vm.makeRequest()

        XCTAssertEqual(request.forwardPhoneNumber, "+15551234567")
        XCTAssertEqual(request.forwardEmail, "test@example.com")
        XCTAssertEqual(request.forwardToPhoneE164, "+15559876543")
        XCTAssertEqual(request.forwardQuietHoursStart, 22)
        XCTAssertEqual(request.forwardQuietHoursEnd, 7)
    }

    func testHasChangesFalseImmediatelyAfterLoad() {
        let vm = ForwardingSettingsViewModel()

        vm.load(from: makeDTO())

        XCTAssertFalse(vm.hasChanges)
    }

    func testHasChangesTrueAfterStateChange() {
        let vm = ForwardingSettingsViewModel()

        vm.load(from: makeDTO())

        vm.forwardEmail = "new@example.com"

        XCTAssertTrue(vm.hasChanges)
    }

    func testResetRestoresInitialStateAndClearsMessages() {
        let vm = ForwardingSettingsViewModel()
        let dto = makeDTO()

        vm.load(from: dto)
        vm.forwardEmail = "changed@example.com"
        vm.banner = "Saved"
        vm.errorMessage = "Error"

        vm.reset()

        XCTAssertEqual(vm.forwardEmail, dto.forwardEmail)
        XCTAssertNil(vm.banner)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.hasChanges)
    }

    func testAccountChangeClearsPreviousAccountSettingsAndMessages() {
        let vm = ForwardingSettingsViewModel()
        vm.load(from: makeDTO())
        vm.banner = "Saved"
        vm.clearForAccountChange()
        XCTAssertEqual(vm.makeRequest().forwardPhoneNumber, "")
        XCTAssertNil(vm.initialState)
        XCTAssertNil(vm.banner)
        XCTAssertFalse(vm.hasChanges)
    }

    func testQuietHoursRequireBothEndpoints() {
        let vm = ForwardingSettingsViewModel()
        vm.forwardQuietHoursStart = 22
        XCTAssertEqual(vm.validationErrors["quiet"], "Set both quiet hours or clear both.")
        vm.forwardQuietHoursEnd = 6
        XCTAssertNil(vm.validationErrors["quiet"])
        vm.forwardQuietHoursEnd = 22
        XCTAssertEqual(vm.validationErrors["quiet"], "Quiet hours start and end must differ.")
    }

    func testValidationErrorsRequireSmsDestinationWhenSmsEnabled() {
        let vm = ForwardingSettingsViewModel()

        vm.forwardingEnabledSms = true
        vm.forwardSmsToPhone = false
        vm.forwardSmsToEmail = false

        let errors = vm.validationErrors

        XCTAssertEqual(
            errors["smsToggle"],
            "Choose at least one destination (phone or email)."
        )
    }

    func testValidationErrorsInvalidSmsPhone() {
        let vm = ForwardingSettingsViewModel()

        vm.forwardingEnabledSms = true
        vm.forwardSmsToPhone = true
        vm.forwardPhoneNumber = "bad-phone"

        let errors = vm.validationErrors

        XCTAssertEqual(
            errors["forwardPhoneNumber"],
            "Enter a valid E.164 phone (e.g. +15551234567)."
        )
    }

    func testValidationErrorsInvalidEmail() {
        let vm = ForwardingSettingsViewModel()

        vm.forwardingEnabledSms = true
        vm.forwardSmsToEmail = true
        vm.forwardEmail = "bad-email"

        let errors = vm.validationErrors

        XCTAssertEqual(errors["forwardEmail"], "Enter a valid email.")
    }

    func testValidationErrorsInvalidCallForwardPhone() {
        let vm = ForwardingSettingsViewModel()

        vm.forwardingEnabledCalls = true
        vm.forwardToPhoneE164 = "bad-phone"

        let errors = vm.validationErrors

        XCTAssertEqual(
            errors["forwardToPhoneE164"],
            "Enter a valid E.164 phone."
        )
    }

    func testValidationErrorsInvalidQuietHours() {
        let vm = ForwardingSettingsViewModel()

        vm.forwardQuietHoursStart = 24
        vm.forwardQuietHoursEnd = -1

        let errors = vm.validationErrors

        XCTAssertEqual(
            errors["quiet"],
            "Quiet hours must be between 0 and 23."
        )
    }

    func testValidationErrorsEmptyForValidSettings() {
        let vm = ForwardingSettingsViewModel()

        vm.forwardingEnabledSms = true
        vm.forwardSmsToPhone = true
        vm.forwardPhoneNumber = "+15551234567"
        vm.forwardSmsToEmail = true
        vm.forwardEmail = "test@example.com"

        vm.forwardingEnabledCalls = true
        vm.forwardToPhoneE164 = "+15559876543"

        vm.forwardQuietHoursStart = 22
        vm.forwardQuietHoursEnd = 7

        XCTAssertTrue(vm.validationErrors.isEmpty)
    }

    func testLegacyZoneDefaultsToDeviceAndSavedZoneSurvivesAnotherDevice() {
        let first = ForwardingSettingsViewModel(deviceTimeZone: "America/Denver")
        let legacy = ForwardingSettingsDTO.empty
        first.load(from: legacy)
        XCTAssertEqual(first.forwardQuietHoursTimeZone, "America/Denver")
        XCTAssertTrue(first.hasChanges)
        let saved = first.makeRequest()
        let second = ForwardingSettingsViewModel(deviceTimeZone: "Europe/London")
        second.load(from: saved)
        XCTAssertEqual(second.forwardQuietHoursTimeZone, "America/Denver")
        XCTAssertFalse(second.hasChanges)
    }

    func testInvalidZoneCannotBeSaved() {
        let vm = ForwardingSettingsViewModel(deviceTimeZone: "UTC")
        vm.load(from: makeDTO())
        vm.forwardQuietHoursTimeZone = "MST"
        XCTAssertNotNil(vm.validationErrors["timeZone"])
        vm.forwardQuietHoursTimeZone = "America/Denver"
        XCTAssertNil(vm.validationErrors["timeZone"])
    }
}

// MARK: - Helpers

private func makeDTO() -> ForwardingSettingsDTO {
    ForwardingSettingsDTO(
        forwardingEnabledSms: true,
        forwardSmsToPhone: true,
        forwardPhoneNumber: "+15551234567",
        forwardSmsToEmail: true,
        forwardEmail: "test@example.com",
        forwardingEnabledCalls: true,
        forwardToPhoneE164: "+15559876543",
        forwardQuietHoursStart: 22,
        forwardQuietHoursEnd: 7,
        forwardQuietHoursTimeZone: "America/Denver"
    )
}
