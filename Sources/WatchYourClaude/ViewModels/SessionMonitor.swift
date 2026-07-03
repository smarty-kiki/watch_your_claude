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

    private let service = ClaudeDataService()
    private var statusTimer: Timer?
    private var tokenTimer: Timer?
    private var lastConsumptionMtimes: [URL: Date] = [:]
    private var previousSessionBusy: [String: Bool] = [:]
    private var audioPlayer: AVAudioPlayer?

    // MARK: - Lifecycle

    init() {
        print("[WatchYourClaude] SessionMonitor init — starting timers")
        refreshSessionStatus()
        refreshTokenData()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSessionStatus()
            }
        }
        tokenTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTokenData()
            }
        }
    }

    deinit {
        statusTimer?.invalidate()
        tokenTimer?.invalidate()
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
            // Clean up entries for sessions that no longer exist
            for id in previousSessionBusy.keys {
                if !sessions.contains(where: { $0.id == id }) {
                    previousSessionBusy.removeValue(forKey: id)
                }
            }
        }
    }

    private func refreshTokenData() {
        Task(priority: .utility) {
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
                print("[WatchYourClaude] Throughput: \(throughputResult.events.count) events → \(throughputPoints.count) points")
                print("[WatchYourClaude] Consumption: \(allHistoricalEvents.count) events → \(consumptionBuckets.count) buckets")
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
