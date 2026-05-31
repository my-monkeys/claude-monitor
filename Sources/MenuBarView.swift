import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: MonitorViewModel

    var body: some View {
        VStack(spacing: 0) {
            ramHeader
            Divider()
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
            diskRow
            Divider()
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
            statsRow
            Divider()
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
            appList
            Divider()
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
            killActions
            Divider()
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
            autoKillSection
            if let event = monitor.lastKillEvent {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                    Text(event)
                        .font(.system(.caption2, design: .monospaced))
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
            Divider()
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
            HStack {
                Text("v1.0")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .padding(.top, 12)
        .frame(width: 300)
    }

    // MARK: - RAM Header

    private var ramHeader: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", monitor.snapshot.totalRAM))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(monitor.ramColor)
                Text("GB")
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { monitor.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(.body, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // RAM bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(monitor.ramColor.gradient)
                        .frame(width: geo.size.width * min(monitor.snapshot.totalRAM / 16, 1.0))
                }
            }
            .frame(height: 6)

            HStack {
                if monitor.snapshot.swapUsed > 10 {
                    Label("\(String(format: "%.0f", monitor.snapshot.swapUsed))MB swap", systemImage: "arrow.triangle.swap")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text("/ 16 GB")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Disk Row

    private var diskRow: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "internaldrive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(String(format: "%.0f", monitor.snapshot.diskFreeGB)) GB")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(monitor.diskColor)
                Text("free")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("/ \(String(format: "%.0f", monitor.snapshot.diskTotalGB)) GB")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            // Disk bar: used / total
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(monitor.diskColor.gradient)
                        .frame(width: geo.size.width * diskUsedFraction)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 16)
    }

    private var diskUsedFraction: CGFloat {
        let total = monitor.snapshot.diskTotalGB
        guard total > 0 else { return 0 }
        let used = max(0, total - monitor.snapshot.diskFreeGB)
        return CGFloat(min(used / total, 1.0))
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(
                value: monitor.snapshot.claudeCount,
                label: "Claude",
                detail: memDetail(monitor.snapshot.totalClaudeMemMB),
                color: .green
            )
            statDivider
            statCell(
                value: monitor.snapshot.mcpCount,
                label: "MCP",
                detail: memDetail(monitor.snapshot.totalMCPMemMB),
                color: .blue
            )
            statDivider
            statCell(
                value: monitor.snapshot.procCount,
                label: "Procs",
                detail: monitor.snapshot.procLimit > 0 ? "/\(monitor.snapshot.procLimit)" : nil,
                color: monitor.procColor
            )
        }
        .padding(.horizontal, 16)
    }

    private func memDetail(_ mem: Double) -> String? {
        mem > 1 ? "\(String(format: "%.0f", mem))M" : nil
    }

    private func statCell(value: Int, label: String, detail: String?, color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            if let detail {
                Text(detail)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 36)
    }

    // MARK: - App List

    private var appList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(monitor.snapshot.topApps.enumerated()), id: \.offset) { i, app in
                HStack(spacing: 8) {
                    Text(app.name)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(app.count)×")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, alignment: .trailing)

                    Text("\(String(format: "%.0f", app.memMB))M")
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .frame(width: 54, alignment: .trailing)

                    // Mini bar
                    let maxMem = monitor.snapshot.topApps.first?.memMB ?? 1
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: app.name).gradient)
                        .frame(width: 40 * (app.memMB / maxMem), height: 8)
                        .frame(width: 40, alignment: .leading)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 16)
                .background(i % 2 == 0 ? Color.clear : Color.primary.opacity(0.02))
            }
        }
    }

    private func barColor(for name: String) -> Color {
        if name.contains("Claude") { return .green }
        if name.contains("MCP") { return .blue }
        if name.contains("Dia") { return .purple }
        return .secondary
    }

    // MARK: - Kill Actions

    private var killActions: some View {
        VStack(spacing: 6) {
            if monitor.snapshot.mcpCount > 10 {
                Button {
                    monitor.killAllMCP()
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("Kill \(monitor.snapshot.mcpCount) MCP servers")
                        Spacer()
                    }
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(.orange.gradient, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Auto-Kill Settings

    private var autoKillSection: some View {
        VStack(spacing: 6) {
            Toggle(isOn: $monitor.autoKillEnabled) {
                Text("Auto-kill")
                    .font(.system(.caption, design: .monospaced, weight: .medium))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .padding(.horizontal, 16)

            if monitor.autoKillEnabled {
                VStack(spacing: 4) {
                    HStack {
                        Text("Procs")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 55, alignment: .leading)
                        Slider(value: $monitor.autoKillProcPercent, in: 50...95, step: 5)
                            .controlSize(.mini)
                        Text("\(String(format: "%.0f", monitor.autoKillProcPercent))%")
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                            .frame(width: 30, alignment: .trailing)
                    }

                    HStack {
                        Text("RAM")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 55, alignment: .leading)
                        Slider(value: $monitor.autoKillThresholdGB, in: 15...40, step: 1)
                            .controlSize(.mini)
                        Text("\(String(format: "%.0f", monitor.autoKillThresholdGB))G")
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                            .frame(width: 30, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
