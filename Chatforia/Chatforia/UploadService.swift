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

private struct UploadIntentRequest: Encodable {
    let name: String
    let size: Int
    let mimeType: String
    let sha256: String?
}

private struct UploadIntentResponse: Decodable {
    let uploadUrl: String
    let key: String
    let expiresIn: Int?
    let publicUrl: String?
    let requiresComplete: Bool?
}

private struct UploadCompleteRequest: Encodable {
    let key: String
    let name: String
    let mimeType: String
    let size: Int
    let width: Int?
    let height: Int?
    let durationSec: Int?
    let sha256: String?
}

private struct UploadCompleteResponse: Decodable {
    let ok: Bool
    let file: UploadCompleteFileDTO
}

private struct UploadCompleteFileDTO: Decodable {
    let id: Int?
    let key: String?
    let url: String?
    let name: String?
    let contentType: String?
    let mimeType: String?
    let size: Int?
    let width: Int?
    let height: Int?
    let durationSec: Int?
    let thumbUrl: String?
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
        let sha = sha256Hex(data)

        let intentBody = try JSONEncoder().encode(
            UploadIntentRequest(
                name: fileName,
                size: data.count,
                mimeType: mimeType,
                sha256: sha
            )
        )

        let intent: UploadIntentResponse = try await APIClient.shared.send(
            APIRequest(
                path: "uploads/intent",
                method: .POST,
                body: intentBody,
                requiresAuth: true
            ),
            token: token
        )

        try await putFile(
            data: data,
            to: intent.uploadUrl,
            mimeType: mimeType
        )

        let completeBody = try JSONEncoder().encode(
            UploadCompleteRequest(
                key: intent.key,
                name: fileName,
                mimeType: mimeType,
                size: data.count,
                width: nil,
                height: nil,
                durationSec: nil,
                sha256: sha
            )
        )

        let complete: UploadCompleteResponse = try await APIClient.shared.send(
            APIRequest(
                path: "uploads/complete",
                method: .POST,
                body: completeBody,
                requiresAuth: true
            ),
            token: token
        )

        let file = complete.file
        let resolvedURL =
            file.url ??
            intent.publicUrl ??
            ""

        return UploadResultDTO(
            ok: complete.ok,
            key: file.key ?? intent.key,
            url: resolvedURL,
            access: nil,
            expiresSec: intent.expiresIn,
            contentType: file.contentType ?? file.mimeType ?? mimeType,
            size: file.size ?? data.count
        )
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

    private func putFile(
        data: Data,
        to uploadURLString: String,
        mimeType: String
    ) async throws {
        guard let url = URL(string: uploadURLString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func sha256Hex(_ data: Data) -> String? {
        guard #available(iOS 13.0, *) else { return nil }
        return SHA256Helper.hexDigest(data)
    }
}
