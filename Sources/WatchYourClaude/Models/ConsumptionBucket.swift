import Foundation

struct TokenCount: Equatable {
    var input: Int = 0
    var output: Int = 0
}

/// Aggregated token consumption for a 10-minute window.
struct ConsumptionBucket: Identifiable, Equatable {
    let id = UUID()
    let startTime: Date
    let endTime: Date
    var projectTokens: [String: TokenCount] = [:]
    var modelTokens: [String: TokenCount] = [:]

    var totalInput: Int {
        projectTokens.values.reduce(0) { $0 + $1.input }
    }

    var totalOutput: Int {
        projectTokens.values.reduce(0) { $0 + $1.output }
    }
}
