import Foundation

/// One captured line of llama-server output, classified for display.
public struct ServerLogLine: Identifiable, Sendable {
    public enum Level: Sendable { case info, success, warn, error, debug }
    public let id = UUID()
    public let level: Level
    public let message: String
    public let date = Date()

    /// Classify a raw llama-server stderr/stdout line.
    static func classify(_ raw: String) -> ServerLogLine {
        let lower = raw.lowercased()
        let level: Level
        if lower.contains("error") || lower.contains("failed") { level = .error }
        else if lower.contains("warn") { level = .warn }
        else if lower.contains("loaded") || lower.contains("listening") { level = .success }
        else if lower.hasPrefix("srv") || lower.contains("http") { level = .info }
        else { level = .debug }
        return ServerLogLine(level: level, message: raw)
    }
}

/// Supervises a single `llama-server` child process (PRD SRV-1..SRV-5, §8.3):
/// spawn with profile-derived flags → poll /health until ready → running; capture
/// logs into a ring buffer; SIGTERM teardown; error state carries the stderr tail.
@MainActor
public final class ServerManager: ObservableObject {

    public enum State: Equatable, Sendable {
        case stopped
        case loading(model: String)
        case running(model: String)
        case error(message: String)

        public var isRunning: Bool { if case .running = self { return true }; return false }
        public var isBusy: Bool { if case .loading = self { return true }; return false }
        public var modelName: String? {
            switch self {
            case .loading(let m), .running(let m): return m
            default: return nil
            }
        }
    }

    @Published public private(set) var state: State = .stopped
    @Published public private(set) var logs: [ServerLogLine] = []
    @Published public private(set) var startedAt: Date?
    @Published public private(set) var requestCount = 0
    @Published public private(set) var port: Int = 8080
    @Published public private(set) var currentModel: LibraryModel?

    /// tokens/sec samples from recent chat responses, for the telemetry sparkline.
    @Published public private(set) var throughputHistory: [Double] = []
    @Published public private(set) var lastTokensPerSec: Double?

    // Measured truth, replacing pre-launch estimates in the UI (see /props,
    // the process footprint, and llama-server's own log lines).
    /// n_ctx the server actually allocated, from GET /props.
    @Published public private(set) var actualContextTokens: Int?
    /// "offloaded X/Y layers" parsed from llama-server's load log.
    @Published public private(set) var actualGpuLayers: String?
    /// phys_footprint of the llama-server process in bytes (dirty/compressed
    /// memory — what Activity Monitor's "Memory" column shows). llama.cpp
    /// memory-maps model weights, so this UNDERCOUNTS by the weights size.
    @Published public private(set) var memoryFootprint: UInt64?
    /// Resident size in bytes — includes the mmapped weights actually held in
    /// RAM, which matches what users expect "model memory" to mean.
    @Published public private(set) var residentBytes: UInt64?

    private var process: Process?
    private var footprintTask: Task<Void, Never>?
    private let maxLogLines = 2000

    /// User-chosen llama-server path (Settings → server binary, PRD SRV-7).
    /// Checked before auto-detection. Set to nil to return to auto-detect.
    @MainActor public static var customBinaryPath: String?

    /// Resolve the llama-server binary: custom override → env var → bundled
    /// (PRD SRV-6) → Homebrew → /usr/local. The bundled path is where a packaged
    /// .app would carry its runtime; in this SwiftPM dev build Homebrew is the
    /// effective source.
    @MainActor public static func findServerBinary() -> URL? {
        var candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bin/llama-server"),
            URL(fileURLWithPath: "/opt/homebrew/bin/llama-server"),
            URL(fileURLWithPath: "/usr/local/bin/llama-server"),
        ]
        if let env = ProcessInfo.processInfo.environment["LLAMABOARD_SERVER_BIN"] {
            candidates.insert(URL(fileURLWithPath: env), at: 0)
        }
        if let custom = customBinaryPath, !custom.isEmpty {
            candidates.insert(URL(fileURLWithPath: custom), at: 0)
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public init() {}

    public var baseURL: URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    public var uptime: TimeInterval {
        startedAt.map { Date().timeIntervalSince($0) } ?? 0
    }

    // MARK: - Lifecycle

    public func start(model: LibraryModel, settings: ModelSettings) {
        guard !state.isBusy else { return }
        stop()

        guard let binary = Self.findServerBinary() else {
            state = .error(message: "llama-server not found. Install llama.cpp (brew install llama.cpp) or set LLAMABOARD_SERVER_BIN.")
            return
        }

        logs.removeAll()
        requestCount = 0
        throughputHistory.removeAll()
        lastTokensPerSec = nil
        actualContextTokens = nil
        actualGpuLayers = nil
        memoryFootprint = nil
        residentBytes = nil
        port = settings.port
        currentModel = model
        state = .loading(model: model.displayName)

        let proc = Process()
        proc.executableURL = binary
        proc.arguments = settings.serverArguments(modelPath: model.url.path)

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in
                self?.append(output: text)
            }
        }

