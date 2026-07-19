import Foundation
import LlamaboardKit

/// Assert-based unit tests for LlamaboardKit, run with `swift run llamaboard-tests`.
/// (An executable target because the swift-testing/XCTest modules aren't available
/// with Command Line Tools alone.)

nonisolated(unsafe) var failures = 0

func expect(_ condition: Bool, _ label: String,
            file: StaticString = #file, line: UInt = #line) {
    if condition {
        print("  ok  \(label)")
    } else {
        failures += 1
        print("FAIL  \(label)  (\(file):\(line))")
    }
}

func expectThrows(_ label: String, _ body: () throws -> Void) {
    do {
        try body()
        failures += 1
        print("FAIL  \(label): expected error, none thrown")
    } catch {
        print("  ok  \(label) → \(error)")
    }
}

/// Builds a minimal synthetic GGUF v3 file in memory for parser tests.
struct GGUFBuilder {
    var data = Data()

    init(tensorCount: UInt64, kvCount: UInt64) {
        data.append(Data("GGUF".utf8))
        append(UInt32(3))
        append(tensorCount)
        append(kvCount)
    }

    mutating func append<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    mutating func appendString(_ s: String) {
        append(UInt64(s.utf8.count))
        data.append(Data(s.utf8))
    }
    mutating func kvString(_ key: String, _ value: String) {
        appendString(key); append(UInt32(8)); appendString(value)
    }
    mutating func kvU32(_ key: String, _ value: UInt32) {
        appendString(key); append(UInt32(4)); append(value)
    }
    mutating func kvF32(_ key: String, _ value: Float) {
        appendString(key); append(UInt32(6))
        withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
    }
    mutating func kvStringArray(_ key: String, _ values: [String]) {
        appendString(key); append(UInt32(9))       // array
        append(UInt32(8))                          // of string
        append(UInt64(values.count))
        for v in values { appendString(v) }
    }
    mutating func tensor(_ name: String, dims: [UInt64]) {
        appendString(name)
        append(UInt32(dims.count))
        for d in dims { append(d) }
        append(UInt32(0))   // type F32
        append(UInt64(0))   // offset
    }

    func write() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gguf-test-\(UUID().uuidString).gguf")
        try data.write(to: url)
        return url
    }
}

// MARK: parsesTypicalHeader
do {
    var b = GGUFBuilder(tensorCount: 2, kvCount: 7)
    b.kvString("general.architecture", "llama")
    b.kvString("general.name", "Test Model")
    b.kvU32("general.file_type", 15)              // Q4_K_M
    b.kvU32("llama.context_length", 8192)
    b.kvU32("llama.block_count", 32)
    b.kvStringArray("tokenizer.ggml.tokens", ["<s>", "</s>", "hello"])  // must be skipped
    b.kvF32("llama.rope.freq_base", 10000.0)      // skipped float
    b.tensor("blk.0.attn_q.weight", dims: [4096, 4096])
    b.tensor("output.weight", dims: [4096, 32000])
    let url = try b.write()
    defer { try? FileManager.default.removeItem(at: url) }

    let meta = try GGUFReader.read(url: url)
    expect(meta.version == 3, "version parsed")
    expect(meta.architecture == "llama", "architecture parsed")
    expect(meta.modelName == "Test Model", "name parsed")
    expect(meta.quantName == "Q4_K_M", "file_type → quant name")
    expect(meta.contextLength == 8192, "context length parsed")
    expect(meta.blockCount == 32, "block count parsed")
    expect(meta.parameterCount == UInt64(4096) * 4096 + UInt64(4096) * 32000, "parameter count from tensor table")
    expect(meta.parameterLabel == "148M", "parameter label derived")
} catch {
    failures += 1
    print("FAIL  parsesTypicalHeader threw: \(error)")
}

