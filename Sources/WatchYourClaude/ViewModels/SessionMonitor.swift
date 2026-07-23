import Foundation
import Combine
import AVFoundation
import AppKit

@MainActor
final class SessionMonitor: ObservableObject {

    // MARK: - Published state

    @Published var activeSessions: [SessionInfo] = []
    @Published var throughputPoints: [ThroughputPoint] = []
    @Published var consumptionBuckets: [ConsumptionBucket] = []
    @Published var overallStatus: OverallStatus = .inactive

    @Published var notificationsEnabled = false

    enum OverallStatus {
        case busy       // at least one session is actively executing
        case idle       // sessions are up but waiting for input
        case inactive   // no active sessions
    }

    // MARK: - Private

    nonisolated private let service = ClaudeDataService()
    private var sessionsDirSource: DispatchSourceFileSystemObject?
    private var projectsDirSource: DispatchSourceFileSystemObject?
    private var jsonlFileSources: [URL: DispatchSourceFileSystemObject] = [:]
    private var lastConsumptionMtimes: [URL: Date] = [:]
    private var previousSessionBusy: [String: Bool] = [:]
    private var audioPlayer: AVAudioPlayer?
    private var fallbackTimer: Timer?
    private var refreshDebounceTask: Task<Void, Never>?
    private var cachedConsumptionBuckets: [ConsumptionBucket] = []
    private var lastConsumptionParseTime: Date?
    private var cachedThroughputPoints: [ThroughputPoint] = []
    private var cachedUserTimestamps: [String: Date] = [:]
    private var lastThroughputParseTime: Date?

    // MARK: - Lifecycle

