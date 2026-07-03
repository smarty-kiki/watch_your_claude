import SwiftUI
import AppKit

@main
struct WatchYourClaudeApp: App {
    @StateObject private var monitor = SessionMonitor()

    init() {
        setAppIcon()
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(monitor: monitor)
        } label: {
            makeMenuBarIcon(statusColor: statusNSColor)
        }
        .menuBarExtraStyle(.window)
    }

    private func setAppIcon() {
        guard let url = Bundle.module.url(forResource: "icon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return }
        NSApplication.shared.applicationIconImage = image
    }

    private var statusNSColor: NSColor {
        switch monitor.overallStatus {
        case .busy:     return .systemGreen
        case .idle:     return .systemBlue
        case .inactive: return .systemGray
        }
    }

    private func makeMenuBarIcon(statusColor: NSColor) -> some View {
        let image = drawMenuBarImage(statusColor: statusColor)
        return Image(nsImage: image)
    }

    private func drawMenuBarImage(statusColor: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        // Dark background circle
        let bgPath = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 16, height: 16))
        NSColor(red: 0.08, green: 0.13, blue: 0.24, alpha: 1).setFill()
        bgPath.fill()

        // Colored "C" arc
        statusColor.setStroke()
        let cPath = NSBezierPath()
        cPath.appendArc(
            withCenter: NSPoint(x: 9, y: 9),
            radius: 6,
            startAngle: 200,
            endAngle: 340,
            clockwise: false
        )
        cPath.lineWidth = 1.8
        cPath.lineCapStyle = .round
        cPath.stroke()

        // Signal wave in center
        statusColor.withAlphaComponent(0.9).setStroke()
        let wave = NSBezierPath()
        wave.move(to: NSPoint(x: 5, y: 9))
        wave.line(to: NSPoint(x: 7, y: 9))
        wave.line(to: NSPoint(x: 8, y: 6))
        wave.line(to: NSPoint(x: 9, y: 12))
        wave.line(to: NSPoint(x: 10, y: 7))
        wave.line(to: NSPoint(x: 11, y: 9))
        wave.line(to: NSPoint(x: 13, y: 9))
        wave.lineWidth = 1.2
        wave.lineCapStyle = .round
        wave.lineJoinStyle = .round
        wave.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
