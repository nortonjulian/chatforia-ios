import XCTest
@testable import Chatforia

final class ESIMServiceTests: XCTestCase {

    func testBuildLPAUriBuildsExpectedFormat() {
        let uri = ESIMService.shared.test_buildLPAUri(
            smdp: "rsp.example.com",
            activationCode: "ABC123"
        )

        XCTAssertEqual(
            uri,
            "LPA:1$rsp.example.com$ABC123"
        )
    }

    func testBuildLPAUriReturnsNilForMissingSmdp() {
        let uri = ESIMService.shared.test_buildLPAUri(
            smdp: nil,
            activationCode: "ABC123"
        )

        XCTAssertNil(uri)
    }

    func testBuildLPAUriReturnsNilForMissingActivationCode() {
        let uri = ESIMService.shared.test_buildLPAUri(
            smdp: "rsp.example.com",
            activationCode: nil
        )

        XCTAssertNil(uri)
    }

    func testBuildLPAUriTrimsWhitespace() {
        let uri = ESIMService.shared.test_buildLPAUri(
            smdp: "  rsp.example.com  ",
            activationCode: "  ABC123  "
        )

        XCTAssertEqual(
            uri,
            "LPA:1$rsp.example.com$ABC123"
        )
    }

    func testInferredRegionReturnsEU() {
        let pack = makePack(product: "europe-10gb")

        XCTAssertEqual(
            ESIMService.shared.test_inferredRegion(from: pack),
            "EU"
        )
    }

    func testInferredRegionReturnsUK() {
        let pack = makePack(product: "uk-plan")

        XCTAssertEqual(
            ESIMService.shared.test_inferredRegion(from: pack),
            "UK"
        )
    }

    func testInferredRegionReturnsCanada() {
        let pack = makePack(product: "canada-unlimited")

        XCTAssertEqual(
            ESIMService.shared.test_inferredRegion(from: pack),
            "CA"
        )
    }

    func testInferredRegionReturnsAustralia() {
        let pack = makePack(product: "australia-pack")

        XCTAssertEqual(
            ESIMService.shared.test_inferredRegion(from: pack),
            "AU"
        )
    }

    func testInferredRegionReturnsJapan() {
        let pack = makePack(product: "japan-travel")

        XCTAssertEqual(
            ESIMService.shared.test_inferredRegion(from: pack),
            "JP"
        )
    }

    func testInferredRegionDefaultsToUS() {
        let pack = makePack(product: "unknown-region")

        XCTAssertEqual(
            ESIMService.shared.test_inferredRegion(from: pack),
            "US"
        )
    }

    func testInvalidResponseErrorDescriptionExists() {
        XCTAssertEqual(
            ESIMServiceError.invalidResponse.errorDescription,
            "The server returned an invalid response."
        )
    }

    func testServerErrorDescriptionReturnsMessage() {
        let error = ESIMServiceError.server(
            statusCode: 500,
            message: "Backend exploded"
        )

        XCTAssertEqual(
            error.errorDescription,
            "Backend exploded"
        )
    }
}

// MARK: - Helpers

private func makePack(product: String) -> DataPackOption {
    DataPackOption(
        id: "test",
        product: product,
        scope: .local,
        gb: 5,
        titleKey: "test.title",
        descriptionKey: "test.description"
    )
}
