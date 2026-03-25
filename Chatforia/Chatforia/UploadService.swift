import Foundation

struct UploadResultDTO: Decodable {
    let ok: Bool?
    let key: String?
    let url: String
    let access: String?
    let expiresSec: Int?
    let contentType: String?
    let size: Int?
}

final class UploadService {
    static let shared = UploadService()
    private init() {}

    func uploadImage(data: Data, token: String) async throws -> UploadResultDTO {
        let responseData = try await APIClient.shared.uploadMultipart(
            path: "media/upload",
            token: token,
            fieldName: "file",
            fileData: data,
            fileName: "sms-image.jpg",
            mimeType: "image/jpeg"
        )

        let decoder = JSONDecoder.tolerantISO8601Decoder()
        return try decoder.decode(UploadResultDTO.self, from: responseData)
    }
    
    func uploadAudio(fileURL: URL, token: String) async throws -> UploadResultDTO {
        let data = try Data(contentsOf: fileURL)

        let responseData = try await APIClient.shared.uploadMultipart(
            path: "media/upload",
            token: token,
            fieldName: "file",
            fileData: data,
            fileName: "voice-\(Int(Date().timeIntervalSince1970)).m4a",
            mimeType: "audio/m4a"
        )

        let decoder = JSONDecoder.tolerantISO8601Decoder()
        return try decoder.decode(UploadResultDTO.self, from: responseData)
    }
}
