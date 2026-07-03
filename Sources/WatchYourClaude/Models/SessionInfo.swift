import Foundation

struct SessionInfo: Identifiable, Equatable {
    let id: String          // sessionId
    let pid: Int
    let cwd: String
    let status: String      // "busy" or "idle"
    let startedAt: Date
    let updatedAt: Date
    let version: String

    var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    var isBusy: Bool { status == "busy" }
    var isActive: Bool { Date().timeIntervalSince(updatedAt) < 30 }

    /// File path to this session's PID file: ~/.claude/sessions/<pid>.json
    var pidFilePath: String {
        ClaudeDataService.claudeSessionsDir.appendingPathComponent("\(pid).json").path
    }
}
