import Foundation
import CryptoKit
import Security

struct PushInstallationIdentity: Codable, Equatable {
    let installationId: String
    let installationProof: String
}

struct PushCleanupGrant: Codable, Equatable {
    let installationId: String
    let generation: String
    let cleanupCapability: String
    let accountId: Int
    let sessionDigest: String
    let expiresAt: Date
}

struct PushTokenRevision: Codable, Equatable {
    let digest: String
    let revision: Int
}

struct PushAuthorityState: Codable, Equatable {
    var identity: PushInstallationIdentity?
    var current: PushCleanupGrant?
    var pending: [PushCleanupGrant] = []
    var revisions: [String: PushTokenRevision] = [:]
}

enum PushAuthorityClientError: Error {
    case fullSessionRequired
    case staleAccount
    case secureStorageUnavailable
    case pendingCleanupLimit
}

@MainActor
protocol PushAuthorityStateStoring {
    func load() throws -> PushAuthorityState
    func save(_ state: PushAuthorityState) throws
}

@MainActor
final class KeychainPushAuthorityStateStore: PushAuthorityStateStoring {
    private let service = Bundle.main.bundleIdentifier ?? "com.chatforia.Chatforia"
    private let account = "chatforia.push.session-authority.v1"

    func load() throws -> PushAuthorityState {
        guard let data = KeychainHelper.read(service: service, account: account) else {
            return PushAuthorityState()
        }
        return try JSONDecoder().decode(PushAuthorityState.self, from: data)
    }

