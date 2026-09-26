import Foundation

struct MyAssignedNumberDTO: Decodable {
    let number: AssignedNumberDTO?
}

struct AssignedNumberDTO: Decodable, Identifiable {
    var id: String { e164 }
    let e164: String
    let status: String?
    let capabilities: CapabilityList?
    let keepLocked: Bool?
    let releaseAfter: String?
    let holdUntil: String?
}

struct NumberPoolResponseDTO: Decodable {
    let numbers: [AvailableNumberDTO]?
    let error: String?
    let message: String?
}

struct AvailableNumberDTO: Decodable, Identifiable {
    var id: String { e164 ?? number ?? UUID().uuidString }
    let e164: String?
    let number: String?
    let locality: String?
    let local: String?
    let region: String?
    let display: String?
    let capabilities: CapabilityList?
}

struct LeaseNumberResponseDTO: Decodable {
    let ok: Bool?
    let number: AssignedNumberDTO?
    let error: String?
}

struct NumberRegulatoryLeaseResponseDTO: Decodable {
    let error: String?
    let message: String?
    let decision: String?
    let requiresVerification: Bool?
}

enum PhoneNumberLeaseError: Error, LocalizedError {
    case regulatory(NumberRegulatoryLeaseResponseDTO)

    var errorDescription: String? {
        switch self {
        case .regulatory(let response):
            return response.message
                ?? response.error
                ?? response.decision
                ?? "Regulatory verification is required."
        }
    }

    var regulatoryResponse: NumberRegulatoryLeaseResponseDTO? {
        guard case .regulatory(let response) = self else {
            return nil
        }
        return response
    }
}

struct CapabilityList: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let arr = try? container.decode([String].self) {
            values = arr.map { $0.lowercased() }
            return
        }

        if let dict = try? container.decode([String: Bool].self) {
            values = dict
                .filter { $0.value }
                .map { $0.key.lowercased() }
                .sorted()
            return
        }

        values = []
    }
}

struct RegulatoryRequirementsDTO: Decodable {
    let endUser: [RegulatoryEndUserRequirementDTO]?
    let supportingDocument: [[RegulatorySupportingDocumentRequirementDTO]]?

    enum CodingKeys: String, CodingKey {
        case endUser = "end_user"
        case supportingDocument = "supporting_document"
    }

    private struct SupportingDocumentGroup: Decodable {
        let entries: [RegulatorySupportingDocumentRequirementDTO]

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            if let group = try? container.decode(
                [RegulatorySupportingDocumentRequirementDTO].self
            ) {
                entries = group
                return
            }

            entries = [
                try container.decode(
                    RegulatorySupportingDocumentRequirementDTO.self
                )
            ]
        }
    }

    init(from decoder: Decoder) throws {
        let container =
            try decoder.container(keyedBy: CodingKeys.self)

        endUser = try container.decodeIfPresent(
            [RegulatoryEndUserRequirementDTO].self,
            forKey: .endUser
        )

        let groups = try container.decodeIfPresent(
            [SupportingDocumentGroup].self,
            forKey: .supportingDocument
        )

        supportingDocument = groups?.map(\.entries)
    }
}

struct RegulatoryEndUserRequirementDTO: Decodable {
    let fields: [String]?
}

struct RegulatorySupportingDocumentRequirementDTO: Decodable {
    let requirementName: String?
    let type: String?
    let acceptedDocuments: [RegulatoryAcceptedDocumentDTO]?

    enum CodingKeys: String, CodingKey {
        case requirementName = "requirement_name"
        case type
        case acceptedDocuments = "accepted_documents"
    }
}

struct RegulatoryAcceptedDocumentDTO: Decodable {
    let name: String?
    let type: String?
}

struct RegulatoryProfileDTO: Decodable {
    let endUserSid: String?
    let rejectionReason: String?
}

struct RegulatoryInitializeResponseDTO: Decodable {
    let initialized: Bool?
    let reused: Bool?
    let reason: String?
    let profile: RegulatoryProfileDTO?
    let requirements: RegulatoryRequirementsDTO?
    let validation: RegulatoryValidationDTO?
}

struct RegulatoryValidationDTO: Decodable {
    let missingFields: [String]?
}

struct RegulatoryStatusResponseDTO: Decodable {
    let allowed: Bool?
    let decision: String?
    let requiresVerification: Bool?
    let profile: RegulatoryProfileDTO?
    let error: String?
}

struct RegulatoryDocumentRequirementsResponseDTO: Decodable {
    let resolved: Bool?
    let reason: String?
    let requiredFields: [String]?
    let missingFields: [String]?
}

