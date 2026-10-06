import XCTest
@testable import Chatforia

@MainActor
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
    func testRegulatoryRequirementsDecodeNestedDocumentGroups() throws {
        let json = """
        {
          "end_user": [
            {
              "fields": [
                "first_name",
                "last_name",
                "email"
              ]
            }
          ],
          "supporting_document": [
            [
              {
                "requirement_name": "identity",
                "type": "identity",
                "accepted_documents": [
                  {
                    "name": "Passport",
                    "type": "passport"
                  }
                ]
              },
              {
                "requirement_name": "address",
                "type": "address",
                "accepted_documents": [
                  {
                    "name": "Utility Bill",
                    "type": "utility_bill"
                  }
                ]
              }
            ]
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(
            RegulatoryRequirementsDTO.self,
            from: json
        )

        XCTAssertEqual(
            decoded.endUser?.first?.fields,
            ["first_name", "last_name", "email"]
        )
        XCTAssertEqual(decoded.supportingDocument?.count, 1)
        XCTAssertEqual(decoded.supportingDocument?.first?.count, 2)
        XCTAssertEqual(
            decoded.supportingDocument?.first?.first?.requirementName,
            "identity"
        )
        XCTAssertEqual(
            decoded.supportingDocument?.first?.last?.requirementName,
            "address"
        )
    }

    func testRegulatoryRequirementsDecodeMixedDocumentGroups() throws {
        let json = """
        {
          "supporting_document": [
            [
              {
                "requirement_name": "identity",
                "type": "identity",
                "accepted_documents": [
                  {
                    "type": "passport"
                  }
                ]
              }
            ],
            {
              "requirement_name": "address",
              "type": "address",
              "accepted_documents": [
                {
                  "name": "Utility Bill",
                  "type": "utility_bill"
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(
            RegulatoryRequirementsDTO.self,
            from: json
        )

        XCTAssertEqual(decoded.supportingDocument?.count, 2)
        XCTAssertEqual(decoded.supportingDocument?[0].count, 1)
        XCTAssertEqual(decoded.supportingDocument?[1].count, 1)

        XCTAssertEqual(
            decoded.supportingDocument?[0][0].requirementName,
            "identity"
        )
        XCTAssertEqual(
            decoded.supportingDocument?[0][0]
                .acceptedDocuments?.first?.type,
            "passport"
        )

        XCTAssertEqual(
            decoded.supportingDocument?[1][0].requirementName,
            "address"
        )
        XCTAssertEqual(
            decoded.supportingDocument?[1][0]
                .acceptedDocuments?.first?.name,
            "Utility Bill"
        )
    }

    func testRegulatoryLeaseResponseDecodesRequiredState() throws {
        let json = """
        {
          "error": "VERIFICATION_REQUIRED",
          "decision": "VERIFICATION_REQUIRED",
          "requiresVerification": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(
            NumberRegulatoryLeaseResponseDTO.self,
            from: json
        )

        XCTAssertEqual(
            decoded.decision,
            "VERIFICATION_REQUIRED"
        )
        XCTAssertEqual(decoded.requiresVerification, true)
    }

    func testRegulatoryLeaseResponseDecodesPendingState() throws {
        let json = """
        {
          "error": "VERIFICATION_PENDING",
          "decision": "VERIFICATION_PENDING",
          "requiresVerification": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(
            NumberRegulatoryLeaseResponseDTO.self,
            from: json
        )

        XCTAssertEqual(
            decoded.decision,
            "VERIFICATION_PENDING"
        )
        XCTAssertEqual(decoded.requiresVerification, false)
    }

    func testRegulatoryVerificationStatePreservesExactLeaseInputs() {
        let state = NumberRegulatoryVerificationState(
            e164: "+15551234567",
            purchaseIntent: true,
            decision: "VERIFICATION_REQUIRED",
            requiresVerification: true
        )

        XCTAssertEqual(state.e164, "+15551234567")
        XCTAssertTrue(state.purchaseIntent)
        XCTAssertEqual(
            state.decision,
            "VERIFICATION_REQUIRED"
        )
        XCTAssertTrue(state.requiresVerification)
    }

}
