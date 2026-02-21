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
            
            // 🔴 TOKEN NO LONGER NEEDED — APIClient attaches it automatically
            APIClient.shared.sendRaw(request) { result in
                switch result {
                case .success(let (data, _)):
                    let decoder = JSONDecoder()
                    
                    if let dto = try? decoder.decode(MessageDTO.self, from: data) {
                        completion(.success(serverMessage: nil)) // placeholder for now
                    } else {
                        completion(.temporaryFailure)
                    }
                    
                case .failure(let error):
                    let isRetryable =
                        (error as? APIClientError)?.isRetryable == true ||
                        ((error as NSError).code >= 500 && (error as NSError).code < 600)
                    
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
}
