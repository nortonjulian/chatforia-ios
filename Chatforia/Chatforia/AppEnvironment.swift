import Foundation

enum AppEnvironment {

    static let apiBaseURL: URL = {
        #if DEBUG
        return URL(string: "http://10.0.0.57:5002")!
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

    static func configureSendQueueHandlersIfNeeded() {
        guard !SendQueueManager.isConfiguredForHandlers else { return }
        SendQueueManager.isConfiguredForHandlers = true

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

                    print("🔑 queue token present: true")

                    let (data, _) = try await APIClient.shared.sendRaw(request, token: token)
                    print("✅ sendRaw returned for \(job.clientMessageId), bytes=\(data.count)")

                    let decoder = JSONDecoder.tolerantISO8601Decoder()

                    struct ShapedEnvelope: Decodable {
                        let shaped: MessageDTO
                    }

                    struct ItemEnvelope: Decodable {
                        let item: MessageDTO
                    }

                    if let dto = try? decoder.decode(MessageDTO.self, from: data) {
                        print("✅ decoded direct MessageDTO id=\(dto.id) clientMessageId=\(dto.clientMessageId ?? "nil")")
                        completion(.success(serverMessage: dto))
                        return
                    }

                    if let env = try? decoder.decode(ShapedEnvelope.self, from: data) {
                        print("✅ decoded shaped MessageDTO id=\(env.shaped.id) clientMessageId=\(env.shaped.clientMessageId ?? "nil")")
                        completion(.success(serverMessage: env.shaped))
                        return
                    }

                    if let env = try? decoder.decode(ItemEnvelope.self, from: data) {
                        print("✅ decoded item MessageDTO id=\(env.item.id) clientMessageId=\(env.item.clientMessageId ?? "nil")")
                        completion(.success(serverMessage: env.item))
                        return
                    }

                    let rawPreview = String(data: data.prefix(1000), encoding: .utf8) ?? "<non-utf8 data>"
                    print("❌ queued send decode failed. RAW: \(rawPreview)")
                    completion(.temporaryFailure)
                } catch {
                    print("❌ sendJobHandler network error for \(job.clientMessageId): \(error)")
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

        SendQueueManager.shared.sendSuccessCallback = { clientMessageId, serverMessage in
            DispatchQueue.main.async {
                print("🎉 sendSuccessCallback for \(clientMessageId)")
                guard serverMessage != nil else { return }
                MessageStore.shared.markDeliveryState(
                    clientMessageId: clientMessageId,
                    state: .sent
                )
            }
        }

        SendQueueManager.shared.sendFailedCallback = { clientMessageId in
            DispatchQueue.main.async {
                print("🛑 sendFailedCallback for \(clientMessageId)")
                MessageStore.shared.markDeliveryState(
                    clientMessageId: clientMessageId,
                    state: .failed
                )
            }
        }
    }
}