struct RegulatoryDocumentResponseDTO: Decodable {
    let provisioned: Bool?
    let reused: Bool?
    let reason: String?
    let requiredFields: [String]?
    let missingFields: [String]?
}

struct RegulatoryAssembleResponseDTO: Decodable {
    let assembled: Bool?
    let reason: String?
}

struct RegulatorySubmitResponseDTO: Decodable {
    let submitted: Bool?
    let reason: String?
}

final class NumberRegulatoryService {
    static let shared = NumberRegulatoryService()

    private init() {}

    private func sendAllowingRegulatoryConflict<Response: Decodable>(
        _ request: APIRequest,
        token: String?
    ) async throws -> Response {
        do {
            return try await APIClient.shared.send(
                request,
                token: token
            )
        } catch let apiError as APIError {
            guard case .server(
                let status,
                _,
                _,
                let body
            ) = apiError,
                  status == 409,
                  let body
            else {
                throw apiError
            }

            do {
                return try JSONDecoder.tolerantISO8601Decoder()
                    .decode(Response.self, from: body)
            } catch {
                throw APIError.decoding(error)
            }
        }
    }

    func initialize(
        e164: String,
        endUserAttributes: [String: String]? = nil,
        token: String?
    ) async throws -> RegulatoryInitializeResponseDTO {
        struct Body: Encodable {
            let e164: String
            let endUserAttributes: [String: String]?
        }

        let body = try JSONEncoder().encode(
            Body(
                e164: e164,
                endUserAttributes: endUserAttributes
            )
        )

        return try await sendAllowingRegulatoryConflict(
            APIRequest(
                path: "numbers/regulatory/initialize",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }

    func status(
        e164: String,
        token: String?
    ) async throws -> RegulatoryStatusResponseDTO {
        struct Body: Encodable {
            let e164: String
        }

        let body = try JSONEncoder().encode(Body(e164: e164))

        return try await APIClient.shared.send(
            APIRequest(
                path: "numbers/regulatory/status",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }

    func documentRequirements(
        e164: String,
        requirementName: String,
        documentType: String,
        token: String?
    ) async throws -> RegulatoryDocumentRequirementsResponseDTO {
        struct Body: Encodable {
            let e164: String
            let requirementName: String
            let documentType: String
        }

        let body = try JSONEncoder().encode(
            Body(
                e164: e164,
                requirementName: requirementName,
                documentType: documentType
            )
        )

        return try await sendAllowingRegulatoryConflict(
            APIRequest(
                path: "numbers/regulatory/document-requirements",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }

    func uploadDocument(
        e164: String,
        requirementName: String,
        documentType: String,
        attributes: [String: String],
        fileData: Data,
        fileName: String,
        mimeType: String,
        token: String?
    ) async throws -> RegulatoryDocumentResponseDTO {
        guard let token else {
            throw APIError.unauthorized
        }

        let allowedMimeTypes = [
            "image/jpeg",
            "image/png",
            "application/pdf"
        ]

        guard allowedMimeTypes.contains(mimeType) else {
            throw APIError.server(
                status: 400,
                message: "Unsupported regulatory document type."
            )
        }

        guard fileData.count <= 5 * 1024 * 1024 else {
            throw APIError.server(
                status: 400,
                message: "Regulatory documents must be 5 MB or smaller."
            )
        }

        let url: URL
        do {
            url = try APIClient.shared.buildURL(
                from: APIRequest(
                    path: "numbers/regulatory/documents",
                    method: .POST,
                    body: nil,
                    requiresAuth: true
                )
            )
        } catch {
            throw APIError.invalidURL
        }

        let attributesData = try JSONEncoder().encode(attributes)

        guard let attributesJSON =
            String(data: attributesData, encoding: .utf8)
        else {
            throw APIError.server(
                status: 400,
                message: "Could not encode regulatory document attributes."
            )
        }

        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpMethod = HTTPMethod.POST.rawValue
        request.timeoutInterval = AppEnvironment.requestTimeout
        request.setValue(
            "Bearer \(token)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        var body = Data()

        func appendTextPart(
            name: String,
            value: String
        ) {
            body.append(
                "--\(boundary)\r\n".data(using: .utf8)!
            )
            body.append(
                "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
                    .data(using: .utf8)!
            )
            body.append(
                value.data(using: .utf8)!
            )
            body.append(
                "\r\n".data(using: .utf8)!
            )
        }

        appendTextPart(name: "e164", value: e164)
        appendTextPart(
            name: "requirementName",
            value: requirementName
        )
        appendTextPart(
            name: "documentType",
            value: documentType
        )
        appendTextPart(
            name: "attributes",
            value: attributesJSON
        )

        body.append(
            "--\(boundary)\r\n".data(using: .utf8)!
        )
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n"
                .data(using: .utf8)!
        )
        body.append(
            "Content-Type: \(mimeType)\r\n\r\n"
                .data(using: .utf8)!
        )
        body.append(fileData)
        body.append(
            "\r\n".data(using: .utf8)!
        )
        body.append(
            "--\(boundary)--\r\n".data(using: .utf8)!
        )

        request.httpBody = body

        do {
            let (data, response) =
                try await URLSession.shared.data(for: request)

            guard let http =
                response as? HTTPURLResponse
            else {
                throw APIError.server(
                    status: -1,
                    message: "Non-HTTP response"
                )
            }

            if http.statusCode == 401 {
                throw APIError.unauthorized
            }

            if http.statusCode == 409 {
                do {
                    return try JSONDecoder
                        .tolerantISO8601Decoder()
                        .decode(
                            RegulatoryDocumentResponseDTO.self,
                            from: data
                        )
                } catch {
                    throw APIError.decoding(error)
                }
            }

            guard (200...299).contains(http.statusCode) else {
                let message =
                    String(data: data, encoding: .utf8)

                throw APIError.server(
                    status: http.statusCode,
                    message: message,
                    body: data
                )
            }

            do {
                return try JSONDecoder
                    .tolerantISO8601Decoder()
                    .decode(
                        RegulatoryDocumentResponseDTO.self,
                        from: data
                    )
            } catch {
                throw APIError.decoding(error)
            }
        } catch let apiError as APIError {
            throw apiError
        } catch {
            throw APIError.network(error)
        }
    }

    func assemble(
        e164: String,
        email: String,
        token: String?
    ) async throws -> RegulatoryAssembleResponseDTO {
        struct Body: Encodable {
            let e164: String
            let email: String
        }

        let body = try JSONEncoder().encode(
            Body(e164: e164, email: email)
        )

        return try await sendAllowingRegulatoryConflict(
            APIRequest(
                path: "numbers/regulatory/assemble",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }

    func submit(
        e164: String,
        token: String?
    ) async throws -> RegulatorySubmitResponseDTO {
        struct Body: Encodable {
            let e164: String
        }

        let body = try JSONEncoder().encode(Body(e164: e164))

        return try await APIClient.shared.send(
            APIRequest(
                path: "numbers/regulatory/submit",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }
}

final class PhoneNumberPoolService {
    static let shared = PhoneNumberPoolService()
    private init() {}

    func fetchMyNumber(token: String?) async throws -> MyAssignedNumberDTO {
        try await APIClient.shared.send(
            APIRequest(path: "numbers/my", method: .GET, requiresAuth: true),
            token: token
        )
    }

    func searchPool(
        country: String = "US",
        capability: String = "voice",
        areaCode: String? = nil,
        limit: Int = 25,
        forSale: Bool = false,
        token: String?
    ) async throws -> NumberPoolResponseDTO {
        var parts: [String] = [
            "country=\(country)",
            "capability=\(capability)",
            "limit=\(limit)",
            "forSale=\(forSale ? "true" : "false")"
        ]

        if let areaCode, !areaCode.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            parts.append("areaCode=\(areaCode)")
        }

        let path = "numbers/pool?\(parts.joined(separator: "&"))"

        return try await APIClient.shared.send(
            APIRequest(path: path, method: .GET, requiresAuth: true),
            token: token
        )
    }
    
    func leaseNumber(e164: String, purchaseIntent: Bool = false, token: String?) async throws -> LeaseNumberResponseDTO {
        struct Body: Encodable {
            let e164: String
            let purchaseIntent: Bool?
        }

        let body = try JSONEncoder().encode(
            Body(e164: e164, purchaseIntent: purchaseIntent ? true : nil)
        )

        do {
            return try await APIClient.shared.send(
                APIRequest(
                    path: "numbers/lease",
                    method: .POST,
                    body: body,
                    requiresAuth: true
                ),
                token: token
            )
        } catch let apiError as APIError {
            guard case .server(let status, _, _, let responseBody) = apiError,
                  status == 409,
                  let responseBody,
                  let regulatory =
                    try? JSONDecoder().decode(
                        NumberRegulatoryLeaseResponseDTO.self,
                        from: responseBody
                    ),
                  let decision = regulatory.decision,
                  [
                    "VERIFICATION_REQUIRED",
                    "VERIFICATION_PENDING",
                    "VERIFICATION_REJECTED"
                  ].contains(decision)
            else {
                throw apiError
            }

            throw PhoneNumberLeaseError.regulatory(regulatory)
        }
    }
}
