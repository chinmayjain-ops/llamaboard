import Foundation
import LlamaboardKit

/// Headless end-to-end smoke test of LlamaboardKit:
///   1. locate a GGUF (argv[1] or first model in the managed directory)
///   2. parse its header
///   3. start llama-server via ServerManager
///   4. stream a chat completion via ChatClient
///   5. stop the server
/// Exits 0 on success, 1 on failure.

func fail(_ message: String) -> Never {
    print("SMOKE FAIL: \(message)")
    exit(1)
}

let arguments = CommandLine.arguments

/// `llamaboard-smoke --hf-search [query]` exercises the live hub search only.
if arguments.contains("--hf-search") {
    let query = arguments.last.flatMap { $0 == "--hf-search" ? nil : $0 } ?? ""
    Task { @MainActor in
        do {
            for sort in HFSortOrder.allCases {
                let results = try await HFHub.search(query: query, sort: sort, limit: 5)
                guard !results.isEmpty else { fail("no results for sort=\(sort.rawValue)") }
                print("── sort=\(sort.label) (\(results.count) results)")
                for r in results.prefix(3) {
                    let quants = r.quantTags.prefix(4).joined(separator: ",")
                    print("   \(r.repo) — \(r.downloads) dl, \(r.ggufFiles.count) gguf" +
                          "\(r.gated ? ", GATED" : "")\(r.isSplitOnly ? ", SPLIT" : "")" +
                          "\(quants.isEmpty ? "" : " [\(quants)]")")
                }
            }
            print("SMOKE PASS (hf-search)")
            exit(0)
        } catch {
            fail("hub search error: \(error)")
        }
    }
    RunLoop.main.run()
}

@MainActor
func run() async {
    // 1. Locate a model
    let modelURL: URL
    if arguments.count > 1 {
        modelURL = URL(fileURLWithPath: arguments[1])
    } else {
        let dir = AppPaths.models
        guard let first = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .first(where: { $0.pathExtension == "gguf" }) else {
            fail("no GGUF found in \(dir.path); pass a model path as argv[1]")
        }
        modelURL = first
    }
    print("── model: \(modelURL.path)")

    // 2. Parse header
    let meta: GGUFMetadata
    do { meta = try GGUFReader.read(url: modelURL) }
    catch { fail("GGUF parse error: \(error)") }
    print("── gguf v\(meta.version): arch=\(meta.architecture ?? "?") name=\(meta.modelName ?? "?") " +
          "params=\(meta.parameterLabel) quant=\(meta.quantName ?? "?") ctx=\(meta.contextLength.map(String.init) ?? "?") " +
          "layers=\(meta.blockCount.map(String.init) ?? "?")")

    let fileSize = (try? modelURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
    var settings = ModelSettings()
    settings.contextSize = 2048
    settings.port = 18080   // avoid clashing with anything on 8080
    print("── fit: \(HardwareInfo.fit(fileSize: fileSize, metadata: meta, contextTokens: 2048)) " +
          "(\(HardwareInfo.estimatedRAM(fileSize: fileSize, metadata: meta, contextTokens: 2048)))")

    // 3. Start server
    let model = LibraryModel(url: modelURL, fileName: modelURL.lastPathComponent,
                             fileSize: fileSize, metadata: meta, metadataError: nil)
    let server = ServerManager()
    server.start(model: model, settings: settings)

    var waited = 0.0
    while !server.state.isRunning {
        if case .error(let message) = server.state { fail("server error: \(message)") }
        if waited > 120 { fail("server did not become healthy in 120s") }
        try? await Task.sleep(nanoseconds: 250_000_000)
        waited += 0.25
    }
    print("── server: running on \(server.baseURL.absoluteString) after \(String(format: "%.1f", waited))s")

    // Measured-truth fields (Inspector honesty): /props n_ctx, offloaded
    // layers from logs, process footprint sampling.
    try? await Task.sleep(nanoseconds: 4_500_000_000)   // one footprint sample tick
    guard server.actualContextTokens == settings.contextSize else {
        server.stop()
        fail("actualContextTokens \(server.actualContextTokens.map(String.init) ?? "nil") != requested \(settings.contextSize)")
    }
    print("── measured: n_ctx=\(server.actualContextTokens!) " +
          "gpuLayers=\(server.actualGpuLayers ?? "?") " +
          "footprint=\(server.memoryFootprint.map { String(format: "%.2f GB", Double($0) / 1_073_741_824) } ?? "nil")")
    guard let footprint = server.memoryFootprint, footprint > 10_000_000 else {
        server.stop()
        fail("memory footprint not sampled")
    }

    // 4. Stream a chat completion
    let client = ChatClient(baseURL: server.baseURL)
    var reply = ""
    var metrics: ChatMetrics?
    do {
        for try await event in client.stream(
            messages: [ChatTurn(role: "user", content: "Reply with exactly: hello from llamaboard")],
            settings: settings
        ) {
            switch event {
            case .delta(let text): reply += text
            case .finished(let m): metrics = m
            }
        }
    } catch {
        server.stop()
        fail("chat stream error: \(error)")
    }

    guard let metrics, !reply.isEmpty else {
        server.stop()
        fail("empty reply from model")
    }
    print("── reply: \(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))")
    print(String(format: "── metrics: %d tokens, %.1f t/s, %.2fs TTFT", metrics.tokens, metrics.tokensPerSec, metrics.ttft))
    server.recordChatMetrics(tokensPerSec: metrics.tokensPerSec)

    // 5. Stop
    server.stop()
    guard server.state == .stopped else { fail("server did not stop cleanly") }
    print("── server stopped cleanly")
    print("SMOKE PASS")
    exit(0)
}

Task { @MainActor in
    await run()
}
RunLoop.main.run()
