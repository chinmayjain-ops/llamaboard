import SwiftUI
import LlamaboardKit

/// Server & Telemetry — a running-status header with uptime/requests, a bento row of
/// telemetry (tokens/sec, memory, endpoint), and a Bench/Logs split pane below.
/// All live values come from ServerManager.
struct ServerView: View {
    @EnvironmentObject var app: AppState
    @State private var tab = 0
    @State private var copiedEndpoint = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            statusHeader
            telemetryRow
            tabs
            splitPane
        }
        .padding(.top, 88)
        .padding(.bottom, 8)
    }

    // MARK: Status header

    private var statusHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(statusLabel).font(.monoLabel).tracking(1).foregroundStyle(statusColor)
                }
                HStack(spacing: 8) {
                    Text(statusTitle).font(.headlineLg).foregroundStyle(Theme.onSurface)
                    if let model = app.server.state.modelName {
                        Text(model).font(.headlineLg).foregroundStyle(Theme.primary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            Spacer()
            HStack(spacing: 16) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    statBox("Uptime", uptimeString)
                }
                statBox("Requests", "\(app.server.requestCount)")
            }
        }
    }

    private var statusColor: Color {
        switch app.server.state {
        case .running: return Theme.systemGreen
        case .loading: return Theme.systemOrange
        case .error: return Theme.systemRed
        case .stopped: return Theme.outlineVariant
        }
    }
    private var statusLabel: String {
        switch app.server.state {
        case .running: return "SERVER ACTIVE"
        case .loading: return "LOADING MODEL"
        case .error: return "SERVER ERROR"
        case .stopped: return "SERVER STOPPED"
        }
    }
    private var statusTitle: String {
        switch app.server.state {
        case .running, .loading: return "Running:"
        case .error: return "Error"
        case .stopped: return "No model running"
        }
    }
    private var uptimeString: String {
        let t = Int(app.server.uptime)
        return String(format: "%02d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60)
    }

    private func statBox(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel(label)
            Text(value).font(.system(size: 20, weight: .medium, design: .monospaced)).foregroundStyle(Theme.onSurface)
        }
        .padding(16)
        .frame(minWidth: 140, alignment: .leading)
        .glassPanel(cornerRadius: 14)
    }

    // MARK: Telemetry row

    private var telemetryRow: some View {
        HStack(spacing: Theme.gutter) {
            tokensCard
            memoryCard
            endpointCard
        }
    }

    private var tokensCard: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    MonoLabel("Tokens/sec")
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(app.server.lastTokensPerSec.map { String(format: "%.1f", $0) } ?? "—")
                            .font(.headlineMd).foregroundStyle(Theme.onSurface)
                        Text("t/s").font(.bodySm).foregroundStyle(Theme.onSurfaceVariant)
                    }
                }
                Spacer()
                Image(systemName: "speedometer").foregroundStyle(Theme.primary)
            }
            Spacer()
            BarChart(values: normalizedThroughput).frame(height: 56)
        }
        .padding(Theme.lensPadding)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .glassPanel(cornerRadius: 20)
    }

    private var normalizedThroughput: [Double] {
        let history = app.server.throughputHistory.suffix(12)
        guard let max = history.max(), max > 0 else { return [] }
        return history.map { $0 / max }
    }

    private var memoryCard: some View {
        // Resident memory (incl. mmapped weights in RAM) — measured, not the
        // pre-launch estimate; estimates only drive the Library fits-check.
        let usedGB = app.server.state.isRunning
            ? Double(app.server.residentBytes ?? 0) / 1_073_741_824 : 0
        let budgetGB = Double(app.gpuBudgetBytes) / 1_073_741_824
        let modelFileGB = Double(app.server.currentModel?.fileSize ?? 0) / 1_073_741_824
        return VStack(alignment: .leading) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    MonoLabel("Memory (Measured)")
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", usedGB)).font(.headlineMd).foregroundStyle(Theme.onSurface)
                        Text(String(format: "GB / %.1f GB budget", budgetGB))
                            .font(.bodySm).foregroundStyle(Theme.onSurfaceVariant)
                    }
                }
                Spacer()
                Image(systemName: "memorychip").foregroundStyle(Theme.systemOrange)
            }
            Spacer()
            VStack(spacing: 8) {
                ProgressBar(value: budgetGB > 0 ? min(usedGB / budgetGB, 1) : 0, color: Theme.systemOrange)
                HStack {
                    Text(String(format: "MODEL FILE: %.1fGB", app.server.state.isRunning ? modelFileGB : 0))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.onSurfaceVariant)
                    Spacer()
                    Text("CTX: \(app.server.actualContextTokens.map(String.init) ?? "—")")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.onSurfaceVariant)
                }
            }
        }
        .padding(Theme.lensPadding)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .glassPanel(cornerRadius: 20)
    }

    private var endpointURL: String { "\(app.server.baseURL.absoluteString)/v1" }

    private var endpointCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Local Endpoint")
            HStack {
                Text(endpointURL).font(.monoData).foregroundStyle(Theme.primary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(endpointURL, forType: .string)
                    copiedEndpoint = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copiedEndpoint = false }
                } label: {
                    Image(systemName: copiedEndpoint ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundStyle(copiedEndpoint ? Theme.systemGreen : Theme.onSurfaceVariant)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.surfaceContainer, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.glassBorder, lineWidth: 1))

            Text("curl \(endpointURL)/chat/completions \\\n-H \"Content-Type: application/json\" \\\n-d '{ \"messages\": [{\"role\":\"user\",\"content\":\"Hi\"}] }'")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.onSurfaceVariant)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Theme.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.glassBorder, lineWidth: 1))
        }
        .padding(Theme.lensPadding)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .glassPanel(cornerRadius: 20)
    }

    // MARK: Tabs + panes

    private var tabs: some View {
        HStack(spacing: 28) {
            tabButton("Bench", "chart.bar", 0)
            tabButton("Logs", "terminal", 1)
        }
        .padding(.horizontal, 8)
        .overlay(Rectangle().fill(Theme.glassBorder).frame(height: 1), alignment: .bottom)
    }

    private func tabButton(_ title: String, _ symbol: String, _ index: Int) -> some View {
        Button { tab = index } label: {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: symbol).font(.system(size: 15))
                    Text(title).font(.bodyMd.weight(.bold))
                }
                .foregroundStyle(tab == index ? Theme.primary : Theme.onSurfaceVariant)
                Rectangle().fill(tab == index ? Theme.primary : .clear).frame(height: 2)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    private var splitPane: some View {
        HStack(alignment: .top, spacing: Theme.gutter) {
            benchTable.frame(maxWidth: .infinity)
            logsConsole.frame(width: 320)
        }
        .frame(maxHeight: .infinity)
    }

    private var benchTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Previous Runs").font(.headlineMd).foregroundStyle(Theme.onSurface)
                Text("SAMPLE").font(.monoLabel).foregroundStyle(Theme.systemOrange)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.systemOrange.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                Spacer()
                Button { } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle").font(.system(size: 13))
                        Text("Run New Bench").font(.bodySm)
                    }.foregroundStyle(Theme.primary)
                }.buttonStyle(.plain)
                .help("Bench panel arrives with SRV-11 (Milestone 3)")
            }
            .padding(16)
            .overlay(Rectangle().fill(Theme.glassBorder).frame(height: 1), alignment: .bottom)

            HStack(spacing: 0) {
                col("Model", .leading, 2)
                col("Quant", .leading, 1)
                col("Prompt t/s", .trailing, 1)
                col("Eval t/s", .trailing, 1)
                col("Date", .trailing, 1)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.surfaceContainerLow)

            VScroll {
                VStack(spacing: 0) {
                    ForEach(app.benchRuns) { run in
                        benchRow(run)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .glassPanel(cornerRadius: 20)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func col(_ title: String, _ align: Alignment, _ span: Int) -> some View {
        MonoLabel(title)
            .frame(maxWidth: .infinity, alignment: align)
            .layoutPriority(Double(span))
    }

    private func benchRow(_ run: BenchRun) -> some View {
        HStack(spacing: 0) {
            Text(run.model).font(.monoData).foregroundStyle(Theme.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(2)
            Text(run.quant).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.onSurface)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.surfaceContainerHighest, in: RoundedRectangle(cornerRadius: 4))
                .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
            Text(run.promptTS).font(.monoData.weight(.bold)).foregroundStyle(Theme.systemGreen)
                .frame(maxWidth: .infinity, alignment: .trailing).layoutPriority(1)
            Text(run.evalTS).font(.monoData).foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity, alignment: .trailing).layoutPriority(1)
            Text(run.date).font(.monoData).foregroundStyle(Theme.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .trailing).layoutPriority(1)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(Rectangle().fill(Theme.glassBorder.opacity(0.4)).frame(height: 1), alignment: .bottom)
    }

    private var logsConsole: some View {
        VStack(spacing: 0) {
            HStack {
                MonoLabel("Live Console")
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Theme.systemRed.opacity(0.3)).frame(width: 10, height: 10)
                    Circle().fill(Theme.systemOrange.opacity(0.3)).frame(width: 10, height: 10)
                    Circle().fill(Theme.systemGreen.opacity(0.3)).frame(width: 10, height: 10)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .overlay(Rectangle().fill(Theme.glassBorder).frame(height: 1), alignment: .bottom)

            ScrollViewReader { proxy in
                VScroll {
                    VStack(alignment: .leading, spacing: 5) {
                        if app.server.logs.isEmpty {
                            Text("No output yet. Start a model to see llama-server logs.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.onSurfaceVariant.opacity(0.6))
                        }
                        ForEach(app.server.logs) { line in
                            (Text(line.level.tag).foregroundColor(line.level.color)
                             + Text(" \(line.message)").foregroundColor(Theme.onSurfaceVariant))
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("_").font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.onSurfaceVariant)
                            .id("log-tail")
                    }
                    .padding(16)
                }
                .onChange(of: app.server.logs.count) {
                    proxy.scrollTo("log-tail", anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surfaceContainerLowest.opacity(0.8), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .glassPanel(cornerRadius: 20)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Vertical bar chart used in the tokens/sec telemetry card.
struct BarChart: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 4) {
                if values.isEmpty {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.primary.opacity(0.08))
                        .frame(height: 4)
                } else {
                    ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.primary.opacity(0.25 + 0.5 * (Double(i) / Double(max(values.count - 1, 1)))))
                            .frame(height: max(4, geo.size.height * v))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}
