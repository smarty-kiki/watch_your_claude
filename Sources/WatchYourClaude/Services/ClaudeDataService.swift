import Foundation

/// Reads Claude Code session data from ~/.claude/ on disk.
final class ClaudeDataService {

    // MARK: - Paths

    static func resolveClaudeDir() -> URL {
        // NSHomeDirectory() is more reliable than homeDirectoryForCurrentUser in GUI apps
        let home = NSHomeDirectory()
        if !home.isEmpty {
            let url = URL(fileURLWithPath: home).appendingPathComponent(".claude")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        // Fallback
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
    }

    static var claudeDir: URL { resolveClaudeDir() }
    static var claudeSessionsDir: URL { claudeDir.appendingPathComponent("sessions") }
    static var claudeProjectsDir: URL { claudeDir.appendingPathComponent("projects") }

    // MARK: - Session scanning

    /// Returns all sessions whose `updatedAt` is within the last `staleness` seconds.
    /// Scans both session JSON files (preferred, more info) and JSONL files (fallback).
    func scanActiveSessions(staleness seconds: TimeInterval = 180) -> [SessionInfo] {
        let now = Date()
        var sessions: [SessionInfo] = []
        var seenIds = Set<String>()

        // 1) Scan session JSON files (preferred: has pid, status, version, etc.)
        if let files = try? FileManager.default.contentsOfDirectory(
            at: Self.claudeSessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) {
            for file in files where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file),
                      let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let pid = raw["pid"] as? Int,
                      let sessionId = raw["sessionId"] as? String,
                      let cwd = raw["cwd"] as? String,
                      let status = raw["status"] as? String,
                      let startedAtMs = raw["startedAt"] as? Double,
                      let updatedAtMs = raw["updatedAt"] as? Double
                else {
                    print("[WatchYourClaude] Failed to parse session file: \(file.lastPathComponent)")
                    continue
                }

                let updatedAt = Date(timeIntervalSince1970: updatedAtMs / 1000)
                guard now.timeIntervalSince(updatedAt) < seconds else { continue }

                sessions.append(SessionInfo(
                    id: sessionId,
                    pid: pid,
                    cwd: cwd,
                    status: status,
                    startedAt: Date(timeIntervalSince1970: startedAtMs / 1000),
                    updatedAt: updatedAt,
                    version: raw["version"] as? String ?? ""
                ))
                seenIds.insert(sessionId)
            }
        } else {
            print("[WatchYourClaude] Cannot read sessions dir: \(Self.claudeSessionsDir.path)")
        }

