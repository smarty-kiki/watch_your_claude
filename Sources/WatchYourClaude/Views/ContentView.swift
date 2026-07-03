import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var monitor: SessionMonitor

    var body: some View {
        VStack(spacing: 12) {
            // Session status
            SessionStatusView(
                sessions: monitor.activeSessions,
                overallStatus: monitor.overallStatus
            )

            Divider()

            // Throughput chart
            ThroughputChartView(points: monitor.throughputPoints)

            Divider()

            // Consumption chart
            ConsumptionChartView(buckets: monitor.consumptionBuckets)

            Divider()

            // Bottom bar: bell, debug info, quit button
            HStack {
                Button {
                    monitor.notificationsEnabled.toggle()
                } label: {
                    Image(systemName: monitor.notificationsEnabled ? "bell.fill" : "bell.slash")
                        .font(.caption)
                        .foregroundColor(monitor.notificationsEnabled ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(monitor.notificationsEnabled ? "Notifications on" : "Notifications off")

                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .padding(.leading, 4)
                Text("Sessions: \(monitor.activeSessions.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("TP: \(monitor.throughputPoints.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Buckets: \(monitor.consumptionBuckets.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Quit WatchYourClaude")
            }
        }
        .padding(12)
        .frame(width: 400)
    }

    private var statusColor: Color {
        switch monitor.overallStatus {
        case .busy: return .green
        case .idle: return .blue
        case .inactive: return .gray
        }
    }
}
