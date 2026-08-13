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
        // -o command gives full args (needed to classify + spot Claude roots); ppid drives
        // MCP detection by parentage. Order matters: command is last (it contains spaces).
        let psOutput = shell("ps -axo pid,ppid,%cpu,rss,user,command")
        let lines = psOutput.components(separatedBy: "\n").dropFirst()
        let currentUser = NSUserName()

        // First pass: parse every row and collect the Claude session roots, since a child
        // can be listed before its parent.
        var rows: [(pid: Int32, ppid: Int32, cpu: Double, memMB: Double, user: String, cmd: String)] = []
        var claudeRoots = Set<Int32>()

        for line in lines {
            let cols = line.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
            guard cols.count >= 6 else { continue }
            let pid = Int32(cols[0]) ?? 0
            // After maxSplits, the remainder keeps ps's column padding (the `user` field is
            // space-padded), so trim — otherwise cmd is " …claude …" and hasPrefix fails.
            let cmd = cols[5...].joined(separator: " ").trimmingCharacters(in: .whitespaces)
            rows.append((
                pid: pid,
                ppid: Int32(cols[1]) ?? 0,
                cpu: Double(cols[2]) ?? 0,
                memMB: (Double(cols[3]) ?? 0) / 1024,
                user: String(cols[4]),
                cmd: cmd
            ))
            if isClaudeRoot(cmd) { claudeRoots.insert(pid) }
        }

        var totalRSS: Double = 0
        var procCount = 0
        var claude: [ProcessInfo] = []
        var mcp: [ProcessInfo] = []
        var appMem: [String: (count: Int, mem: Double)] = [:]

        for r in rows {
            // Per-user process count vs kern.maxprocperuid — the ceiling a runaway worker
            // swarm pins before the Mac can no longer fork (cf. the PostCSS incident).
            if r.user == currentUser { procCount += 1 }
            totalRSS += r.memMB

            let proc = ProcessInfo(id: r.pid, name: classify(r.cmd), cpu: r.cpu, memMB: r.memMB, command: String(r.cmd.prefix(120)))

            if r.cmd.contains("claude") && !r.cmd.contains("zsh") && !r.cmd.contains("watchdog") && !r.cmd.contains("ClaudeMonitor") {
                claude.append(proc)
            }

            // MCP servers are the persistent processes a Claude session spawns directly.
            // Detecting by parentage (not by name) catches custom-named servers like
            // vocast-manager and dedupes launcher+child pairs to one row per server.
            // The session's non-MCP children (caffeinate, Bash-tool shells, LSPs) are excluded.
            if claudeRoots.contains(r.ppid) && !isAuxiliaryChild(r.cmd) {
                mcp.append(proc)
            }

            if r.memMB > 10 {
                let appName = classify(r.cmd)
                let existing = appMem[appName] ?? (count: 0, mem: 0)
                appMem[appName] = (count: existing.count + 1, mem: existing.mem + r.memMB)
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

    /// A Claude Code session root — the `claude` CLI itself, not the desktop app or this monitor.
    private static func isClaudeRoot(_ cmd: String) -> Bool {
        (cmd == "claude" || cmd.hasPrefix("claude ")) && !cmd.contains("Claude.app") && !cmd.contains("ClaudeMonitor")
    }

    /// Children a Claude session spawns that are NOT MCP servers: the keep-awake helper,
    /// Bash-tool shells, and editor/LSP toolchains.
    private static func isAuxiliaryChild(_ cmd: String) -> Bool {
        let exe = cmd.split(separator: " ").first.map(String.init) ?? cmd
        let base = exe.split(separator: "/").last.map(String.init) ?? exe
        if base == "caffeinate" || base == "zsh" || base == "bash" || base == "sh" { return true }
        if cmd.contains(" -c ") { return true }               // Bash tool runs `/bin/zsh -c …`
        let lc = cmd.lowercased()
        if lc.contains("xcode.app") || lc.contains("sourcekit") { return true }
        return false
    }

    private static func classify(_ cmd: String) -> String {
        if cmd.contains("Dia.app") { return "Dia" }
        if cmd.contains("claude") { return "Claude" }
        if cmd.contains("Beeper") { return "Beeper" }
        if cmd.contains("Chrome") { return "Chrome" }
        if cmd.contains("Warp") { return "Warp" }
        if cmd.contains("next-server") { return "NextServer" }
        if cmd.contains("google-play-mcp") { return "MCP:google-play" }
        if cmd.contains("appstore-connect-mcp") { return "MCP:appstore" }
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
