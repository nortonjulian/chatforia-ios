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

    func uploadFile(
        data: Data,
        token: String,
        fileName: String,
        mimeType: String
    ) async throws -> UploadResultDTO {
        let responseData = try await APIClient.shared.uploadMultipart(
            path: "media/upload",
            token: token,
            fieldName: "file",
            fileData: data,
            fileName: fileName,
            mimeType: mimeType
        )

        let decoder = JSONDecoder.tolerantISO8601Decoder()
        return try decoder.decode(UploadResultDTO.self, from: responseData)
    }

    func uploadImage(data: Data, token: String) async throws -> UploadResultDTO {
        try await uploadFile(
            data: data,
            token: token,
            fileName: "image-\(Int(Date().timeIntervalSince1970)).jpg",
            mimeType: "image/jpeg"
        )
    }

    func uploadGIF(data: Data, token: String) async throws -> UploadResultDTO {
        try await uploadFile(
            data: data,
            token: token,
            fileName: "gif-\(Int(Date().timeIntervalSince1970)).gif",
            mimeType: "image/gif"
        )
    }

    func uploadAudio(fileURL: URL, token: String) async throws -> UploadResultDTO {
        let data = try Data(contentsOf: fileURL)

        return try await uploadFile(
            data: data,
            token: token,
            fileName: "voice-\(Int(Date().timeIntervalSince1970)).m4a",
            mimeType: "audio/m4a"
        )
    }
    
    func uploadVideo(
        fileURL: URL,
        token: String,
        fileName: String,
        mimeType: String
    ) async throws -> UploadResultDTO {
        let data = try Data(contentsOf: fileURL)

        return try await uploadFile(
            data: data,
            token: token,
            fileName: fileName,
            mimeType: mimeType
        )
    }
}
