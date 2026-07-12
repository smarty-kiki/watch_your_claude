import Foundation

/// A single throughput data point — one API response's generation speed.
struct ThroughputPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let inputTokensPerSecond: Double
    let outputTokensPerSecond: Double
    let model: String

    static func maxBySecond(_ points: [ThroughputPoint]) -> [ThroughputPoint] {
        let grouped = Dictionary(grouping: points) { point in
            point.timestamp.timeIntervalSince1970.rounded(.down)
        }
        return grouped.compactMap { (_, group) in
            guard let first = group.first else { return nil }
            return ThroughputPoint(
                timestamp: first.timestamp,
                inputTokensPerSecond: group.map(\.inputTokensPerSecond).max() ?? 0,
                outputTokensPerSecond: group.map(\.outputTokensPerSecond).max() ?? 0,
                model: first.model
            )
        }.sorted { $0.timestamp < $1.timestamp }
    }
}
