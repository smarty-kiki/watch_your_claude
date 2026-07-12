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

            let throughputResult = service.parseTokenEventsAndUserTimestamps(since: Date().addingTimeInterval(-60 * 60))
            let throughputPoints = ThroughputPoint.maxBySecond(
                service.computeThroughput(
                    events: throughputResult.events,
                    userTimestamps: throughputResult.userTimestamps
                )
            )
            let threeHoursAgo = Date().addingTimeInterval(-3 * 3600)
            let allHistoricalEvents = service.parseTokenEvents(since: threeHoursAgo)
            let consumptionBuckets = service.computeConsumptionBuckets(
                events: allHistoricalEvents,
                bucketMinutes: 10,
                lookbackHours: 3
            )

            await MainActor.run {
                self.throughputPoints = throughputPoints
                self.consumptionBuckets = consumptionBuckets
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