    func save(_ state: PushAuthorityState) throws {
        let data = try JSONEncoder().encode(state)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updated = SecItemUpdate(query as CFDictionary,
                                    [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else {
            throw PushAuthorityClientError.secureStorageUnavailable
        }
        var added = query
        added[kSecValueData as String] = data
        added[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(added as CFDictionary, nil) == errSecSuccess else {
            throw PushAuthorityClientError.secureStorageUnavailable
        }
    }
}

struct PushActivationRequest: Encodable {
    let installationId: String
    let installationProof: String
    let deviceId: String
    let platform: String
    let appId: String
}

struct PushActivationResponse: Decodable {
    let generation: String
    let expiresAt: Date
    let cleanupCapability: String
}

struct AuthorizedPushRegistration: Encodable {
    let installationId: String
    let installationProof: String
    let generation: String
    let provider: String
    let environment: String
    let token: String
    let tokenRevision: Int
}

@MainActor
protocol PushAuthorityTransport {
    func activate(_ body: PushActivationRequest, token: String) async throws -> PushActivationResponse
    func register(_ body: AuthorizedPushRegistration, token: String) async throws
    func cleanup(_ grant: PushCleanupGrant) async throws
}

@MainActor
struct APIPushAuthorityTransport: PushAuthorityTransport {
    func activate(_ body: PushActivationRequest, token: String) async throws -> PushActivationResponse {
        let response: PushActivationResponse = try await APIClient.shared.send(
            APIRequest(path: "devices/push-authority/activate", method: .POST,
                       body: try JSONEncoder().encode(body)), token: token
        )
        return response
    }

    func register(_ body: AuthorizedPushRegistration, token: String) async throws {
        struct RegistrationResponse: Decodable { let registered: Bool }
        let response: RegistrationResponse = try await APIClient.shared.send(
            APIRequest(path: "devices/push-authority/register", method: .POST,
                       body: try JSONEncoder().encode(body)), token: token
        )
        guard response.registered else { throw PushAuthorityClientError.staleAccount }
    }

    func cleanup(_ grant: PushCleanupGrant) async throws {
        struct CleanupRequest: Encodable {
            let installationId: String
            let generation: String
            let cleanupCapability: String
        }
        let body = CleanupRequest(installationId: grant.installationId,
                                  generation: grant.generation,
                                  cleanupCapability: grant.cleanupCapability)
        _ = try await APIClient.shared.sendRaw(
            APIRequest(path: "devices/push-authority/cleanup", method: .POST,
                       body: try JSONEncoder().encode(body), requiresAuth: false,
                       isolatedSession: true), token: nil
        )
    }
}

// Account-independent installation identity; grants remain account and session
// scoped. Only cleanup capabilities and token digests are persisted, never JWTs.
@MainActor
final class PushSessionAuthority {
    static let shared = PushSessionAuthority()

    private let storage: PushAuthorityStateStoring
    private let transport: PushAuthorityTransport
    private let isCurrent: @MainActor (Int, String) -> Bool
    private let pendingLimit = 32

    init(
        storage: PushAuthorityStateStoring? = nil,
        transport: PushAuthorityTransport? = nil,
        isCurrent: (@MainActor (Int, String) -> Bool)? = nil
    ) {
        self.storage = storage ?? KeychainPushAuthorityStateStore()
        self.transport = transport ?? APIPushAuthorityTransport()
        self.isCurrent = isCurrent ?? { accountId, token in
            UserDefaults.standard.integer(forKey: "chatforia.currentUserId") == accountId &&
                TokenStore.shared.read() == token
        }
    }

    static func isFullSession(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return false }
        let raw = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = raw + String(repeating: "=", count: (4 - raw.count % 4) % 4)
        guard let data = Data(base64Encoded: padded),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = claims["typ"] as? String else { return false }
        // This is only an early client check. The server verifies the signature,
        // expiry, account and token version for every authenticated request.
        return type == "session"
    }

    static func tokenDigest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private func identity() throws -> PushInstallationIdentity {
        var state = try storage.load()
        if let identity = state.identity { return identity }
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard result == errSecSuccess else { throw PushAuthorityClientError.secureStorageUnavailable }
        let proof = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let identity = PushInstallationIdentity(
            installationId: UUID().uuidString.lowercased(), installationProof: proof
        )
        state.identity = identity
        try storage.save(state)
        return identity
    }

    private func appendPending(_ grant: PushCleanupGrant, to state: inout PushAuthorityState) throws {
        guard !state.pending.contains(grant) else { return }
        guard state.pending.count < pendingLimit else { throw PushAuthorityClientError.pendingCleanupLimit }
        state.pending.append(grant)
    }

    func endCurrentSession(matching expected: PushCleanupGrant? = nil) throws -> PushCleanupGrant? {
        var state = try storage.load()
        guard let grant = state.current else { return nil }
        if let expected, expected != grant { return nil }
        try appendPending(grant, to: &state)
        state.current = nil
        try storage.save(state)
        return grant
    }

    func confirmAuthenticatedLogout(_ grant: PushCleanupGrant?) throws {
        guard let grant else { return }
        var state = try storage.load()
        state.pending.removeAll { $0 == grant }
        try storage.save(state)
    }

    func retryPendingCleanup() async {
        guard let pending = try? storage.load().pending else { return }
        for grant in pending {
            do {
                try await transport.cleanup(grant)
                var state = try storage.load()
                state.pending.removeAll { $0 == grant }
                try storage.save(state)
            } catch {
                // Retain the capability for a later foreground/network retry.
                debugLog("Push authority cleanup pending:", error)
            }
        }
    }

    func cleanupAfterMissingSession() async {
        do { _ = try endCurrentSession() }
        catch { debugLog("Push authority cleanup could not be saved:", error) }
        await retryPendingCleanup()
    }

    func register(
        provider: String, pushToken: String, accountId: Int,
        authToken: String, deviceId: String
    ) async throws {
        guard Self.isFullSession(authToken) else { throw PushAuthorityClientError.fullSessionRequired }
        guard isCurrent(accountId, authToken) else { throw PushAuthorityClientError.staleAccount }
        await retryPendingCleanup()
        guard isCurrent(accountId, authToken) else { throw PushAuthorityClientError.staleAccount }

        let identity = try identity()
        let sessionDigest = Self.tokenDigest(authToken)
        var state = try storage.load()
        var grant = state.current
        if grant?.accountId != accountId || grant?.sessionDigest != sessionDigest ||
            (grant?.expiresAt ?? .distantPast) <= Date() {
            // Reserve space before issuing another cleanup capability. A full
            // queue must fail closed rather than discard a revocation grant.
            guard state.pending.count < pendingLimit - (state.current == nil ? 0 : 1) else {
                throw PushAuthorityClientError.pendingCleanupLimit
            }
            let response = try await transport.activate(
                PushActivationRequest(installationId: identity.installationId,
                                      installationProof: identity.installationProof,
                                      deviceId: deviceId, platform: "ios",
                                      appId: Bundle.main.bundleIdentifier ?? "com.chatforia.Chatforia"),
                token: authToken
            )
            let activated = PushCleanupGrant(
                installationId: identity.installationId,
                generation: response.generation,
                cleanupCapability: response.cleanupCapability,
                accountId: accountId, sessionDigest: sessionDigest,
                expiresAt: response.expiresAt
            )
            state = try storage.load()
            if isCurrent(accountId, authToken) {
                if let previous = state.current, previous != activated {
                    try appendPending(previous, to: &state)
                }
                state.current = activated
                try storage.save(state)
                grant = activated
            } else {
                try appendPending(activated, to: &state)
                try storage.save(state)
                Task { await self.retryPendingCleanup() }
                throw PushAuthorityClientError.staleAccount
            }
        }
        guard let grant, isCurrent(accountId, authToken) else {
            throw PushAuthorityClientError.staleAccount
        }

        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        let digest = Self.tokenDigest("\(environment):\(pushToken)")
        state = try storage.load()
        let previousRevision = state.revisions[provider]
        let revision = previousRevision?.digest == digest
            ? previousRevision!.revision : (previousRevision?.revision ?? 0) + 1
        state.revisions[provider] = PushTokenRevision(digest: digest, revision: revision)
        try storage.save(state)

        guard isCurrent(accountId, authToken) else { throw PushAuthorityClientError.staleAccount }
        do {
            try await transport.register(
                AuthorizedPushRegistration(
                    installationId: identity.installationId,
                    installationProof: identity.installationProof,
                    generation: grant.generation, provider: provider,
                    environment: environment, token: pushToken,
                    tokenRevision: revision
                ), token: authToken
            )
        } catch {
            let revoked: Bool
            switch error {
            case APIError.unauthorized:
                revoked = true
            case APIError.server(let status, let code, _, _):
                revoked = status == 403 &&
                    (code == "PUSH_AUTHORITY_REVOKED" || code == "DEVICE_NOT_ELIGIBLE")
            default:
                revoked = false
            }
            if revoked {
                _ = try? endCurrentSession(matching: grant)
                Task { await self.retryPendingCleanup() }
            }
            throw error
        }
        guard isCurrent(accountId, authToken) else {
            _ = try? endCurrentSession(matching: grant)
            Task { await self.retryPendingCleanup() }
            throw PushAuthorityClientError.staleAccount
        }
    }
}
