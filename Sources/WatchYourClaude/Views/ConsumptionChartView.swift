import SwiftUI
import Charts

struct ConsumptionChartView: View {
    let buckets: [ConsumptionBucket]
    @State private var grouping: Grouping = .byProject
    @State private var hoveredBucket: ConsumptionBucket?
    @State private var hoverX: CGFloat = 0

    enum Grouping: String, CaseIterable {
        case byProject = "By Project"
        case byModel = "By Model"
    }

    private struct BucketData: Identifiable {
        let id = UUID()
        let startTime: Date
        let label: String
        let inputTokens: Int
        let outputTokens: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Token Consumption (3h)")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Picker("Grouping", selection: $grouping) {
                    ForEach(Grouping.allCases, id: \.self) { g in
                        Text(g.rawValue).tag(g)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .scaleEffect(0.75)
                .frame(width: 130)
            }
            .padding(.horizontal, 4)

            if buckets.allSatisfy({ $0.totalInput == 0 && $0.totalOutput == 0 }) {
                emptyChart
            } else {
                chartView
            }
        }
    }

    private var emptyChart: some View {
        ZStack {
            Rectangle()
                .fill(Color.primary.opacity(0.03))
                .frame(height: 140)
            Text("No consumption data yet")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .cornerRadius(6)
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = buckets.first?.startTime else {
            let now = Date()
            return now.addingTimeInterval(-3 * 3600)...now
        }
        return first...first.addingTimeInterval(3 * 3600)
    }

    private var chartView: some View {
        Chart {
            ForEach(stackedData(), id: \.id) { item in
                BarMark(
                    x: .value("Time", item.startTime, unit: .minute),
                    y: .value("Tokens", item.inputTokens + item.outputTokens),
                    width: .fixed(14)
                )
                .foregroundStyle(by: .value("Key", item.label))
            }
        }
        .chartXScale(domain: xDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .minute, count: 30)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
            }
        }
        .chartForegroundStyleScale(range: [
            .blue, .purple, .orange, .green, .pink, .teal, .yellow, .red, .mint, .indigo
        ])
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            if let date = proxy.value(atX: loc.x, as: Date.self) {
                                hoveredBucket = findNearestBucket(to: date)
                                hoverX = loc.x
                            }
                        case .ended:
                            hoveredBucket = nil
                        }
                    }
                    .overlay {
                        if let bucket = hoveredBucket, bucket.totalInput + bucket.totalOutput > 0 {
                            consumptionTooltip(for: bucket)
                                .position(x: clampX(hoverX, width: geo.size.width), y: 14)
                        }
                    }
            }
        }
        .frame(height: 140)
    }

    private func findNearestBucket(to date: Date) -> ConsumptionBucket? {
        buckets.min(by: {
            abs($0.startTime.timeIntervalSince(date)) < abs($1.startTime.timeIntervalSince(date))
        })
    }

    private func clampX(_ x: CGFloat, width: CGFloat) -> CGFloat {
        let tooltipHalf: CGFloat = 85
        return min(max(x, tooltipHalf), width - tooltipHalf)
    }

    private func consumptionTooltip(for bucket: ConsumptionBucket) -> some View {
        let items: [(key: String, total: Int)] = {
            let dict: [String: (input: Int, output: Int)]
            switch grouping {
            case .byProject: dict = bucket.projectTokens
            case .byModel: dict = bucket.modelTokens
            }
            return dict.map { (key: $0.key, total: $0.value.input + $0.value.output) }
                .sorted { $0.total > $1.total }
        }()

        return VStack(alignment: .leading, spacing: 1) {
            Text("\(bucket.startTime.formatted(.dateTime.hour().minute())) - \(bucket.endTime.formatted(.dateTime.hour().minute()))")
                .font(.caption2)
                .foregroundColor(.secondary)
            ForEach(items.prefix(5), id: \.key) { item in
                HStack {
                    Text(item.key)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 90, alignment: .leading)
                    Text(formatTokens(item.total))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            if items.count > 5 {
                Text("+ \(items.count - 5) more")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(5)
        .frame(width: 140)
        .background(.regularMaterial)
        .cornerRadius(5)
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1000 { return "\(count / 1000)k" }
        return "\(count)"
    }

    private func stackedData() -> [BucketData] {
        var result: [BucketData] = []
        for bucket in buckets {
            let dict: [String: (input: Int, output: Int)]
            switch grouping {
            case .byProject:
                dict = bucket.projectTokens
            case .byModel:
                // Merge models with fewer tokens into "Other"
                var merged: [String: (input: Int, output: Int)] = [:]
                for (key, tokens) in bucket.modelTokens {
                    let short = modelShortName(key)
                    var existing = merged[short] ?? (0, 0)
                    existing.input += tokens.input
                    existing.output += tokens.output
                    merged[short] = existing
                }
                dict = merged
            }

            for (key, tokens) in dict {
                result.append(BucketData(
                    startTime: bucket.startTime,
                    label: key,
                    inputTokens: tokens.input,
                    outputTokens: tokens.output
                ))
            }
        }
        return result
    }

    private func modelShortName(_ full: String) -> String {
        // e.g. deepseek-v4-pro → v4-pro, claude-opus-4-7 → opus
        let parts = full.components(separatedBy: "-")
        if parts.count >= 3 {
            return parts.dropFirst().joined(separator: "-")
        }
        return full
    }
}
