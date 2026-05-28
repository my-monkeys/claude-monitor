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
        claudeProcesses: [], mcpProcesses: [], postcssProcesses: [],
        topApps: []
    )
    @Published var autoKillEnabled = true
    @Published var autoKillThresholdGB: Double = 20
    @Published var autoKillWorkerThreshold: Int = 20
    @Published var lastKillEvent: String?

    private var timer: Timer?

    var menuBarText: String {
        let c = snapshot.claudeCount
        let m = snapshot.mcpCount
        let p = snapshot.postcssCount
        if p > 5 { return "⚠️ \(p) PostCSS" }
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

    func killAllPostCSS() {
        let pids = snapshot.postcssProcesses.map(\.id)
        guard !pids.isEmpty else { return }
        ProcessScanner.killAll(pids: pids)
        lastKillEvent = "Killed \(pids.count) PostCSS workers"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
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
        if snapshot.postcssCount > autoKillWorkerThreshold || snapshot.totalRAM > autoKillThresholdGB {
            let pcPids = snapshot.postcssProcesses.map(\.id)
            if !pcPids.isEmpty {
                ProcessScanner.killAll(pids: pcPids)
                lastKillEvent = "Auto-killed \(pcPids.count) PostCSS @ \(String(format: "%.1f", snapshot.totalRAM))GB"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
            }
        }
    }
}
