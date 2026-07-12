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
        let series: Series

        enum Series: String { case upload, download }
    }

    private var chartData: [ChartData] {
        let maxInput = points.map(\.inputTokensPerSecond).max() ?? 100
        let maxOutput = points.map(\.outputTokensPerSecond).max() ?? 100

        return points.flatMap { p in
            let uploadNorm = maxInput > 0 ? p.inputTokensPerSecond / maxInput : 0
            let downloadNorm = maxOutput > 0 ? p.outputTokensPerSecond / maxOutput : 0
            return [
                ChartData(timestamp: p.timestamp, value: uploadNorm, series: .upload),
                ChartData(timestamp: p.timestamp, value: -downloadNorm, series: .download)
            ]
        }
    }

    private var maxInput: Double { points.map(\.inputTokensPerSecond).max() ?? 100 }
    private var maxOutput: Double { points.map(\.outputTokensPerSecond).max() ?? 100 }

    private var yDomain: ClosedRange<Double> {
        return -1.2...1.2
    }

    private var yAxisLabels: [Double] {
        let inputSteps = [0.25, 0.5, 0.75, 1.0]
        let outputSteps = [-0.25, -0.5, -0.75, -1.0]
        return inputSteps.map { $0 } + outputSteps.map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Token Throughput (1h)")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                if !points.isEmpty {
                    Text("↑ \(Int(maxInput))/s  ↓ \(Int(maxOutput))/s")
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

            legendView
        }
    }

    private var emptyChart: some View {
        ZStack {
            Rectangle()
                .fill(Color.primary.opacity(0.03))
                .frame(height: 120)
            Text("Waiting for API activity...")
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
                    width: .fixed(1)
                )
                .foregroundStyle(
                    item.series == .upload
                        ? Color.blue.opacity(abs(item.value) > 0 ? 0.85 : 0.1)
                        : Color.purple.opacity(abs(item.value) > 0 ? 0.85 : 0.1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
            }
        }
        .chartXScale(domain: xDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                if let date = value.as(Date.self), date.timeIntervalSinceNow > -15 {
                    AxisValueLabel("now")
                } else {
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        let real = abs(v) * (v >= 0 ? maxInput : maxOutput)
                        Text("\(Int(real))/s")
                            .font(.caption2)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartYScale(domain: yDomain)
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
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    Circle().fill(Color.blue).frame(width: 5, height: 5)
                    Text("↑ \(Int(pt.inputTokensPerSecond))/s")
                        .font(.caption2)
                        .foregroundColor(.primary)
                }
                HStack(spacing: 2) {
                    Circle().fill(Color.purple).frame(width: 5, height: 5)
                    Text("↓ \(Int(pt.outputTokensPerSecond))/s")
                        .font(.caption2)
                        .foregroundColor(.primary)
                }
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

    private var legendView: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Circle().fill(Color.blue).frame(width: 6, height: 6)
                Text("Upload (input t/s)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                Circle().fill(Color.purple).frame(width: 6, height: 6)
                Text("Download (output t/s)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}
