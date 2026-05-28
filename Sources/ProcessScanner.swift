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
    let claudeProcesses: [ProcessInfo]
    let mcpProcesses: [ProcessInfo]
    let postcssProcesses: [ProcessInfo]
    let topApps: [(name: String, count: Int, memMB: Double)]

    var claudeCount: Int { claudeProcesses.count }
    var mcpCount: Int { mcpProcesses.count }
    var postcssCount: Int { postcssProcesses.count }
    var totalMCPMemMB: Double { mcpProcesses.reduce(0) { $0 + $1.memMB } }
    var totalClaudeMemMB: Double { claudeProcesses.reduce(0) { $0 + $1.memMB } }
}

final class ProcessScanner {
    static func scan() -> SystemSnapshot {
        let psOutput = shell("ps aux")
        let lines = psOutput.components(separatedBy: "\n").dropFirst()

        var totalRSS: Double = 0
        var claude: [ProcessInfo] = []
        var mcp: [ProcessInfo] = []
        var postcss: [ProcessInfo] = []
        var appMem: [String: (count: Int, mem: Double)] = [:]

        for line in lines {
            let cols = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: true)
            guard cols.count >= 11 else { continue }

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

            if cmd.contains("postcss") {
                postcss.append(proc)
            }

            if memMB > 10 {
                let appName = classify(cmd)
                let existing = appMem[appName] ?? (count: 0, mem: 0)
                appMem[appName] = (count: existing.count + 1, mem: existing.mem + memMB)
            }
        }

        let swapLine = shell("sysctl vm.swapusage")
        let swapUsed = extractSwapMB(from: swapLine)

        let topApps = appMem
            .map { (name: $0.key, count: $0.value.count, memMB: $0.value.mem) }
            .sorted { $0.memMB > $1.memMB }
            .prefix(8)

        return SystemSnapshot(
            totalRAM: totalRSS / 1024,
            swapUsed: swapUsed,
            claudeProcesses: claude,
            mcpProcesses: mcp,
            postcssProcesses: postcss,
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
        if cmd.contains("postcss") { return "PostCSS" }
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
