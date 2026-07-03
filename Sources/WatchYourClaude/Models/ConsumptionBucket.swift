import Foundation

/// Aggregated token consumption for a 10-minute window.
struct ConsumptionBucket: Identifiable {
    let id = UUID()
    let startTime: Date
    let endTime: Date
    var projectTokens: [String: (input: Int, output: Int)] = [:]
    var modelTokens: [String: (input: Int, output: Int)] = [:]

    var totalInput: Int {
        projectTokens.values.reduce(0) { $0 + $1.input }
    }

    var totalOutput: Int {
        projectTokens.values.reduce(0) { $0 + $1.output }
    }
}
