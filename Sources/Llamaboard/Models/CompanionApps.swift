import AppKit
import SwiftUI
import LlamaboardKit

/// One companion app the launcher knows how to detect and start (PRD §6.7).
struct CompanionApp: Identifiable {
    enum Kind {
        /// A GUI app, located by trying bundle paths in order.
        case gui(bundlePaths: [String])
        /// A CLI tool, located by trying executable paths in order; launched in Terminal.
        case cli(binPaths: [String])
        /// A user-added .app bundle or executable.
        case custom(path: String)
    }

    let id: String
    let name: String
    let tagline: String
    let kind: Kind
    var installURL: URL? = nil
    var fallbackSymbol: String = "app.dashed"

    /// Filesystem location if installed, nil otherwise.
    var resolvedPath: String? {
        let fm = FileManager.default
        switch kind {
        case .gui(let paths):
            return paths.map { NSString(string: $0).expandingTildeInPath }
                .first { fm.fileExists(atPath: $0) }
        case .cli(let paths):
            return paths.map { NSString(string: $0).expandingTildeInPath }
                .first { fm.isExecutableFile(atPath: $0) }
        case .custom(let path):
            return fm.fileExists(atPath: path) ? path : nil
        }
    }

    var isInstalled: Bool { resolvedPath != nil }
    var isCustom: Bool { if case .custom = kind { return true }; return false }

    /// The real app icon when installed, for the card.
    var icon: NSImage? {
        resolvedPath.map { NSWorkspace.shared.icon(forFile: $0) }
    }
}

/// Detects, persists (custom entries), and launches companion apps with the
/// Llamaboard endpoint injected via the OpenAI-compatible env convention.
@MainActor
final class CompanionAppsManager: ObservableObject {
    private static let customKey = "customCompanionApps"

    /// Launch set (APP-1). Data-driven: adding an app is a new entry here.
    static let known: [CompanionApp] = [
        CompanionApp(
            id: "hermes",
            name: "Hermes",
            tagline: "Nous Research's agent — Launch configures it to chat through your running model.",
            kind: .gui(bundlePaths: ["/Applications/Hermes.app", "~/Applications/Hermes.app"]),
            installURL: URL(string: "https://hermes.nousresearch.com"),
            fallbackSymbol: "message.badge.waveform"),
        CompanionApp(
            id: "openclaw",
            name: "OpenClaw",
            tagline: "Personal AI assistant gateway — runs against your local model.",
            kind: .cli(binPaths: ["/opt/homebrew/bin/openclaw", "/usr/local/bin/openclaw",
                                  "~/.local/bin/openclaw", "~/.npm-global/bin/openclaw"]),
            installURL: URL(string: "https://openclaw.ai"),
            fallbackSymbol: "pawprint"),
    ]

    @Published private(set) var apps: [CompanionApp] = []
    @Published var lastLaunchError: String?
    @Published var lastLaunchNote: String?

    init() { refresh() }

    func refresh() {
        let customPaths = UserDefaults.standard.stringArray(forKey: Self.customKey) ?? []
        let custom = customPaths.map { path in
            CompanionApp(
                id: "custom:\(path)",
                name: FileManager.default.displayName(atPath: path),
                tagline: path,
                kind: .custom(path: path),
                fallbackSymbol: "app")
        }
        apps = Self.known + custom
    }

    func addCustomApp(path: String) {
        var paths = UserDefaults.standard.stringArray(forKey: Self.customKey) ?? []
        guard !paths.contains(path) else { return }
        paths.append(path)
        UserDefaults.standard.set(paths, forKey: Self.customKey)
        refresh()
    }

    func removeCustomApp(_ app: CompanionApp) {
        guard case .custom(let path) = app.kind else { return }
        var paths = UserDefaults.standard.stringArray(forKey: Self.customKey) ?? []
        paths.removeAll { $0 == path }
        UserDefaults.standard.set(paths, forKey: Self.customKey)
        refresh()
    }

    /// Launch an app pre-wired to the endpoint (APP-2). `endpoint` is nil when
    /// no model is running — the app still opens, unconfigured.
    ///
    /// Env vars alone aren't enough for apps that manage their own provider
    /// config, so apps with a known config format get it written first:
    /// Hermes reads ~/.hermes/config.yaml, where `provider: custom` +
    /// `base_url` selects a generic OpenAI-compatible endpoint.
    func launch(_ app: CompanionApp, endpoint: URL?, modelName: String?) {
        guard let path = app.resolvedPath else { return }
        lastLaunchError = nil
        lastLaunchNote = nil

        if app.id == "hermes", let endpoint, let modelName, HermesIntegration.isInstalled {
            do {
                let backup = try HermesIntegration.configure(
                    baseURL: endpoint.absoluteString, model: modelName)
                var note = "Hermes configured: \(modelName) via \(endpoint.absoluteString)."
                if let backup {
                    note += " Original config backed up to \(backup.lastPathComponent)."
                }
                note += " If Hermes was already open, restart it to pick up the change."
                lastLaunchNote = note
            } catch {
                lastLaunchError = "Couldn't write Hermes config: \(error.localizedDescription)"
                return
            }
        }

        var env: [String: String] = [:]
        if let endpoint {
            env["OPENAI_BASE_URL"] = endpoint.absoluteString
            env["OPENAI_API_BASE"] = endpoint.absoluteString   // older convention
            env["OPENAI_API_KEY"] = "llamaboard"
        }

        let isBundle = path.hasSuffix(".app")
        if isBundle {
            let config = NSWorkspace.OpenConfiguration()
            config.environment = env
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: config) { _, error in
                if let error {
                    Task { @MainActor [weak self] in
                        self?.lastLaunchError = "Couldn't launch \(app.name): \(error.localizedDescription)"
                    }
                }
            }
        } else {
            launchInTerminal(executable: path, env: env, appName: app.name)
        }
    }

    /// CLI tools open in a Terminal window with the env prefixed, so their output
    /// stays visible to the user.
    private func launchInTerminal(executable: String, env: [String: String], appName: String) {
        let envPrefix = env.map { "\($0.key)=\"\($0.value)\"" }.joined(separator: " ")
        let command = "\(envPrefix) \"\(executable)\"".trimmingCharacters(in: .whitespaces)
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        do { try proc.run() } catch {
            lastLaunchError = "Couldn't launch \(appName): \(error.localizedDescription)"
        }
    }
}
