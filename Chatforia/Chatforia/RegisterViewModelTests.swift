import XCTest
@testable import Chatforia

@MainActor
final class RegisterViewModelTests: XCTestCase {

    func testEmptyUsernameShowsUsernameRequiredError() async {
        let vm = RegisterViewModel()

        vm.username = ""
        vm.email = "test@example.com"
        vm.password = "password123"
        vm.confirmPassword = "password123"

        await vm.submit(auth: AuthStore(), languageCode: "en")

        XCTAssertEqual(vm.errorMessage, appText("auth.usernameRequired", languageCode: "en"))
        XCTAssertFalse(vm.isSubmitting)
    }

    func testInvalidEmailShowsValidEmailRequiredError() async {
        let vm = RegisterViewModel()

        vm.username = "julian"
        vm.email = "bad-email"
        vm.password = "password123"
        vm.confirmPassword = "password123"

        await vm.submit(auth: AuthStore(), languageCode: "en")

        XCTAssertEqual(vm.errorMessage, appText("auth.validEmailRequired", languageCode: "en"))
        XCTAssertFalse(vm.isSubmitting)
    }

    func testEmptyPasswordShowsPasswordRequiredError() async {
        let vm = RegisterViewModel()

        vm.username = "julian"
        vm.email = "test@example.com"
        vm.password = ""
        vm.confirmPassword = ""

        await vm.submit(auth: AuthStore(), languageCode: "en")

        XCTAssertEqual(vm.errorMessage, appText("auth.passwordRequired", languageCode: "en"))
        XCTAssertFalse(vm.isSubmitting)
    }

    func testShortPasswordShowsMinLengthError() async {
        let vm = RegisterViewModel()

        vm.username = "julian"
        vm.email = "test@example.com"
        vm.password = "123"
        vm.confirmPassword = "123"

        await vm.submit(auth: AuthStore(), languageCode: "en")

        XCTAssertEqual(vm.errorMessage, appText("auth.passwordMinLength", languageCode: "en"))
        XCTAssertFalse(vm.isSubmitting)
    }

    func testPasswordMismatchShowsPasswordsDontMatchError() async {
        let vm = RegisterViewModel()

        vm.username = "julian"
        vm.email = "test@example.com"
        vm.password = "password123"
        vm.confirmPassword = "different123"

        await vm.submit(auth: AuthStore(), languageCode: "en")

        XCTAssertEqual(vm.errorMessage, appText("auth.passwordsDontMatch", languageCode: "en"))
        XCTAssertFalse(vm.isSubmitting)
    }

    func testPhoneWithoutSmsConsentShowsConsentRequiredError() async {
        let vm = RegisterViewModel()

        vm.username = "julian"
        vm.email = "test@example.com"
        vm.password = "password123"
        vm.confirmPassword = "password123"
        vm.phone = "5551234567"
        vm.smsConsent = false

        await vm.submit(auth: AuthStore(), languageCode: "en")

        XCTAssertEqual(vm.errorMessage, appText("auth.smsConsentRequired", languageCode: "en"))
        XCTAssertFalse(vm.isSubmitting)
    }
}
