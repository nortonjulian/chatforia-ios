import XCTest
@testable import Chatforia

@MainActor
final class PhoneContactsServiceTests: XCTestCase {

    func testNormalizePhoneReturnsNilForBlankInput() {
        XCTAssertNil(PhoneContactsService.normalizePhone(""))
        XCTAssertNil(PhoneContactsService.normalizePhone("   "))
    }

    func testNormalizePhoneReturnsNilForTooFewDigits() {
        XCTAssertNil(PhoneContactsService.normalizePhone("123456"))
    }

    func testNormalizePhoneKeepsLeadingPlus() {
        let result = PhoneContactsService.normalizePhone("+44 20 7946 0958")

        XCTAssertEqual(result, "+442079460958")
    }

    func testNormalizePhoneFormatsTenDigitUSNumber() {
        let result = PhoneContactsService.normalizePhone("(555) 123-4567")

        XCTAssertEqual(result, "+15551234567")
    }

    func testNormalizePhoneFormatsElevenDigitUSNumberStartingWithOne() {
        let result = PhoneContactsService.normalizePhone("1 (555) 123-4567")

        XCTAssertEqual(result, "+15551234567")
    }

    func testNormalizePhoneAddsPlusForInternationalNumberWithoutPlus() {
        let result = PhoneContactsService.normalizePhone("442079460958")

        XCTAssertEqual(result, "+442079460958")
    }

    func testNormalizePhoneRemovesFormattingCharacters() {
        let result = PhoneContactsService.normalizePhone("+1-555.123.4567")

        XCTAssertEqual(result, "+15551234567")
    }
}
