import XCTest
@testable import Chatforia

@MainActor
final class RegistrationServiceTests: XCTestCase {
    func testSignupTrimsIdentityAndPreservesPassword() throws {
        let request = RegistrationService().makeRegistrationRequest(
            username: " julian ", email: " julian@example.com ",
            password: "  Password!23  ")
        XCTAssertEqual(request.username, "julian")
        XCTAssertEqual(request.email, "julian@example.com")
        XCTAssertEqual(request.password, "  Password!23  ")
    }

    func testSignupBodyContainsNoPhoneConsentOrVerificationProof() throws {
        let request = RegistrationService().makeRegistrationRequest(
            username: "julian", email: "julian@example.com", password: "Password!23")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), Set(["username", "email", "password"]))
    }
}
