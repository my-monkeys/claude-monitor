import SwiftUI

@main
struct ClaudeMonitorApp: App {
    @StateObject private var monitor = MonitorViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: monitor)
        } label: {
            Text(monitor.menuBarText)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class MonitorViewModel: ObservableObject {
    @Published var snapshot = SystemSnapshot(
        totalRAM: 0, swapUsed: 0,
        procCount: 0, procLimit: 0,
        diskFreeGB: 0, diskTotalGB: 0,
        claudeProcesses: [], mcpProcesses: [],
        topApps: []
    )
    @Published var autoKillEnabled = true
    @Published var autoKillThresholdGB: Double = 20
    /// Auto-kill trigger as a percentage of the per-user process limit.
    @Published var autoKillProcPercent: Double = 80
    @Published var lastKillEvent: String?

    /// Process count fraction above which we surface a menu-bar warning.
    private let procWarnFraction = 0.85

    private var timer: Timer?

    var menuBarText: String {
        let c = snapshot.claudeCount
        let m = snapshot.mcpCount
        if snapshot.procFraction > procWarnFraction { return "⚠️ \(snapshot.procCount) procs" }
        return "🤖\(c) 🔌\(m)"
    }

    private func loadMenuBarIcon(_ name: String) -> NSImage? {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/ClaudeMonitor_ClaudeMonitor.bundle/Icons/\(name).png"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/ClaudeMonitor_ClaudeMonitor.bundle/Icons/\(name).png"),
        ]
        if let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Icons") {
            return makeTemplate(url)
        }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return makeTemplate(url)
        }
        return nil
    }

    private func makeTemplate(_ url: URL) -> NSImage? {
        guard let img = NSImage(contentsOf: url) else { return nil }
        img.size = NSSize(width: 16, height: 16)
        img.isTemplate = true
        return img
    }

    var ramColor: Color {
        if snapshot.totalRAM > 20 { return .red }
        if snapshot.totalRAM > 16 { return .orange }
        return .green
    }

    var procColor: Color {
        let f = snapshot.procFraction
        if f > 0.85 { return .red }
        if f > 0.6 { return .orange }
        return .green
    }

    var diskColor: Color {
        if snapshot.diskFreeGB < 10 { return .red }
        if snapshot.diskFreeGB < 30 { return .orange }
        return .green
    }

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        snapshot = ProcessScanner.scan()
        checkAutoKill()
    }

    func killProcess(_ pid: Int32) {
        ProcessScanner.killProcess(pid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh() }
    }

    func killAllMCP() {
        let pids = snapshot.mcpProcesses.map(\.id)
        guard !pids.isEmpty else { return }
        ProcessScanner.killAll(pids: pids)
        lastKillEvent = "Killed \(pids.count) MCP servers"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
    }

    private func checkAutoKill() {
        guard autoKillEnabled else { return }
        let procTrigger = snapshot.procLimit > 0
            && snapshot.procCount > Int(autoKillProcPercent / 100 * Double(snapshot.procLimit))
        guard procTrigger || snapshot.totalRAM > autoKillThresholdGB else { return }

        // The disposable worker swarm we can safely reap: npm/MCP servers.
        let pids = snapshot.mcpProcesses.map(\.id)
        guard !pids.isEmpty else { return }
        ProcessScanner.killAll(pids: pids)
        lastKillEvent = "Auto-killed \(pids.count) MCP @ \(snapshot.procCount) procs"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
    }
}
