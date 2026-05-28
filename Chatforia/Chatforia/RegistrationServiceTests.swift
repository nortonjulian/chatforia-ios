import XCTest
@testable import Chatforia

final class RegistrationServiceTests: XCTestCase {

    func testMakeRegistrationRequestTrimsUsernameAndEmail() {
        let service = RegistrationService()

        let request = service.makeRegistrationRequest(
            username: "  julian  ",
            email: "  julian@example.com  ",
            password: "password123"
        )

        XCTAssertEqual(request.username, "julian")
        XCTAssertEqual(request.email, "julian@example.com")
        XCTAssertEqual(request.password, "password123")
    }

    func testMakeRegistrationRequestConvertsEmptyPhoneToNil() {
        let service = RegistrationService()

        let request = service.makeRegistrationRequest(
            username: "julian",
            email: "julian@example.com",
            password: "password123",
            phone: "   ",
            smsConsent: true
        )

        XCTAssertNil(request.phone)
        XCTAssertNil(request.smsConsent)
    }

    func testMakeRegistrationRequestKeepsPhoneAndSmsConsentWhenPhonePresent() {
        let service = RegistrationService()

        let request = service.makeRegistrationRequest(
            username: "julian",
            email: "julian@example.com",
            password: "password123",
            phone: " 5551234567 ",
            smsConsent: true
        )

        XCTAssertEqual(request.phone, "5551234567")
        XCTAssertEqual(request.smsConsent, true)
    }

    func testMakeRegistrationRequestKeepsSmsConsentFalseWhenPhonePresent() {
        let service = RegistrationService()

        let request = service.makeRegistrationRequest(
            username: "julian",
            email: "julian@example.com",
            password: "password123",
            phone: "5551234567",
            smsConsent: false
        )

        XCTAssertEqual(request.phone, "5551234567")
        XCTAssertEqual(request.smsConsent, false)
    }
}
