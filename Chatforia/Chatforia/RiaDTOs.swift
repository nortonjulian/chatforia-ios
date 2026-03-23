import Foundation

struct RiaContextMessageDTO: Encodable {
    let role: String
    let content: String
}

struct SuggestRepliesRequest: Encodable {
    let messages: [RiaContextMessageDTO]
    let draft: String
    let filterProfanity: Bool
}

struct SuggestRepliesResponse: Decodable {
    let suggestions: [String]
}

struct RewriteTextRequest: Encodable {
    let text: String
    let tone: String
    let filterProfanity: Bool
}

struct RewriteTextResponse: Decodable {
    let rewrites: [String]
}

struct ChatRequest: Encodable {
    let messages: [RiaContextMessageDTO]
    let memoryEnabled: Bool
    let filterProfanity: Bool
}

struct ChatResponse: Decodable {
    let reply: String
}
