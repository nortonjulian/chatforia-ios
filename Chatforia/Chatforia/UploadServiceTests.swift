import XCTest
@testable import Chatforia

@MainActor
final class UploadServiceTests: XCTestCase {

    func testUploadResultDTODecodesFullResponse() throws {
        let json = """
        {
          "ok": true,
          "key": "uploads/test.jpg",
          "url": "https://example.com/test.jpg",
          "access": "public",
          "expiresSec": 3600,
          "contentType": "image/jpeg",
          "size": 12345
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(
            UploadResultDTO.self,
            from: json
        )

        XCTAssertEqual(result.ok, true)
        XCTAssertEqual(result.key, "uploads/test.jpg")
        XCTAssertEqual(result.url, "https://example.com/test.jpg")
        XCTAssertEqual(result.access, "public")
        XCTAssertEqual(result.expiresSec, 3600)
        XCTAssertEqual(result.contentType, "image/jpeg")
        XCTAssertEqual(result.size, 12345)
    }

    func testUploadResultDTODecodesRequiredOnlyFields() throws {
        let json = """
        {
          "url": "https://example.com/file.jpg"
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(
            UploadResultDTO.self,
            from: json
        )

        XCTAssertNil(result.ok)
        XCTAssertNil(result.key)
        XCTAssertEqual(result.url, "https://example.com/file.jpg")
        XCTAssertNil(result.access)
        XCTAssertNil(result.expiresSec)
        XCTAssertNil(result.contentType)
        XCTAssertNil(result.size)
    }

    func testAvatarUploadResponseDecodesAvatarURL() throws {
        let json = """
        {
          "avatarUrl": "https://example.com/avatar.jpg"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(
            AvatarUploadResponse.self,
            from: json
        )

        XCTAssertEqual(
            response.avatarUrl,
            "https://example.com/avatar.jpg"
        )
    }

    func testUploadAudioThrowsWhenFileDoesNotExist() async {
        let missingURL = URL(fileURLWithPath: "/tmp/missing-audio-file.m4a")

        do {
            _ = try await UploadService.shared.uploadAudio(
                fileURL: missingURL,
                token: "token"
            )

            XCTFail("Expected uploadAudio to throw for missing file")
        } catch {
            XCTAssertTrue(true)
        }
    }

    func testUploadVideoThrowsWhenFileDoesNotExist() async {
        let missingURL = URL(fileURLWithPath: "/tmp/missing-video-file.mp4")

        do {
            _ = try await UploadService.shared.uploadVideo(
                fileURL: missingURL,
                token: "token",
                fileName: "video.mp4",
                mimeType: "video/mp4"
            )

            XCTFail("Expected uploadVideo to throw for missing file")
        } catch {
            XCTAssertTrue(true)
        }
    }
}
