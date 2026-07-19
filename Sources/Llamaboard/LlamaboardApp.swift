import SwiftUI
import AppKit
import LlamaboardKit

@main
struct LlamaboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

/// Ensures the app activates and shows a regular window when launched from a bare
/// SwiftPM executable (no app bundle / Info.plist).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Stitch-designed llama glass tile as the Dock icon (a SwiftPM executable
        // has no bundle Info.plist icon, so set it at runtime).
        if let logo = AppLogo.image {
            NSApp.applicationIconImage = logo
        }

        // Debug: `Llamaboard --snapshot <dir>` renders every section to PNGs
        // offscreen and exits. Used for headless visual verification.
        if let flagIndex = CommandLine.arguments.firstIndex(of: "--snapshot"),
           CommandLine.arguments.count > flagIndex + 1 {
            let dir = URL(fileURLWithPath: CommandLine.arguments[flagIndex + 1], isDirectory: true)
            let live = CommandLine.arguments.contains("--live")
            Task { @MainActor in
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                // Give the library scan a moment to finish so cards render.
                try? await Task.sleep(for: .seconds(1.5))

                // --live: exercise the real pipeline first — start the model,
                // run one chat exchange, then capture the running-state UI.
                if live {
                    let state = AppState.shared
                    // --model <substring>: pick a specific library model for the
                    // live run instead of the first one.
                    if let modelIndex = CommandLine.arguments.firstIndex(of: "--model"),
                       CommandLine.arguments.count > modelIndex + 1 {
                        let needle = CommandLine.arguments[modelIndex + 1].lowercased()
                        if let match = state.library.models.first(where: { $0.displayName.lowercased().contains(needle) }) {
                            state.select(match)
                        }
                    }
                    state.startSelectedModel()
                    for _ in 0..<240 where !state.server.state.isRunning {
                        if case .error = state.server.state { break }
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                    if state.server.state.isRunning {
                        state.sendMessage("In two sentences, why does quantization make local LLMs practical?")
                        for _ in 0..<240 where state.isGenerating || state.messages.count < 2 {
                            try? await Task.sleep(for: .milliseconds(500))
                        }
                    }
                }

                @MainActor func capture(_ name: String) {
                    let view = RootView()
                        .environmentObject(AppState.shared)
                        .environment(\.isSnapshot, true)
                        .frame(width: 1440, height: 900)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    if let tiff = renderer.nsImage?.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: dir.appendingPathComponent("\(name).png"))
                    }
                }
                // --download "<pasted input>": exercise the paste-to-download
                // pipeline end to end, capturing Discover mid-download and after.
                if let downloadIndex = CommandLine.arguments.firstIndex(of: "--download"),
                   CommandLine.arguments.count > downloadIndex + 1 {
                    let input = CommandLine.arguments[downloadIndex + 1]
                    let state = AppState.shared
                    state.section = .discover
                    await state.downloads.start(input: input)
                    var midCaptured = false
                    for _ in 0..<600 {
                        guard state.downloads.hasActiveDownloads else { break }
                        if !midCaptured, let first = state.downloads.items.first,
                           first.phase == .downloading, first.fractionDone > 0.15 {
                            capture("Discover-downloading")
                            midCaptured = true
                        }
                        try? await Task.sleep(for: .milliseconds(300))
                    }
                    capture("Discover-done")
                    let status = state.downloads.items.first.map { "\($0.fileName) — \($0.phase)" } ?? "no item"
                    FileHandle.standardError.write(Data("[llamaboard] download result: \(status)\n".utf8))
                }

                // --hf-query <q>: run a live hub search before capturing Discover.
                if let hfIndex = CommandLine.arguments.firstIndex(of: "--hf-query"),
                   CommandLine.arguments.count > hfIndex + 1 {
                    let state = AppState.shared
                    state.searchQuery = CommandLine.arguments[hfIndex + 1]
                    state.hubSearch.run(query: state.searchQuery, immediate: true)
                    for _ in 0..<60 where state.hubSearch.results.isEmpty && state.hubSearch.errorMessage == nil {
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                }

                // --quant-picker <repo>: open the picker for a specific repo.
                if let pickerIndex = CommandLine.arguments.firstIndex(of: "--quant-picker"),
                   CommandLine.arguments.count > pickerIndex + 1 {
                    let repo = CommandLine.arguments[pickerIndex + 1]
                    let state = AppState.shared
                    state.section = .discover
                    if let files = try? await HFHub.quantFiles(repo: repo) {
                        state.quantPickerPreload = files
                        state.quantPickerTarget = HFSearchResult(
                            repo: repo, author: repo.split(separator: "/").first.map(String.init) ?? "",
                            downloads: 0, likes: 0, gated: false, pipelineTag: "text-generation",
                            lastModified: nil, ggufFiles: files.map(\.fileName))
                        capture("QuantPicker")
                        state.quantPickerTarget = nil
                        state.quantPickerPreload = nil
                    }
                }

                // --search <query>: pre-fill the search field to verify filtering.
                if let queryIndex = CommandLine.arguments.firstIndex(of: "--search"),
                   CommandLine.arguments.count > queryIndex + 1 {
                    AppState.shared.searchQuery = CommandLine.arguments[queryIndex + 1]
                }
                for section in Section.allCases {
                    AppState.shared.section = section
                    capture(section.rawValue)
                }
                AppState.shared.section = .library
                AppState.shared.showSettings = true
                capture("Settings")
                AppState.shared.showSettings = false
                AppState.shared.server.stop()
                NSApp.terminate(nil)
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    /// PRD §8.3: never orphan the llama-server child process.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppState.shared.server.stop()
        }
    }
}
