import Foundation

enum AppEnvironment {

    static let apiBaseURL: URL = {
        #if DEBUG
        return URL(string: "https://api.chatforia.com")!
        #elseif STAGING
        return URL(string: "https://staging-api.chatforia.com")!
        #else
        return URL(string: "https://api.chatforia.com")!
        #endif
    }()

    static let requestTimeout: TimeInterval = {
        #if DEBUG
        return 60
        #else
        return 30
        #endif
    }()
    
    static let tenorAPIKey: String = {
        guard
            let value = Bundle.main.infoDictionary?["TENOR_API_KEY"] as? String,
            !value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
        else {
            assertionFailure("Missing TENOR_API_KEY in build settings")
            return ""
        }
        return value
    }()

    static func configureSendQueueHandlersIfNeeded() {
        guard !SendQueueManager.isConfiguredForHandlers else { return }
        SendQueueManager.isConfiguredForHandlers = true

        // MARK: - SEND JOB HANDLER

        SendQueueManager.shared.sendJobHandler = { job, completion in
            print("🚀 sendJobHandler invoked for \(job.clientMessageId)")

            let request = APIRequest(
                path: "messages",
                method: .POST,
                body: job.bodyJSON,
                requiresAuth: true
            )

            Task {
                do {
                    guard let token = TokenStore.shared.read(), !token.isEmpty else {
                        print("❌ sendJobHandler missing auth token")
                        completion(.permanentFailure)
                        return
                    }

                    let (data, _) = try await APIClient.shared.sendRaw(request, token: token)

                    let decoder = JSONDecoder.tolerantISO8601Decoder()

                    struct MessageEnvelopeResponse: Decodable {
                        let message: MessageDTO
                    }

                    struct ShapedEnvelope: Decodable {
                        let shaped: MessageDTO
                    }

                    struct ItemEnvelope: Decodable {
                        let item: MessageDTO
                    }

                    // Try decoding in order of likelihood
                    if let dto = try? decoder.decode(MessageDTO.self, from: data) {
                        completion(.success(serverMessage: dto))
                        return
                    }

                    if let env = try? decoder.decode(MessageEnvelopeResponse.self, from: data) {
                        completion(.success(serverMessage: env.message))
                        return
                    }

                    if let env = try? decoder.decode(ShapedEnvelope.self, from: data) {
                        completion(.success(serverMessage: env.shaped))
                        return
                    }

                    if let env = try? decoder.decode(ItemEnvelope.self, from: data) {
                        completion(.success(serverMessage: env.item))
                        return
                    }

                    print("❌ decode failed")
                    completion(.temporaryFailure)

                } catch {
                    print("❌ sendJobHandler error:", error)

                    let nsError = error as NSError
                    let isRetryable =
                        nsError.code == NSURLErrorNotConnectedToInternet ||
                        nsError.code == NSURLErrorTimedOut ||
                        nsError.code == NSURLErrorNetworkConnectionLost ||
                        nsError.code == NSURLErrorCannotConnectToHost ||
                        nsError.code == NSURLErrorCannotFindHost ||
                        (500...599).contains(nsError.code)

                    completion(isRetryable ? .temporaryFailure : .permanentFailure)
                }
            }
        }

        // MARK: - SUCCESS CALLBACK

        SendQueueManager.shared.sendSuccessCallback = { clientMessageId, serverMessage in
            DispatchQueue.main.async {
                guard let serverMessage else { return }

                let normalized = MessageDTO(
                    id: serverMessage.id,
                    contentCiphertext: serverMessage.contentCiphertext,
                    rawContent: serverMessage.rawContent,
                    translations: serverMessage.translations,
                    translatedFrom: serverMessage.translatedFrom,
                    translatedForMe: serverMessage.translatedForMe,
                    encryptedKeyForMe: serverMessage.encryptedKeyForMe,
                    imageUrl: serverMessage.imageUrl,
                    audioUrl: serverMessage.audioUrl,
                    audioDurationSec: serverMessage.audioDurationSec,
                    attachments: serverMessage.attachments,
                    isExplicit: serverMessage.isExplicit,
                    createdAt: serverMessage.createdAt,
                    expiresAt: serverMessage.expiresAt,
                    editedAt: serverMessage.editedAt,
                    deletedBySender: serverMessage.deletedBySender,
                    deletedForAll: serverMessage.deletedForAll,
                    deletedAt: serverMessage.deletedAt,
                    deletedById: serverMessage.deletedById,
                    sender: serverMessage.sender,
                    readBy: serverMessage.readBy,
                    chatRoomId: serverMessage.chatRoomId,
                    reactionSummary: serverMessage.reactionSummary,
                    myReactions: serverMessage.myReactions,
                    revision: serverMessage.revision,
                    clientMessageId: serverMessage.clientMessageId ?? clientMessageId
                )

                // ✅ FIX: use existing MessageStore API
                MessageStore.shared.replaceOptimisticMessage(
                    clientMessageId: clientMessageId,
                    with: normalized
                )

                MessageStore.shared.setDeliveryState(
                    clientMessageId: clientMessageId,
                    state: DeliveryState.sent
                )
            }
        }

        // MARK: - FAILURE CALLBACK

        SendQueueManager.shared.sendFailedCallback = { clientMessageId in
            DispatchQueue.main.async {
                MessageStore.shared.setDeliveryState(
                    clientMessageId: clientMessageId,
                    state: DeliveryState.failed
                )
            }
        }
    }
}
