import SwiftUI

struct SessionStatusView: View {
    let sessions: [SessionInfo]
    let overallStatus: SessionMonitor.OverallStatus

    var body: some View {
        VStack(spacing: 0) {
            if sessions.isEmpty {
                noSessionsView
            } else {
                ForEach(sessions) { session in
                    SessionRowView(session: session)
                    if session.id != sessions.last?.id {
                        Divider().padding(.leading, 28)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }

    private var noSessionsView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.gray)
                .frame(width: 8, height: 8)
            Text("No active Claude sessions")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct SessionRowView: View {
    let session: SessionInfo

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.isBusy ? Color.green : Color.blue)
                .frame(width: 8, height: 8)

            Text(session.projectName)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            StatusBadge(isBusy: session.isBusy)
        }
        .padding(.vertical, 4)
    }
}

private struct StatusBadge: View {
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(isBusy ? Color.green : Color.blue)
                .frame(width: 5, height: 5)
            Text(isBusy ? "busy" : "idle")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