    init() {
        setupDirectoryWatchers()
        scanAndWatchNewJsonlFiles()
        refreshSessionStatus()
        refreshTokenData()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSessionStatus()
                self?.refreshTokenData()
            }
        }
    }

    deinit {
        sessionsDirSource?.cancel()
        projectsDirSource?.cancel()
        for (_, source) in jsonlFileSources {
            source.cancel()
        }
        jsonlFileSources.removeAll()
        fallbackTimer?.invalidate()
        refreshDebounceTask?.cancel()
    }

    // MARK: - Directory Watchers

    private func setupDirectoryWatchers() {
        setupSessionsDirWatcher()
        setupProjectsDirWatcher()
    }

    private func setupSessionsDirWatcher() {
        let dirURL = ClaudeDataService.claudeSessionsDir
        guard FileManager.default.fileExists(atPath: dirURL.path) else { return }

        let fd = open(dirURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .extend],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            self?.debouncedRefresh()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        self.sessionsDirSource = source
    }

    private func setupProjectsDirWatcher() {
        let dirURL = ClaudeDataService.claudeProjectsDir
        guard FileManager.default.fileExists(atPath: dirURL.path) else { return }

        let fd = open(dirURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .extend],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            self?.debouncedRefresh()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        self.projectsDirSource = source
    }

    private func scanAndWatchNewJsonlFiles() {
        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: ClaudeDataService.claudeProjectsDir,
            includingPropertiesForKeys: nil
        ) else { return }

        for projDir in projectDirs where projDir.hasDirectoryPath {
            guard let sessionFiles = try? FileManager.default.contentsOfDirectory(
                at: projDir,
                includingPropertiesForKeys: nil
            ) else { continue }

            for file in sessionFiles where file.pathExtension == "jsonl" {
                if jsonlFileSources[file] == nil {
                    watchJsonlFile(file)
                }
            }
        }
    }

    private func watchJsonlFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .extend],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            if !FileManager.default.fileExists(atPath: url.path) {
                self?.jsonlFileSources.removeValue(forKey: url)
                return
            }
            self?.debouncedRefresh()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        jsonlFileSources[url] = source
    }

    // MARK: - Debounced Refresh

    private func debouncedRefresh() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.scanAndWatchNewJsonlFiles()
                self.refreshSessionStatus()
            }
            self.refreshTokenData()
        }
    }

    // MARK: - Refresh

    private func refreshSessionStatus() {
        let sessions = service.scanActiveSessions()
        activeSessions = sessions

        let newStatus: OverallStatus
        if sessions.isEmpty {
            newStatus = .inactive
        } else if sessions.contains(where: { $0.isBusy }) {
            newStatus = .busy
        } else {
            newStatus = .idle
        }
        overallStatus = newStatus

        if notificationsEnabled {
            for session in sessions {
                let wasBusy = previousSessionBusy[session.id] ?? false
                if wasBusy && !session.isBusy {
                    playNotificationSound()
                }
                previousSessionBusy[session.id] = session.isBusy
            }
            for id in previousSessionBusy.keys {
                if !sessions.contains(where: { $0.id == id }) {
                    previousSessionBusy.removeValue(forKey: id)
                }
            }
        }
    }

    private func refreshTokenData() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            let service = self.service

            let oneHourAgo = Date().addingTimeInterval(-3600)
            let throughputResult = service.parseTokenEventsAndUserTimestamps(since: oneHourAgo)
            let threeHoursAgo = Date().addingTimeInterval(-3 * 3600)

            await MainActor.run {
                let throughputPoints: [ThroughputPoint]
                if self.cachedThroughputPoints.isEmpty {
                    self.cachedUserTimestamps = throughputResult.userTimestamps
                    let points = ThroughputPoint.maxBySecond(
                        service.computeThroughput(events: throughputResult.events, userTimestamps: throughputResult.userTimestamps)
                    )
                    self.cachedThroughputPoints = points
                    self.lastThroughputParseTime = Date()
                    throughputPoints = points
                } else {
                    let since: Date
                    if let last = self.lastThroughputParseTime {
                        since = Date(timeIntervalSince1970: last.timeIntervalSince1970.rounded(.down))
                    } else {
                        since = oneHourAgo
                    }
                    let newResult = service.parseTokenEventsAndUserTimestamps(since: since)
                    self.cachedUserTimestamps.merge(newResult.userTimestamps, uniquingKeysWith: { $1 })

                    let incrementalPoints = ThroughputPoint.maxBySecond(
                        service.computeThroughput(events: newResult.events, userTimestamps: self.cachedUserTimestamps)
                    )

                    var combined = self.cachedThroughputPoints
                    let existingSeconds = Set(combined.map { $0.timestamp.timeIntervalSince1970.rounded(.down) })
                    for point in incrementalPoints {
                        let key = point.timestamp.timeIntervalSince1970.rounded(.down)
                        if !existingSeconds.contains(key) {
                            combined.append(point)
                        }
                    }
                    combined.sort { $0.timestamp < $1.timestamp }

                    let cutoff = Date().addingTimeInterval(-3600)
                    combined = combined.filter { $0.timestamp >= cutoff }

                    self.cachedThroughputPoints = combined
                    self.lastThroughputParseTime = Date()
                    throughputPoints = combined
                }

                let consumptionEvents = service.parseTokenEvents(since: threeHoursAgo)

                let newBuckets: [ConsumptionBucket]
                if self.cachedConsumptionBuckets.isEmpty {
                    let allBuckets = service.computeConsumptionBuckets(
                        events: consumptionEvents,
                        bucketMinutes: 10,
                        lookbackHours: 3
                    )
                    self.cachedConsumptionBuckets = allBuckets
                    self.lastConsumptionParseTime = consumptionEvents.last?.timestamp
                    newBuckets = allBuckets
                } else {
                    let bucketCount = self.cachedConsumptionBuckets.count
                    let bucketSeconds = TimeInterval(10 * 60)
                    let expectedStart = ClaudeDataService.alignedBucketAnchor()
                        .addingTimeInterval(-TimeInterval(bucketCount) * bucketSeconds)
                    let drift = abs(expectedStart.timeIntervalSince(self.cachedConsumptionBuckets.first?.startTime ?? expectedStart))

                    if drift > bucketSeconds {
                        let allBuckets = service.computeConsumptionBuckets(
                            events: consumptionEvents,
                            bucketMinutes: 10,
                            lookbackHours: 3
                        )
                        self.cachedConsumptionBuckets = allBuckets
                        self.lastConsumptionParseTime = consumptionEvents.last?.timestamp
                        newBuckets = allBuckets
                    } else {
                        let since: Date
                        if let last = self.lastConsumptionParseTime {
                            since = Date(timeIntervalSince1970: last.timeIntervalSince1970.rounded(.down))
                        } else {
                            since = threeHoursAgo
                        }
                        let newEvents = service.parseTokenEvents(since: since)
                        let currentBucket = service.computeCurrentConsumptionBucket(
                            events: newEvents,
                            bucketMinutes: 10
                        )
                        self.cachedConsumptionBuckets[self.cachedConsumptionBuckets.count - 1] = currentBucket
                        self.lastConsumptionParseTime = newEvents.last?.timestamp
                        newBuckets = self.cachedConsumptionBuckets
                    }
                }

                self.throughputPoints = throughputPoints
                self.consumptionBuckets = newBuckets
            }
        }
    }

    private func playNotificationSound() {
        guard let url = Bundle.module.url(forResource: "notification", withExtension: "wav") else {
            NSSound.beep()
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = 1.0
            audioPlayer?.play()
        } catch {
            NSSound.beep()
        }
    }
}
