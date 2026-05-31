import Foundation

struct ProcessInfo: Identifiable {
    let id: Int32
    let name: String
    let cpu: Double
    let memMB: Double
    let command: String
}

struct SystemSnapshot {
    let totalRAM: Double
    let swapUsed: Double
    let procCount: Int
    let procLimit: Int
    let diskFreeGB: Double
    let diskTotalGB: Double
    let claudeProcesses: [ProcessInfo]
    let mcpProcesses: [ProcessInfo]
    let topApps: [(name: String, count: Int, memMB: Double)]

    var claudeCount: Int { claudeProcesses.count }
    var mcpCount: Int { mcpProcesses.count }
    var totalMCPMemMB: Double { mcpProcesses.reduce(0) { $0 + $1.memMB } }
    var totalClaudeMemMB: Double { claudeProcesses.reduce(0) { $0 + $1.memMB } }

    /// Process count as a fraction of the per-user limit (0...1).
    var procFraction: Double { procLimit > 0 ? Double(procCount) / Double(procLimit) : 0 }
}

final class ProcessScanner {
    static func scan() -> SystemSnapshot {
        let psOutput = shell("ps aux")
        let lines = psOutput.components(separatedBy: "\n").dropFirst()
        let currentUser = NSUserName()

        var totalRSS: Double = 0
        var procCount = 0
        var claude: [ProcessInfo] = []
        var mcp: [ProcessInfo] = []
        var appMem: [String: (count: Int, mem: Double)] = [:]

        for line in lines {
            let cols = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: true)
            guard cols.count >= 11 else { continue }

            // Per-user process count vs kern.maxprocperuid — the limit a runaway
            // worker swarm hits before the Mac can no longer fork (cf. the PostCSS incident).
            if cols[0] == currentUser { procCount += 1 }

            let pid = Int32(cols[1]) ?? 0
            let cpu = Double(cols[2]) ?? 0
            let rssKB = Double(cols[5]) ?? 0
            let memMB = rssKB / 1024
            let cmd = String(cols[10...].joined(separator: " "))

            totalRSS += memMB

            let proc = ProcessInfo(id: pid, name: classify(cmd), cpu: cpu, memMB: memMB, command: String(cmd.prefix(120)))

            if cmd.contains("claude") && !cmd.contains("zsh") && !cmd.contains("watchdog") && !cmd.contains("ClaudeMonitor") {
                claude.append(proc)
            }

            if cmd.contains("npm exec") || cmd.contains("mcp run") || cmd.contains("mcp-server") || cmd.contains("language-server") {
                mcp.append(proc)
            }

            if memMB > 10 {
                let appName = classify(cmd)
                let existing = appMem[appName] ?? (count: 0, mem: 0)
                appMem[appName] = (count: existing.count + 1, mem: existing.mem + memMB)
            }
        }

        let swapLine = shell("sysctl vm.swapusage")
        let swapUsed = extractSwapMB(from: swapLine)
        let disk = diskUsage()

        let topApps = appMem
            .map { (name: $0.key, count: $0.value.count, memMB: $0.value.mem) }
            .sorted { $0.memMB > $1.memMB }
            .prefix(8)

        return SystemSnapshot(
            totalRAM: totalRSS / 1024,
            swapUsed: swapUsed,
            procCount: procCount,
            procLimit: maxProcPerUID(),
            diskFreeGB: disk.freeGB,
            diskTotalGB: disk.totalGB,
            claudeProcesses: claude,
            mcpProcesses: mcp,
            topApps: Array(topApps)
        )
    }

    static func killProcess(_ pid: Int32) {
        shell("kill \(pid)")
    }

    static func killAll(pids: [Int32]) {
        let pidStr = pids.map(String.init).joined(separator: " ")
        shell("kill -9 \(pidStr)")
    }

    private static func classify(_ cmd: String) -> String {
        if cmd.contains("Dia.app") { return "Dia" }
        if cmd.contains("claude") { return "Claude" }
        if cmd.contains("Beeper") { return "Beeper" }
        if cmd.contains("Chrome") { return "Chrome" }
        if cmd.contains("Warp") { return "Warp" }
        if cmd.contains("next-server") { return "NextServer" }
        if cmd.contains("npm exec firebase") { return "MCP:firebase" }
        if cmd.contains("npm exec") && cmd.contains("playwright") { return "MCP:playwright" }
        if cmd.contains("npm exec") && cmd.contains("clockify") { return "MCP:clockify" }
        if cmd.contains("npm exec") && cmd.contains("simulator") { return "MCP:ios-sim" }
        if cmd.contains("npm exec") { return "MCP:other" }
        if cmd.contains("language-server") { return "DartLSP" }
        if cmd.contains("fontawesome") { return "FontAwesome" }
        if cmd.contains("image-generator") { return "ImageGen" }
        if cmd.contains("Raycast") { return "Raycast" }
        if cmd.contains("WindowServer") { return "WindowServer" }
        if cmd.contains("mds_stores") { return "Spotlight" }
        if cmd.contains("Google Drive") { return "GoogleDrive" }
        if cmd.contains("superwhisper") { return "SuperWhisper" }
        if cmd.contains("Finder") { return "Finder" }

        let parts = cmd.split(separator: "/")
        if let last = parts.last {
            return String(last.prefix(20)).trimmingCharacters(in: .whitespaces)
        }
        return "other"
    }

    private static func extractSwapMB(from line: String) -> Double {
        guard let range = line.range(of: "used = ") else { return 0 }
        let after = line[range.upperBound...]
        let numStr = after.prefix(while: { $0.isNumber || $0 == "." })
        return Double(numStr) ?? 0
    }

    /// Per-user process cap (kern.maxprocperuid). Returns 0 if it can't be read.
    private static func maxProcPerUID() -> Int {
        Int(shell("sysctl -n kern.maxprocperuid").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Free / total space on the volume holding $HOME, in decimal GB (matches Finder).
    /// `volumeAvailableCapacityForImportantUsage` is purgeable-aware, like Finder's "Available".
    private static func diskUsage() -> (freeGB: Double, totalGB: Double) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]) else { return (0, 0) }

        let bytesPerGB = 1_000_000_000.0
        let free = Double(values.volumeAvailableCapacityForImportantUsage ?? 0) / bytesPerGB
        let total = Double(values.volumeTotalCapacity ?? 0) / bytesPerGB
        return (free, total)
    }

    @discardableResult
    private static func shell(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        task.launchPath = "/bin/zsh"
        task.arguments = ["-c", command]
        task.launch()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
