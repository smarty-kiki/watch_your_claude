import Foundation

/// A single API response event from the session JSONL, with token usage and timestamp.
struct TokenEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadInputTokens: Int
    let cacheCreationInputTokens: Int
    let model: String
    let projectName: String
    let sessionId: String
    let parentUuid: String?

    var totalTokens: Int { inputTokens + outputTokens }
    var totalInputTokens: Int { inputTokens + cacheReadInputTokens + cacheCreationInputTokens }
}
