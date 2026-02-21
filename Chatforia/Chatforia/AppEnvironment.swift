import Foundation

enum AppEnvironment {
    
    static let apiBaseURL: URL = {
        #if DEBUG
        URL(string: "http://localhost:5002")!
        #elseif STAGING
        URL(string: "https://staging-api.chatforia.com")!
        #else
        URL(string: "https://api.chatforia.com")!
        #endif
    }()
    
    static let requestTimeout: TimeInterval = {
        #if DEBUG
        60
        #else
        30
        #endif
    }()
    
    static func configureSendQueueHandlersIfNeeded() {
        guard !SendQueueManager.isConfiguredForHandlers else { return }
        SendQueueManager.isConfiguredForHandlers = true
        
        SendQueueManager.shared.sendJobHandler = { job, completion in
            let request = APIRequest(
                path: "messages",
                method: .POST,
                body: job.bodyJSON,
                requiresAuth: true
            )
            
            let token = TokenStore().read()   // or TokenStore.shared.read() after you add shared
            
            APIClient.shared.sendRaw(request, token) { result in
                switch result {
                case .success(let (data, _)):
                    handleSuccessfulResponse(data: data, completion: completion)
                    
                case .failure(let error):
                    let isRetryable = (error as? APIClientError)?.isRetryable == true ||
                                      error.isRetryableServerError
                    completion(isRetryable ? .temporaryFailure : .permanentFailure)
                }
            }
        }
        
        SendQueueManager.shared.sendSuccessCallback = { clientMessageId, serverMessage in
            DispatchQueue.main.async {
                MessageStore.shared.insertOrReplace(serverMessage)
            }
        }
        
        SendQueueManager.shared.sendFailedCallback = { clientMessageId in
            DispatchQueue.main.async {
                MessageStore.shared.markDeliveryState(
                    clientMessageId: clientMessageId,
                    state: .failed
                )
            }
        }
    }
    
    // ────────────────────────────────────────────────
    // Put this OUTSIDE the closure — at enum level
    // ────────────────────────────────────────────────
    private static func handleSuccessfulResponse(
        data: Data,
        completion: @escaping (SendAttemptResult) -> Void
    ) {
        let decoder = JSONDecoder.tolerantISO8601Decoder()
        
        // Option 1: direct MessageDTO at root
        if let dto = try? decoder.decode(MessageDTO.self, from: data) {
            // ← Replace next line with YOUR REAL conversion method
            // Examples of what it might be named in your code:
            //   let serverMsg = dto.toServerMessage()
            //   let serverMsg = dto.serverMessage
            //   let serverMsg = ServerMessage(from: dto)
            //   let serverMsg = dto.asServerMessage()
            
            if let serverMsg = dto.asServerMessageIfAvailable() {   // ← CHANGE THIS LINE
                completion(.success(serverMessage: serverMsg))
                return
            }
        }
        
        // Option 2: wrapped in { "item": MessageDTO }
        struct MessageEnvelope: Decodable {
            let item: MessageDTO
        }
        
        if let envelope = try? decoder.decode(MessageEnvelope.self, from: data),
           let serverMsg = envelope.item.asServerMessageIfAvailable() {   // ← CHANGE THIS TOO
            completion(.success(serverMessage: serverMsg))
            return
        }
        
        // If neither format matches → treat as server-side temporary issue
        completion(.temporaryFailure)
    }
}
