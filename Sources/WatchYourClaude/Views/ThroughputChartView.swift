import SwiftUI
import Charts

struct ThroughputChartView: View {
    let points: [ThroughputPoint]

    @State private var hoveredPoint: ThroughputPoint?
    @State private var hoverX: CGFloat = 0

    private struct ChartData: Identifiable {
        let id = UUID()
        let timestamp: Date
        let value: Double
    }

    private var chartData: [ChartData] {
        let maxVal = points.map(\.outputTokensPerSecond).max() ?? 100
        return points.map {
            ChartData(timestamp: $0.timestamp, value: $0.outputTokensPerSecond / maxVal)
        }
    }

    private var maxOutput: Double { points.map(\.outputTokensPerSecond).max() ?? 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "speedometer")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Generation Speed")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                if !points.isEmpty {
                    Text("Peak: \(Int(maxOutput))/s")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)

            if points.isEmpty {
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
                .frame(height: 120)
            Text("Waiting for generation activity...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .cornerRadius(6)
    }

    private var chartView: some View {
        Chart {
            ForEach(chartData) { item in
                BarMark(
                    x: .value("Time", item.timestamp),
                    y: .value("Speed", item.value),
                    width: .fixed(2)
                )
                .foregroundStyle(Color.purple.opacity(item.value > 0 ? 0.8 : 0.1))
                .clipShape(RoundedRectangle(cornerRadius: 1))
            }
        }
        .chartXScale(domain: xDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v * maxOutput))/s")
                            .font(.caption2)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.secondary.opacity(0.3)),
                    alignment: .center
                )
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            if let date = proxy.value(atX: loc.x, as: Date.self) {
                                hoveredPoint = findNearest(to: date)
                                hoverX = loc.x
                            }
                        case .ended:
                            hoveredPoint = nil
                        }
                    }
                    .overlay {
                        if let pt = hoveredPoint {
                            tooltip(for: pt)
                                .position(x: clampX(hoverX, width: geo.size.width), y: 14)
                        }
                    }
            }
        }
        .frame(height: 120)
    }

    private var xDomain: ClosedRange<Date> {
        let now = Date()
        guard let first = points.first?.timestamp else {
            return now.addingTimeInterval(-3600)...now
        }
        let padding: TimeInterval = 10
        let left = min(first, now.addingTimeInterval(-3600)).addingTimeInterval(-padding)
        return left...now.addingTimeInterval(padding)
    }

    private func tooltip(for pt: ThroughputPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pt.timestamp.formatted(.dateTime.hour().minute().second()))
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: 2) {
                Circle().fill(Color.purple).frame(width: 5, height: 5)
                Text("\(Int(pt.outputTokensPerSecond))/s")
                    .font(.caption2)
                    .foregroundColor(.primary)
            }
        }
        .padding(6)
        .background(.regularMaterial)
        .cornerRadius(6)
    }

    private func clampX(_ x: CGFloat, width: CGFloat) -> CGFloat {
        let tooltipHalf: CGFloat = 85
        return min(max(x, tooltipHalf), width - tooltipHalf)
    }

    private func findNearest(to date: Date) -> ThroughputPoint? {
        points.min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) })
    }
}
