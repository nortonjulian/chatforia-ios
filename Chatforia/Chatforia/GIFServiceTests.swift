import XCTest
@testable import Chatforia

@MainActor
final class GIFServiceTests: XCTestCase {

    func testGIFPickerItemDecodes() throws {
        let json = """
        {
          "id": "gif-1",
          "title": "Funny GIF",
          "previewURL": "https://example.com/preview.gif",
          "fullURL": "https://example.com/full.gif",
          "tenorID": "tenor-1"
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(
            GIFPickerItem.self,
            from: json
        )

        XCTAssertEqual(item.id, "gif-1")
        XCTAssertEqual(item.title, "Funny GIF")
        XCTAssertEqual(item.previewURL?.absoluteString, "https://example.com/preview.gif")
        XCTAssertEqual(item.fullURL?.absoluteString, "https://example.com/full.gif")
        XCTAssertEqual(item.tenorID, "tenor-1")
    }

    func testGIFPickerItemDecodesWithNilURLs() throws {
        let json = """
        {
          "id": "gif-1",
          "title": "Funny GIF",
          "previewURL": null,
          "fullURL": null,
          "tenorID": null
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(
            GIFPickerItem.self,
            from: json
        )

        XCTAssertEqual(item.id, "gif-1")
        XCTAssertEqual(item.title, "Funny GIF")
        XCTAssertNil(item.previewURL)
        XCTAssertNil(item.fullURL)
        XCTAssertNil(item.tenorID)
    }

    func testGIFServiceErrorDescriptions() {
        XCTAssertEqual(
            GIFServiceError.invalidResponse.errorDescription,
            "Invalid GIF response."
        )

        XCTAssertEqual(
            GIFServiceError.badURL.errorDescription,
            "Invalid GIF URL."
        )
    }
}
