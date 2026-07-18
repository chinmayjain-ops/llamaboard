import Foundation

/// Per-model settings profile (PRD §6.3). Persisted as human-readable JSON,
/// one file per model, in Application Support/Llamaboard/Profiles.
public struct ModelSettings: Codable, Sendable, Equatable {
    // Common
    public var contextSize: Int = 4096
    public var temperature: Double = 0.7
    public var systemPrompt: String = ""
    public var gpuLayers: Int = -1          // -1 = offload all (llama-server default 999)

    // Sampling
    public var topK: Int = 40
    public var topP: Double = 0.95
    public var minP: Double = 0.05
    public var repeatPenalty: Double = 1.1
    public var maxTokens: Int = -1          // -1 = unlimited
    public var seed: Int = -1               // -1 = random

    // Memory & performance
    public var threads: Int = -1            // -1 = auto
    public var flashAttention: Bool = true
    public var mlock: Bool = false
    public var kvCacheTypeK: String = "f16" // f16 | q8_0 | q4_0
    public var kvCacheTypeV: String = "f16"

    // Server
    public var port: Int = 8080
    public var parallelSlots: Int = 1
    public var extraArgs: String = ""       // escape hatch, appended verbatim

    public init() {}

    /// llama-server invocation arguments for this profile (SET-4 "copy as command"
    /// uses the same array joined for display).
    public func serverArguments(modelPath: String) -> [String] {
        // Advertise a clean model id on /v1/models (file stem, not the full path)
        // so clients like Hermes show a readable name.
        let alias = ((modelPath as NSString).lastPathComponent as NSString).deletingPathExtension
        var args: [String] = [
            "-m", modelPath,
            "-a", alias,
            "--port", String(port),
            "--ctx-size", String(contextSize),
            "--temp", String(temperature),
            "--top-k", String(topK),
            "--top-p", String(topP),
            "--min-p", String(minP),
            "--repeat-penalty", String(repeatPenalty),
            "--parallel", String(parallelSlots),
        ]
        if gpuLayers >= 0 { args += ["--gpu-layers", String(gpuLayers)] }
        if threads > 0 { args += ["--threads", String(threads)] }
        if seed >= 0 { args += ["--seed", String(seed)] }
        if maxTokens > 0 { args += ["--n-predict", String(maxTokens)] }
        if flashAttention { args += ["--flash-attn", "on"] }
        if mlock { args += ["--mlock"] }
        if kvCacheTypeK != "f16" { args += ["--cache-type-k", kvCacheTypeK] }
        if kvCacheTypeV != "f16" { args += ["--cache-type-v", kvCacheTypeV] }
        if !extraArgs.isEmpty {
            args += extraArgs.split(separator: " ").map(String.init)
        }
        return args
    }
}

/// Loads and saves settings profiles keyed by the model file's basename.
public struct SettingsStore: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? AppPaths.profiles
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func url(for modelFile: String) -> URL {
        let stem = (modelFile as NSString).deletingPathExtension
        return directory.appendingPathComponent("\(stem).json")
    }

    public func load(for modelFile: String) -> ModelSettings {
        let u = url(for: modelFile)
        guard let data = try? Data(contentsOf: u),
              let settings = try? JSONDecoder().decode(ModelSettings.self, from: data) else {
            return ModelSettings()
        }
        return settings
    }

    public func save(_ settings: ModelSettings, for modelFile: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url(for: modelFile), options: .atomic)
    }
}

/// Standard app directories (PRD §8.1). Created on first access.
public enum AppPaths {
    public static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Llamaboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    public static var models: URL {
        let dir = appSupport.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    public static var profiles: URL {
        appSupport.appendingPathComponent("Profiles", isDirectory: true)
    }
    public static var logs: URL {
        let dir = appSupport.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
