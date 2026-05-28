import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: MonitorViewModel

    var body: some View {
        VStack(spacing: 0) {
            ramHeader
            statsRow
                .padding(.top, 10)
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

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(
                value: monitor.snapshot.claudeCount,
                label: "Claude",
                mem: monitor.snapshot.totalClaudeMemMB,
                color: .green
            )
            statDivider
            statCell(
                value: monitor.snapshot.mcpCount,
                label: "MCP",
                mem: monitor.snapshot.totalMCPMemMB,
                color: .blue
            )
            statDivider
            statCell(
                value: monitor.snapshot.postcssCount,
                label: "PostCSS",
                mem: monitor.snapshot.postcssProcesses.reduce(0) { $0 + $1.memMB },
                color: monitor.snapshot.postcssCount > 5 ? .red : .secondary
            )
        }
        .padding(.horizontal, 16)
    }

    private func statCell(value: Int, label: String, mem: Double, color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            if mem > 1 {
                Text("\(String(format: "%.0f", mem))M")
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
        if name.contains("PostCSS") { return .red }
        if name.contains("Claude") { return .green }
        if name.contains("MCP") { return .blue }
        if name.contains("Dia") { return .purple }
        return .secondary
    }

    // MARK: - Kill Actions

    private var killActions: some View {
        VStack(spacing: 6) {
            if monitor.snapshot.postcssCount > 0 {
                Button {
                    monitor.killAllPostCSS()
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Kill \(monitor.snapshot.postcssCount) PostCSS")
                        Spacer()
                    }
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(.red.gradient, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }

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
                        Text("Workers")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 55, alignment: .leading)
                        Slider(value: Binding(
                            get: { Double(monitor.autoKillWorkerThreshold) },
                            set: { monitor.autoKillWorkerThreshold = Int($0) }
                        ), in: 5...100, step: 5)
                        .controlSize(.mini)
                        Text("\(monitor.autoKillWorkerThreshold)")
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
