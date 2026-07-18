import SwiftUI
import LlamaboardKit

/// The floating right inspector drawer: VRAM allocation, telemetry, sampler controls,
/// and a performance sparkline. Shared across Library and Chat.
struct Inspector: View {
    @EnvironmentObject var app: AppState
    @State private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Inspector").font(.headlineMd).foregroundStyle(Theme.onSurface)
                    Text("Local LLM Config").font(.bodySm).foregroundStyle(Theme.onSurfaceVariant.opacity(0.7))
                }
                Spacer()
                Button { app.inspectorVisible = false } label: {
                    Image(systemName: "xmark").font(.system(size: 13))
                        .foregroundStyle(Theme.onSurfaceVariant).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 20)

            HStack(spacing: 18) {
                tabButton("Model", 0)
                tabButton("Inference", 1)
                tabButton("System", 2)
            }
            .overlay(Rectangle().fill(Theme.glassBorder).frame(height: 1), alignment: .bottom)
            .padding(.bottom, 20)

            VScroll {
                VStack(alignment: .leading, spacing: 24) {
                    switch tab {
                    case 1:
                        inferenceTab
                    case 2:
                        systemTab
                    default:
                        vramSection
                        configSection
                        telemetrySection
                        perfHistory
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(Theme.lensPadding)
        .frame(width: Theme.inspectorWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassPanel(cornerRadius: 20)
    }

    // MARK: Inference tab — sampler settings, applied to the next message

    private var inferenceTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            MonoLabel("Sampling")
            sliderRow(title: "Temperature",
                      value: Binding(
                        get: { app.activeSettings.temperature },
                        set: { app.activeSettings.temperature = ($0 * 20).rounded() / 20 }),
                      range: 0...2,
                      display: String(format: "%.2f", app.activeSettings.temperature), tint: Theme.primary)
            sliderRow(title: "Top-K",
                      value: Binding(
                        get: { Double(app.activeSettings.topK) },
                        set: { app.activeSettings.topK = Int($0) }),
                      range: 1...200,
                      display: "\(app.activeSettings.topK)", tint: Theme.primary)
            sliderRow(title: "Top-P",
                      value: Binding(
                        get: { app.activeSettings.topP },
                        set: { app.activeSettings.topP = ($0 * 100).rounded() / 100 }),
                      range: 0.05...1,
                      display: String(format: "%.2f", app.activeSettings.topP), tint: Theme.primary)
            sliderRow(title: "Min-P",
                      value: Binding(
                        get: { app.activeSettings.minP },
                        set: { app.activeSettings.minP = ($0 * 100).rounded() / 100 }),
                      range: 0...0.5,
                      display: String(format: "%.2f", app.activeSettings.minP), tint: Theme.primary)
            sliderRow(title: "Repeat Penalty",
                      value: Binding(
                        get: { app.activeSettings.repeatPenalty },
                        set: { app.activeSettings.repeatPenalty = ($0 * 100).rounded() / 100 }),
                      range: 1...1.5,
                      display: String(format: "%.2f", app.activeSettings.repeatPenalty), tint: Theme.primary)

            MonoLabel("System Prompt").padding(.top, 8)
            TextEditor(text: Binding(
                get: { app.activeSettings.systemPrompt },
                set: { app.activeSettings.systemPrompt = $0 }))
                .font(.bodySm)
                .scrollContentBackground(.hidden)
                .frame(height: 88)
                .padding(8)
                .background(Theme.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.glassBorder, lineWidth: 1))

            Text("Sampler settings and the system prompt apply from the next message — no restart needed.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.onSurfaceVariant.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: System tab — hardware, endpoint, paths

    private var systemTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                MonoLabel("This Mac")
                HStack(spacing: 16) {
                    StatField(label: "Unified Memory",
                              value: String(format: "%.0f GB", Double(HardwareInfo.totalMemory) / 1_073_741_824))
                    StatField(label: "GPU Budget (est.)",
                              value: String(format: "%.0f GB", Double(HardwareInfo.gpuBudget) / 1_073_741_824))
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                MonoLabel("Endpoint")
                systemRow("Base URL", "\(app.server.baseURL.absoluteString)/v1")
                systemRow("Status", app.server.state.isRunning ? "Serving" : "Stopped")
                if app.server.state.isRunning {
                    systemRow("Requests", "\(app.server.requestCount)")
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                MonoLabel("Paths")
                systemRow("Models Folder", app.library.directory.path)
                systemRow("llama-server", app.resolvedServerBinaryPath)
            }
            Button { app.showSettings = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape").font(.system(size: 12))
                    Text("Open Settings").font(.bodySm)
                }
                .foregroundStyle(Theme.primary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Theme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func systemRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.bodySm).foregroundStyle(Theme.onSurfaceVariant)
            Text(value).font(.monoData).foregroundStyle(Theme.onSurface)
                .lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tabButton(_ title: String, _ index: Int) -> some View {
        Button { tab = index } label: {
            VStack(spacing: 8) {
                Text(title).font(.bodyMd)
                    .foregroundStyle(tab == index ? Theme.primary : Theme.onSurfaceVariant)
                Rectangle().fill(tab == index ? Theme.primary : .clear).frame(height: 2)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    private var vramSection: some View {
        let budget = Double(app.gpuBudgetBytes)
        // Measured process footprint while running; nothing shown as "used"
        // when stopped (estimates only drive the Library fits-check badges).
        // Resident size includes the mmapped model weights held in RAM — the
        // number users expect. (Footprint alone undercounts by the weights.)
        // NOTE: `.map(Double.init)` must not be used here — Swift resolves that
        // unapplied reference to Double(bitPattern:), which bit-casts the UInt64
        // into a denormal instead of converting it numerically.
        let measured = app.server.residentBytes.map { Double($0) }
        let used = app.server.state.isRunning ? (measured ?? 0) : 0
        return VStack(alignment: .leading, spacing: 12) {
            MonoLabel("Memory")
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(format: "Used: %.1f GB", used / 1_073_741_824))
                        .font(.monoData).foregroundStyle(Theme.onSurface)
                    Spacer()
                    Text(String(format: "Budget: %.1f GB", budget / 1_073_741_824))
                        .font(.monoData).foregroundStyle(Theme.onSurface)
                }
                ProgressBar(value: budget > 0 ? min(used / budget, 1) : 0, color: Theme.systemGreen)
                Text(app.server.state.isRunning
                     ? "Resident memory incl. mapped weights" + footprintSuffix
                     : "Shown while a model is running")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.onSurfaceVariant.opacity(0.6))
            }
            .padding(14)
            .glassPanel(cornerRadius: 14)
        }
    }

    private var footprintSuffix: String {
        guard let fp = app.server.memoryFootprint else { return "" }
        return String(format: " (%.1f GB app footprint)", Double(fp) / 1_073_741_824)
    }

    private var maxContext: Double {
        Double(app.activeModel?.metadata?.contextLength ?? 32768)
    }
    /// Real offload from llama-server's load log when available; the
    /// configured intent (all layers) otherwise.
    private var layerCount: String {
        if let actual = app.server.actualGpuLayers, app.server.state.isRunning {
            return actual
        }
        return app.activeModel?.metadata?.blockCount.map { "\($0)/\($0)" } ?? "—"
    }
    /// True context: what the server allocated, not just what the slider says.
    private var contextDisplay: String {
        if app.server.state.isRunning, let actual = app.server.actualContextTokens {
            return "\(actual)"
        }
        return "\(app.activeSettings.contextSize)"
    }
    /// The profile changed while running — a restart is needed to apply it.
    private var contextPendingRestart: Bool {
        app.server.state.isRunning
        && app.server.actualContextTokens != nil
        && app.server.actualContextTokens != app.activeSettings.contextSize
    }

    private var offloadFraction: Double {
        let parts = layerCount.split(separator: "/").compactMap { Double($0) }
        guard parts.count == 2, parts[1] > 0 else { return 0 }
        return parts[0] / parts[1]
    }
    private var offloadCaption: String {
        if app.server.state.isRunning, app.server.actualGpuLayers != nil {
            return offloadFraction >= 1.0 ? "Full offload to Metal (measured)"
                                          : "Partial offload to Metal (measured)"
        }
        return "Configured: offload all layers"
    }

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            MonoLabel("Configuration")
            sliderRow(title: "Context Size",
                      value: Binding(
                        get: { Double(app.activeSettings.contextSize) },
                        set: { app.activeSettings.contextSize = Int($0 / 512) * 512 }),
                      range: 512...max(maxContext, 2048),
                      display: "\(app.activeSettings.contextSize)", tint: Theme.primary)
            if contextPendingRestart {
                HStack(spacing: 6) {
                    Circle().fill(Theme.systemOrange).frame(width: 6, height: 6)
                    Text("Server is running with \(app.server.actualContextTokens ?? 0) — restart the model to apply \(app.activeSettings.contextSize).")
                        .font(.system(size: 10)).foregroundStyle(Theme.systemOrange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            sliderRow(title: "Temperature",
                      value: Binding(
                        get: { app.activeSettings.temperature },
                        set: { app.activeSettings.temperature = ($0 * 20).rounded() / 20 }),
                      range: 0...2,
                      display: String(format: "%.2f", app.activeSettings.temperature), tint: Theme.primary)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("GPU Layers").font(.bodySm).foregroundStyle(Theme.onSurface)
                    Spacer()
                    Text(layerCount).font(.monoData).foregroundStyle(Theme.systemGreen)
                }
                ProgressBar(value: offloadFraction, color: Theme.systemGreen)
                Text(offloadCaption)
                    .font(.monoLabel).foregroundStyle(Theme.systemGreen)
            }
            if app.server.state.isRunning {
                Text("Context size applies on next model start; sampler settings apply to the next message.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.onSurfaceVariant.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @Environment(\.isSnapshot) private var isSnapshot

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           display: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.bodySm).foregroundStyle(Theme.onSurface)
                Spacer()
                Text(display).font(.monoData).foregroundStyle(tint)
            }
            if isSnapshot {
                // Native sliders draw as focus artifacts offscreen.
                let fraction = (value.wrappedValue - range.lowerBound) / (range.upperBound - range.lowerBound)
                ProgressBar(value: fraction, color: tint).frame(height: 4)
            } else {
                Slider(value: value, in: range).tint(tint).controlSize(.small)
            }
        }
    }

    private var telemetrySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoLabel("Telemetry")
            telemetryRow("Tokens/sec",
                         app.server.lastTokensPerSec.map { String(format: "%.1f", $0) } ?? "—",
                         Theme.primary)
            telemetryRow("Context Window", contextDisplay, Theme.onSurface)
            telemetryRow("Layer Offload", layerCount, Theme.onSurface)
        }
    }

    private func telemetryRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label).font(.bodySm).foregroundStyle(Theme.onSurface)
            Spacer()
            Text(value).font(.monoData).foregroundStyle(color)
        }
        .padding(.vertical, 6)
        .overlay(Rectangle().fill(Theme.glassBorder.opacity(0.3)).frame(height: 1), alignment: .bottom)
    }

    private var perfHistory: some View {
        let history = app.server.throughputHistory
        let peak = history.max() ?? 1
        let points = history.map { $0 / max(peak, 0.001) }
        return VStack(alignment: .leading, spacing: 12) {
            MonoLabel("Performance History")
            Group {
                if points.count >= 2 {
                    Sparkline(points: points)
                } else if points.count == 1 {
                    // One sample: draw it flat so the value is still visible.
                    Sparkline(points: [points[0], points[0]])
                } else {
                    Text("Metrics appear after the first chat response.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.onSurfaceVariant.opacity(0.6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 72)
            .padding(8)
            .glassPanel(cornerRadius: 14)
        }
    }
}

/// A thin rounded progress meter.
struct ProgressBar: View {
    let value: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceContainerHigh)
                Capsule().fill(color)
                    .frame(width: geo.size.width * value)
                    .shadow(color: color.opacity(0.5), radius: 4)
            }
        }
        .frame(height: 8)
    }
}

/// A filled line sparkline used in the inspector performance card.
struct Sparkline: View {
    let points: [Double]
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let step = points.count > 1 ? w / CGFloat(points.count - 1) : w
            let pts = points.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) * step, y: h - CGFloat(v) * h)
            }
            ZStack {
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: CGPoint(x: first.x, y: h))
                    p.addLine(to: first)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Theme.primary.opacity(0.25), .clear],
                                     startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(Theme.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