// MARK: rejectsNonGGUF
do {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("not-gguf-\(UUID().uuidString).gguf")
    try Data("PK\u{03}\u{04}zipfile".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    expectThrows("non-GGUF rejected") { _ = try GGUFReader.read(url: url) }
} catch {
    failures += 1
    print("FAIL  rejectsNonGGUF setup threw: \(error)")
}

// MARK: rejectsTruncated
do {
    var b = GGUFBuilder(tensorCount: 0, kvCount: 3)   // claims 3 KVs, provides 1
    b.kvString("general.architecture", "llama")
    let url = try b.write()
    defer { try? FileManager.default.removeItem(at: url) }
    expectThrows("truncated header rejected") { _ = try GGUFReader.read(url: url) }
} catch {
    failures += 1
    print("FAIL  rejectsTruncated setup threw: \(error)")
}

// MARK: quant fallback from filename
expect(LibraryModel.quantFromName("Meta-Llama-3-8B-Instruct.Q4_K_M.gguf") == "Q4_K_M", "quant from filename Q4_K_M")
expect(LibraryModel.quantFromName("mistral-7b-q8_0.gguf") == "Q8_0", "quant from filename q8_0")
expect(LibraryModel.quantFromName("plain-model.gguf") == nil, "no quant in plain filename")

// MARK: server arguments reflect settings
do {
    var s = ModelSettings()
    s.contextSize = 8192
    s.port = 9999
    s.flashAttention = true
    s.kvCacheTypeK = "q8_0"
    s.extraArgs = "--verbose"
    let args = s.serverArguments(modelPath: "/tmp/m.gguf")
    expect(args.firstIndex(of: "--ctx-size").map { args[$0 + 1] } == "8192", "ctx-size flag")
    expect(args.firstIndex(of: "--port").map { args[$0 + 1] } == "9999", "port flag")
    expect(args.contains("--cache-type-k"), "kv cache type flag")
    expect(args.last == "--verbose", "extra args appended")
}

// MARK: fit heuristic ordering
expect(HardwareInfo.fit(fileSize: 100 << 20, metadata: nil, contextTokens: 2048) == .fits, "tiny model fits")
expect(HardwareInfo.fit(fileSize: HardwareInfo.totalMemory * 2, metadata: nil, contextTokens: 2048) == .tooLarge, "oversize model too large")

// MARK: settings store round-trip
do {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lb-profiles-\(UUID().uuidString)")
    let store = SettingsStore(directory: dir)
    var s = ModelSettings()
    s.temperature = 1.25
    s.contextSize = 16384
    try store.save(s, for: "my-model.Q4_K_M.gguf")
    let loaded = store.load(for: "my-model.Q4_K_M.gguf")
    expect(loaded == s, "settings JSON round-trip")
    expect(store.load(for: "unknown.gguf") == ModelSettings(), "missing profile → defaults")
    try? FileManager.default.removeItem(at: dir)
} catch {
    failures += 1
    print("FAIL  settings store threw: \(error)")
}

// MARK: HF search parsing (fixture mirrors a real /api/models?full=true payload)
do {
    let fixture = """
    [
      {
        "id": "bartowski/SmolLM2-135M-Instruct-GGUF",
        "author": "bartowski",
        "downloads": 12345,
        "likes": 67,
        "gated": false,
        "pipeline_tag": "text-generation",
        "lastModified": "2025-01-02T11:59:48.000Z",
        "siblings": [
          {"rfilename": "README.md"},
          {"rfilename": "SmolLM2-135M-Instruct-Q4_K_M.gguf"},
          {"rfilename": "SmolLM2-135M-Instruct-Q8_0.gguf"}
        ]
      },
      {
        "id": "meta-llama/Llama-3.2-1B-Instruct",
        "author": "meta-llama",
        "downloads": 999,
        "likes": 10,
        "gated": "manual",
        "pipeline_tag": "text-generation",
        "lastModified": "2025-06-01T00:00:00.000Z",
        "siblings": [{"rfilename": "model-Q4_K_M.gguf"}]
      },
      {
        "id": "someone/embeddings-only",
        "author": "someone",
        "downloads": 5,
        "likes": 0,
        "gated": false,
        "pipeline_tag": "feature-extraction",
        "siblings": [{"rfilename": "big-BF16-00001-of-00002.gguf"}, {"rfilename": "big-BF16-00002-of-00002.gguf"}]
      },
      {
        "id": "someone/no-gguf-here",
        "author": "someone",
        "downloads": 1,
        "likes": 0,
        "siblings": [{"rfilename": "config.json"}]
      }
    ]
    """
    let results = try HFHub.parseSearchResults(Data(fixture.utf8))
    expect(results.count == 3, "search: repos without a GGUF are dropped")

    let first = results[0]
    expect(first.repo == "bartowski/SmolLM2-135M-Instruct-GGUF", "search: repo id parsed")
    expect(first.name == "SmolLM2-135M-Instruct-GGUF", "search: name strips owner")
    expect(first.author == "bartowski", "search: author parsed")
    expect(first.downloads == 12345 && first.likes == 67, "search: counts parsed")
    expect(first.gated == false, "search: boolean gated parsed")
    expect(first.quantTags == ["Q4_K_M", "Q8_0"], "search: quant tags derived from filenames")
    expect(first.isSplitOnly == false, "search: non-split repo detected")
    expect(first.isLikelyChatModel, "search: text-generation is a chat model")
    expect(first.lastModified != nil, "search: fractional-seconds date parsed")

    expect(results[1].gated == true, "search: string gated (\"manual\") treated as gated")
    expect(results[2].isSplitOnly, "search: split-only repo detected")
    expect(results[2].isLikelyChatModel == false, "search: feature-extraction flagged as non-chat")
} catch {
    failures += 1
    print("FAIL  search parsing threw: \(error)")
}

expect(HFSortOrder.trending.apiValue == "trendingScore", "search: trending maps to trendingScore")
expect(HFSortOrder.recent.apiValue == "lastModified", "search: recent maps to lastModified")
expectThrows("search: malformed payload rejected") {
    _ = try HFHub.parseSearchResults(Data("not json".utf8))
}

// MARK: Quant tag extraction from filenames
expect(HFHub.quantTag(fromFileName: "Model-Q4_K_M.gguf") == "Q4_K_M", "quant tag: standard")
expect(HFHub.quantTag(fromFileName: "SmolLM2-135M-Instruct-Q8_0.gguf") == "Q8_0",
       "quant tag: model name digits ignored")
expect(HFHub.quantTag(fromFileName: "Model-Q4_0_4_4.gguf") == "Q4_0_4_4",
       "quant tag: ARM variant kept distinct from Q4_0")
expect(HFHub.quantTag(fromFileName: "Model-Q2_K_L.gguf") == "Q2_K_L",
       "quant tag: _L variant not collapsed to Q2_K")
expect(HFHub.quantTag(fromFileName: "Model-Q3_K_XL.gguf") == "Q3_K_XL",
       "quant tag: variant outside llama.cpp's ftype list")
expect(HFHub.quantTag(fromFileName: "Model-IQ3_XXS.gguf") == "IQ3_XXS", "quant tag: IQ family")
expect(HFHub.quantTag(fromFileName: "BF16/Model-BF16-00001-of-00002.gguf") == "BF16",
       "quant tag: split file in a subfolder")
expect(HFHub.quantTag(fromFileName: "Qwen3-model.gguf") == nil,
       "quant tag: 'Qwen3' is not mistaken for a quant")
expect(HFHub.quantTag(fromFileName: "plain-model.gguf") == nil, "quant tag: none present")

// MARK: Quantization file listing (?blobs=true payload)
do {
    let fixture = """
    {
      "id": "acme/Model-GGUF",
      "siblings": [
        {"rfilename": "README.md", "size": 1000},
        {"rfilename": "Model-Q4_K_M.gguf", "size": 4370000000},
        {"rfilename": "Model-Q8_0.gguf", "size": 7700000000},
        {"rfilename": "Model-Q2_K.gguf", "size": 1200000000},
        {"rfilename": "Model-F16.gguf", "size": 15000000000},
        {"rfilename": "BF16/Model-BF16-00001-of-00002.gguf", "size": 46000000000},
        {"rfilename": "BF16/Model-BF16-00002-of-00002.gguf", "size": 3500000000}
      ]
    }
    """
    let files = try HFHub.parseQuantFiles(Data(fixture.utf8))
    expect(files.count == 5, "quants: non-GGUF skipped and split shards collapsed to one entry")
    expect(files.map(\.sizeBytes) == files.map(\.sizeBytes).sorted(), "quants: sorted smallest first")
    expect(files.first?.quant == "Q2_K", "quants: smallest is Q2_K")
    expect(files.first(where: { $0.quant == "Q4_K_M" })?.sizeBytes == 4_370_000_000, "quants: size parsed")
    expect(files.contains { $0.isSplit }, "quants: split file retained but flagged")
    expect(files.filter { $0.isSplit }.count == 1, "quants: only the first shard is listed")
    expect(files.first(where: { $0.isSplit })?.fileName.contains("-00001-of-") == true,
           "quants: the retained shard is the first one")

    let pick = HardwareInfo.recommendedQuant(from: files, contextTokens: 4096)
    expect(pick != nil, "quants: a recommendation is always produced")
    expect(pick?.isSplit == false, "quants: never recommends a split file")
    expect(pick?.quant != "F16", "quants: prefers a quantized file over full precision")

    // With a large model relative to the budget, the sweet-spot quant wins
    // over merely "the biggest that fits" — bigger quants are also slower.
    let bigModel = [
        HFHub.QuantFile(fileName: "M-Q4_K_M.gguf", quant: "Q4_K_M",
                        sizeBytes: Int64(HardwareInfo.gpuBudget / 3), isSplit: false),
        HFHub.QuantFile(fileName: "M-Q5_K_M.gguf", quant: "Q5_K_M",
                        sizeBytes: Int64(Double(HardwareInfo.gpuBudget) * 0.42), isSplit: false),
    ]
    expect(HardwareInfo.recommendedQuant(from: bigModel, contextTokens: 4096)?.quant == "Q4_K_M",
           "quants: prefers Q4_K_M over a larger quant on a sizeable model")

    // Nothing fits: still suggest the smallest rather than nothing.
    let oversized = [
        HFHub.QuantFile(fileName: "H-Q4_K_M.gguf", quant: "Q4_K_M",
                        sizeBytes: Int64(HardwareInfo.totalMemory * 2), isSplit: false),
        HFHub.QuantFile(fileName: "H-Q2_K.gguf", quant: "Q2_K",
                        sizeBytes: Int64(HardwareInfo.totalMemory * 3 / 2), isSplit: false),
    ]
    expect(HardwareInfo.recommendedQuant(from: oversized, contextTokens: 4096)?.quant == "Q2_K",
           "quants: falls back to the smallest when nothing fits")

    // With only full-precision options available, one is still recommended.
    let f16Only = files.filter { $0.quant == "F16" }
    expect(HardwareInfo.recommendedQuant(from: f16Only, contextTokens: 4096)?.quant == "F16",
           "quants: falls back to full precision when nothing else exists")
    expect(HardwareInfo.recommendedQuant(from: [], contextTokens: 4096) == nil,
           "quants: empty list yields no recommendation")
} catch {
    failures += 1
    print("FAIL  quant file parsing threw: \(error)")
}

expectThrows("quants: malformed payload rejected") {
    _ = try HFHub.parseQuantFiles(Data("[]".utf8))
}

// MARK: HF command parsing
expect(HFCommandParser.parse("llama serve -hf GnLOLot/MiniCPM5-1B-Claude-Opus-Fable5-Thinking-GGUF:Q4_K_M")
       == HFModelRef(repo: "GnLOLot/MiniCPM5-1B-Claude-Opus-Fable5-Thinking-GGUF", quant: "Q4_K_M"),
       "hf: llama serve command with quant")
expect(HFCommandParser.parse("llama-server -hf bartowski/SmolLM2-135M-Instruct-GGUF")
       == HFModelRef(repo: "bartowski/SmolLM2-135M-Instruct-GGUF", quant: nil),
       "hf: llama-server command without quant")
expect(HFCommandParser.parse("llama cli -hf owner/repo:Q8_0 --extra --flags")
       == HFModelRef(repo: "owner/repo", quant: "Q8_0"),
       "hf: llama cli with trailing flags")
expect(HFCommandParser.parse("owner/repo:Q5_K_M")
       == HFModelRef(repo: "owner/repo", quant: "Q5_K_M"),
       "hf: bare ref with quant")
expect(HFCommandParser.parse("https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/tree/main")
       == HFModelRef(repo: "bartowski/SmolLM2-135M-Instruct-GGUF", quant: nil),
       "hf: huggingface.co URL")
expect(HFCommandParser.parse("just some random text") == nil, "hf: garbage rejected")
expect(HFCommandParser.parse("") == nil, "hf: empty rejected")

// MARK: GPU offload log parsing
expect(ServerManager.parseOffloadedLayers("load_tensors: offloaded 48/49 layers to GPU") == "48/49",
       "offload: parses partial offload")
expect(ServerManager.parseOffloadedLayers("llm_load_tensors: offloaded 31/31 layers to GPU") == "31/31",
       "offload: parses full offload")
expect(ServerManager.parseOffloadedLayers("srv log: some unrelated line") == nil,
       "offload: ignores unrelated lines")

// MARK: Hermes config rewriting
do {
    let sample = """
    model:
      default: anthropic/claude-opus-4.6
      provider: auto
      base_url: https://openrouter.ai/api/v1
    agent:
      max_turns: 60
      personalities:
        helpful: You are a helpful, friendly AI assistant.
    _config_version: 33
    """
    let out = HermesIntegration.rewriteConfig(sample, baseURL: "http://127.0.0.1:8080/v1", model: "SmolLM2-135M")
    expect(out.contains("  default: SmolLM2-135M"), "hermes: default model replaced")
    expect(out.contains("  provider: custom"), "hermes: provider set to custom")
    expect(out.contains("  base_url: http://127.0.0.1:8080/v1"), "hermes: base_url replaced")
    expect(out.contains("  api_key: llamaboard"), "hermes: api_key inserted")
    expect(!out.contains("openrouter.ai"), "hermes: old base_url gone")
    expect(out.contains("max_turns: 60") && out.contains("helpful: You are a helpful"), "hermes: other blocks preserved")
    expect(out.contains("_config_version: 33"), "hermes: trailing top-level key preserved")

    // Idempotent: rewriting the rewritten config changes nothing.
    let again = HermesIntegration.rewriteConfig(out, baseURL: "http://127.0.0.1:8080/v1", model: "SmolLM2-135M")
    expect(again == out, "hermes: rewrite is idempotent")

    // Missing model block: one gets prepended.
    let noBlock = HermesIntegration.rewriteConfig("agent:\n  max_turns: 3", baseURL: "http://x/v1", model: "m")
    expect(noBlock.hasPrefix("model:\n"), "hermes: model block created when absent")
}

// Read-only check against the real ~/.hermes/config.yaml when present.
if let real = try? String(contentsOf: HermesIntegration.configURL, encoding: .utf8) {
    let out = HermesIntegration.rewriteConfig(real, baseURL: "http://127.0.0.1:8080/v1", model: "test-model")
    expect(out.contains("  provider: custom") && out.contains("  base_url: http://127.0.0.1:8080/v1"),
           "hermes: real config rewrites cleanly")
    let originalLines = real.components(separatedBy: "\n").count
    let newLines = out.components(separatedBy: "\n").count
    expect(abs(newLines - originalLines) <= 4, "hermes: real config structure preserved (±insert lines)")
}

print(failures == 0 ? "\nALL TESTS PASSED" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