        proc.terminationHandler = { [weak self] p in
            Task { @MainActor [weak self] in
                self?.processDidExit(status: p.terminationStatus)
            }
        }

        do {
            try proc.run()
            process = proc
            appendLog(.info, "Launching \(binary.lastPathComponent) on port \(port)")
            appendLog(.info, "$ llama-server \(proc.arguments!.joined(separator: " "))")
            Task { await pollUntilHealthy(model: model.displayName) }
        } catch {
            state = .error(message: "Failed to launch llama-server: \(error.localizedDescription)")
        }
    }

    public func stop() {
        guard let proc = process else { return }
        footprintTask?.cancel()
        footprintTask = nil
        proc.terminationHandler = nil
        (proc.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if proc.isRunning { proc.terminate() }   // SIGTERM
        process = nil
        startedAt = nil
        currentModel = nil
        actualContextTokens = nil
        memoryFootprint = nil
        residentBytes = nil
        state = .stopped
        appendLog(.info, "Server stopped")
    }

    public func recordChatMetrics(tokensPerSec: Double) {
        requestCount += 1
        lastTokensPerSec = tokensPerSec
        throughputHistory.append(tokensPerSec)
        if throughputHistory.count > 24 { throughputHistory.removeFirst() }
    }

    // MARK: - Internals

    private func processDidExit(status: Int32) {
        guard process != nil else { return }
        footprintTask?.cancel()
        footprintTask = nil
        process = nil
        startedAt = nil
        currentModel = nil
        actualContextTokens = nil
        memoryFootprint = nil
        residentBytes = nil
        if status != 0 {
            let tail = logs.suffix(6).map(\.message).joined(separator: "\n")
            state = .error(message: "llama-server exited (status \(status)).\n\(tail)")
        } else {
            state = .stopped
        }
    }

    private func pollUntilHealthy(model: String) async {
        let url = baseURL.appendingPathComponent("health")
        for _ in 0..<240 {  // up to ~2 min for big models
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard process?.isRunning == true else { return }  // exit handler took over
            if let (data, response) = try? await URLSession.shared.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200,
               String(decoding: data, as: UTF8.self).contains("ok") {
                startedAt = Date()
                state = .running(model: model)
                appendLog(.success, "Model loaded successfully — endpoint ready at \(baseURL.absoluteString)/v1")
                await fetchServerProps()
                startFootprintSampling()
                return
            }
        }
        appendLog(.error, "Health check timed out")
        stop()
        state = .error(message: "Server did not become healthy within 2 minutes.")
    }

    /// Ask the server what it actually allocated (n_ctx may differ from the
    /// requested profile when llama-server clamps it to the model's limit).
    private func fetchServerProps() async {
        let url = baseURL.appendingPathComponent("props")
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let settings = json["default_generation_settings"] as? [String: Any],
           let nCtx = settings["n_ctx"] as? Int {
            actualContextTokens = nCtx
        }
    }

    /// Sample the child process's phys_footprint (Activity Monitor's "Memory")
    /// every few seconds while running.
    private func startFootprintSampling() {
        footprintTask?.cancel()
        guard let pid = process?.processIdentifier else { return }
        footprintTask = Task { [weak self] in
            while !Task.isCancelled {
                let footprint = Self.physFootprint(pid: pid)
                let resident = Self.residentSize(pid: pid)
                await MainActor.run { [weak self] in
                    guard let self, self.state.isRunning else { return }
                    self.memoryFootprint = footprint
                    self.residentBytes = resident
                }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    /// phys_footprint in bytes for a pid, via proc_pid_rusage.
    nonisolated static func physFootprint(pid: Int32) -> UInt64? {
        var info = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPtr in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, reboundPtr)
            }
        }
        guard result == 0 else { return nil }
        return info.ri_phys_footprint
    }

    /// Resident size for a pid via proc_pidinfo — includes file-backed
    /// (mmapped model weight) pages currently in RAM.
    nonisolated static func residentSize(pid: Int32) -> UInt64? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let written = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard written == size else { return nil }
        return info.pti_resident_size
    }

    /// llama-server logs "offloaded X/Y layers to GPU" during model load.
    public static func parseOffloadedLayers(_ line: String) -> String? {
        guard let range = line.range(of: #"offloaded (\d+)/(\d+) layers"#,
                                     options: .regularExpression) else { return nil }
        let match = line[range]
        let numbers = match.split(whereSeparator: { !$0.isNumber && $0 != "/" })
        return numbers.first.map(String.init)
    }

    private func append(output: String) {
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let entry = ServerLogLine.classify(String(line))
            logs.append(entry)
            if let layers = Self.parseOffloadedLayers(String(line)) {
                actualGpuLayers = layers
            }
        }
        if logs.count > maxLogLines {
            logs.removeFirst(logs.count - maxLogLines)
        }
    }

    private func appendLog(_ level: ServerLogLine.Level, _ message: String) {
        logs.append(ServerLogLine(level: level, message: message))
    }
}