        // 2) Scan JSONL files as fallback (some Claude Code versions don't write session JSON)
        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: Self.claudeProjectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return sessions.sorted { $0.updatedAt > $1.updatedAt } }

        for projDir in projectDirs {
            guard projDir.hasDirectoryPath else { continue }
            guard let sessionFiles = try? FileManager.default.contentsOfDirectory(
                at: projDir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for file in sessionFiles where file.pathExtension == "jsonl" {
                guard let mtime = fileModificationDate(file),
                      now.timeIntervalSince(mtime) < seconds else { continue }

                let sessionId = file.deletingPathExtension().lastPathComponent
                guard !seenIds.contains(sessionId) else { continue }

                let cwd = extractCwd(from: file) ?? projDir.lastPathComponent
                let isBusy = isSessionBusy(jsonl: file)
                sessions.append(SessionInfo(
                    id: sessionId,
                    pid: 0,
                    cwd: cwd,
                    status: isBusy ? "busy" : "idle",
                    startedAt: mtime.addingTimeInterval(-3600),
                    updatedAt: mtime,
                    version: ""
                ))
                seenIds.insert(sessionId)
            }
        }

        print("[WatchYourClaude] Found \(sessions.count) active session(s)")
        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Token event parsing

    /// Parses all token events from session JSONL files modified after `since`.
    func parseTokenEvents(since: Date) -> [TokenEvent] {
        let (events, _) = parseTokenEventsAndUserTimestamps(since: since)
        return events
    }

    /// Returns both assistant token events and a map of user event UUID → timestamp,
    /// so throughput can be computed using request latency (user msg → first assistant response).
    func parseTokenEventsAndUserTimestamps(since: Date) -> (events: [TokenEvent], userTimestamps: [String: Date]) {
        var allEvents: [TokenEvent] = []
        var userTimestamps: [String: Date] = [:]

        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: Self.claudeProjectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return ([], [:]) }

        for projDir in projectDirs {
            guard projDir.hasDirectoryPath else { continue }
            guard let sessionFiles = try? FileManager.default.contentsOfDirectory(
                at: projDir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for file in sessionFiles where file.pathExtension == "jsonl" {
                guard let mtime = fileModificationDate(file),
                      mtime >= since else { continue }

                let sessionId = file.deletingPathExtension().lastPathComponent
                let projectName: String
                if let cwd = extractCwd(from: file) {
                    projectName = URL(fileURLWithPath: cwd).lastPathComponent
                } else {
                    projectName = projDir.lastPathComponent
                }

                let result = parseSessionJSONLWithUsers(
                    at: file,
                    since: since,
                    projectName: projectName,
                    sessionId: sessionId
                )
                allEvents.append(contentsOf: result.events)
                userTimestamps.merge(result.userTimestamps, uniquingKeysWith: { $1 })
            }
        }

        return (allEvents.sorted { $0.timestamp < $1.timestamp }, userTimestamps)
    }

    /// Parses the tail of a session JSONL file for recent throughput data.
    func parseRecentTokenEvents(sessionId: String, cwd: String, limit: Int = 200) -> [TokenEvent] {
        let projectDir = encodeProjectName(cwd)
        let fileURL = Self.claudeProjectsDir
            .appendingPathComponent(projectDir)
            .appendingPathComponent("\(sessionId).jsonl")

        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        if !exists {
            print("[WatchYourClaude] JSONL not found: \(fileURL.path)")
            print("[WatchYourClaude]   encoded dir: \(projectDir)")
        }

        return parseSessionJSONL(
            at: fileURL,
            since: Date.distantPast,
            projectName: URL(fileURLWithPath: cwd).lastPathComponent,
            sessionId: sessionId,
            tailLines: limit
        )
    }

    // MARK: - Throughput computation

    /// Computes throughput using the time between a user message and its first assistant response
    /// as the request latency, rather than the gap between consecutive API calls.
    func computeThroughput(events: [TokenEvent], userTimestamps: [String: Date] = [:]) -> [ThroughputPoint] {
        var points: [ThroughputPoint] = []

        for event in events {
            guard let userTime = userTimestamps[event.parentUuid ?? ""] else { continue }
            let latency = event.timestamp.timeIntervalSince(userTime)
            guard latency > 0.05 else { continue }

            points.append(ThroughputPoint(
                timestamp: event.timestamp,
                inputTokensPerSecond: Double(event.totalInputTokens) / latency,
                outputTokensPerSecond: Double(event.outputTokens) / latency,
                model: event.model
            ))
        }

        return points.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Consumption buckets

    /// Groups token events into fixed-duration buckets.
    func computeConsumptionBuckets(
        events: [TokenEvent],
        bucketMinutes: Int = 10,
        lookbackHours: Int = 3
    ) -> [ConsumptionBucket] {
        let now = Date()
        let bucketSeconds = TimeInterval(bucketMinutes * 60)
        let lookbackSeconds = TimeInterval(lookbackHours * 3600)
        let startTime = now.addingTimeInterval(-lookbackSeconds)

        let bucketCount = Int(ceil(lookbackSeconds / bucketSeconds))
        var buckets: [ConsumptionBucket] = (0..<bucketCount).map { i in
            let bucketStart = startTime.addingTimeInterval(TimeInterval(i) * bucketSeconds)
            return ConsumptionBucket(
                startTime: bucketStart,
                endTime: bucketStart.addingTimeInterval(bucketSeconds)
            )
        }

        for event in events {
            let offset = event.timestamp.timeIntervalSince(startTime)
            guard offset >= 0 else { continue }
            let idx = Int(offset / bucketSeconds)
            guard idx < buckets.count else { continue }

            let projectKey = event.projectName
            let modelKey = event.model
            let inputTotal = event.totalInputTokens

            var proj = buckets[idx].projectTokens[projectKey] ?? (0, 0)
            proj.input += inputTotal
            proj.output += event.outputTokens
            buckets[idx].projectTokens[projectKey] = proj

            var mdl = buckets[idx].modelTokens[modelKey] ?? (0, 0)
            mdl.input += inputTotal
            mdl.output += event.outputTokens
            buckets[idx].modelTokens[modelKey] = mdl
        }

        return buckets
    }

    // MARK: - Private helpers

    private func parseSessionJSONL(
        at url: URL,
        since: Date,
        projectName: String,
        sessionId: String,
        tailLines: Int? = nil
    ) -> [TokenEvent] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        if let tail = tailLines, lines.count > tail {
            lines = Array(lines.suffix(tail))
        }

        var events: [TokenEvent] = []
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = raw["type"] as? String,
                  let timestampStr = raw["timestamp"] as? String,
                  let timestamp = iso8601Parse(timestampStr)
            else { continue }

            if type == "assistant",
               timestamp >= since,
               let msg = raw["message"] as? [String: Any],
               let usage = msg["usage"] as? [String: Any] {
                events.append(TokenEvent(
                    timestamp: timestamp,
                    inputTokens: usage["input_tokens"] as? Int ?? 0,
                    outputTokens: usage["output_tokens"] as? Int ?? 0,
                    cacheReadInputTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
                    cacheCreationInputTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
                    model: msg["model"] as? String ?? "",
                    projectName: projectName,
                    sessionId: sessionId,
                    parentUuid: raw["parentUuid"] as? String
                ))
            }
        }
        return events
    }

    private struct SessionParseResult {
        let events: [TokenEvent]
        let userTimestamps: [String: Date]
    }

    /// Parses a JSONL file returning both assistant events and user event timestamps.
    private func parseSessionJSONLWithUsers(
        at url: URL,
        since: Date,
        projectName: String,
        sessionId: String,
        tailLines: Int? = nil
    ) -> SessionParseResult {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return SessionParseResult(events: [], userTimestamps: [:])
        }
        var lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        if let tail = tailLines, lines.count > tail {
            lines = Array(lines.suffix(tail))
        }

        var events: [TokenEvent] = []
        var userTimestamps: [String: Date] = [:]

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = raw["type"] as? String,
                  let timestampStr = raw["timestamp"] as? String,
                  let timestamp = iso8601Parse(timestampStr)
            else { continue }

            switch type {
            case "user":
                if let uuid = raw["uuid"] as? String {
                    userTimestamps[uuid] = timestamp
                }

            case "assistant" where timestamp >= since:
                guard let msg = raw["message"] as? [String: Any],
                      let usage = msg["usage"] as? [String: Any] else { continue }
                events.append(TokenEvent(
                    timestamp: timestamp,
                    inputTokens: usage["input_tokens"] as? Int ?? 0,
                    outputTokens: usage["output_tokens"] as? Int ?? 0,
                    cacheReadInputTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
                    cacheCreationInputTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
                    model: msg["model"] as? String ?? "",
                    projectName: projectName,
                    sessionId: sessionId,
                    parentUuid: raw["parentUuid"] as? String
                ))

            default:
                break
            }
        }

        return SessionParseResult(events: events, userTimestamps: userTimestamps)
    }

    /// Reads the first user event from a JSONL file to extract `cwd`.
    private func extractCwd(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        // Read first 128 KB — enough to find the first user event
        guard let chunk = try? handle.read(upToCount: 128 * 1024),
              let text = String(data: chunk, encoding: .utf8) else { return nil }

        let lines = text.components(separatedBy: .newlines)
        for line in lines.prefix(20) {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = raw["type"] as? String,
                  type == "user",
                  let cwd = raw["cwd"] as? String
            else { continue }
            return cwd
        }
        return nil
    }

    private func fileModificationDate(_ url: URL) -> Date? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let date = values.contentModificationDate else { return nil }
        return date
    }

    /// Determines if a JSONL session is actively busy by checking file modification time.
    /// Claude continuously writes to the JSONL while busy, and stops when idle.
    private func isSessionBusy(jsonl: URL) -> Bool {
        guard let mtime = fileModificationDate(jsonl) else { return false }
        return Date().timeIntervalSince(mtime) < 15
    }

    /// Claude encodes project paths by replacing `/`, `.`, `_` with `-`.
    /// e.g. /Users/yaoyang/Developments.localized/company/smarty/watch_your_claude
    ///   → -Users-yaoyang-Developments-localized-company-smarty-watch-your-claude
    private func encodeProjectName(_ cwd: String) -> String {
        var result = cwd.replacingOccurrences(of: "/", with: "-")
        result = result.replacingOccurrences(of: ".", with: "-")
        result = result.replacingOccurrences(of: "_", with: "-")
        return result
    }

    private func iso8601Parse(_ str: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: str) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: str)
    }
}
