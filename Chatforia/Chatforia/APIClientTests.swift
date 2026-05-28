import XCTest
@testable import Chatforia

final class APIClientTests: XCTestCase {

    func testAPIRequestDefaultsRequiresAuthToTrue() {
        let request = APIRequest(
            path: "messages",
            method: .GET
        )

        XCTAssertTrue(request.requiresAuth)
    }

    func testAPIRequestCanDisableAuth() {
        let request = APIRequest(
            path: "auth/register",
            method: .POST,
            requiresAuth: false
        )

        XCTAssertFalse(request.requiresAuth)
    }

    func testUnauthorizedErrorDescriptionExists() {
        let error = APIError.unauthorized

        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
    }

    func testInvalidURLErrorDescriptionExists() {
        let error = APIError.invalidURL

        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
    }

    func testServerErrorDescriptionContainsStatusCode() {
        let error = APIError.server(
            status: 500,
            message: "Internal Server Error"
        )

        let description = error.errorDescription ?? ""

        XCTAssertTrue(description.contains("500"))
    }

    func testSendThrowsUnauthorizedWhenTokenMissing() async {
        do {
            let _: EmptyResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "messages",
                    method: .GET,
                    requiresAuth: true
                ),
                token: nil
            )

            XCTFail("Expected APIError.unauthorized")
        } catch let error as APIError {
            guard case .unauthorized = error else {
                XCTFail("Expected APIError.unauthorized, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected APIError.unauthorized, got \(error)")
        }
    }

    func testUploadMultipartThrowsUnauthorizedWithoutToken() async {
        do {
            _ = try await APIClient.shared.uploadMultipart(
                path: "upload",
                token: nil,
                fieldName: "file",
                fileData: Data(),
                fileName: "test.jpg",
                mimeType: "image/jpeg"
            )

            XCTFail("Expected APIError.unauthorized")
        } catch let error as APIError {
            guard case .unauthorized = error else {
                XCTFail("Expected APIError.unauthorized, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected APIError.unauthorized, got \(error)")
        }
    }
    
    func testBuildURLSimplePath() throws {

        let url = try APIClient.shared.buildURL(
            from: APIRequest(
                path: "auth/register",
                method: .POST
            )
        )

        XCTAssertTrue(
            url.absoluteString.contains("auth/register")
        )
    }

    func testBuildURLPreservesQueryString() throws {
        let url = try APIClient.shared.buildURL(
            from: APIRequest(
                path: "messages?limit=20&page=1",
                method: .GET
            )
        )

        XCTAssertTrue(url.path.contains("messages"))
        XCTAssertEqual(url.query, "limit=20&page=1")
    }
}
