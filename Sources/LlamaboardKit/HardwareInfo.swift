import Foundation

/// Unified-memory facts and the "fits check" heuristic (PRD LIB-2/LIB-8).
public enum HardwareInfo {

    /// Total unified memory in bytes.
    public static var totalMemory: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// Approximate budget Metal will let a process use — macOS allows roughly
    /// 70–75% of unified memory as the GPU working set on Apple Silicon.
    public static var gpuBudget: UInt64 {
        totalMemory * 3 / 4
    }

    public enum Fit: String, Sendable {
        case fits, tight, tooLarge
    }

    /// Rough KV-cache size for a context: 2 (K+V) × layers × kvHeads × headDim × 2 bytes (f16).
    public static func kvCacheBytes(metadata: GGUFMetadata?, contextTokens: UInt64) -> UInt64 {
        guard let metadata,
              let layers = metadata.blockCount,
              let embed = metadata.embeddingLength,
              let heads = metadata.headCount, heads > 0 else {
            // Fallback: ~0.125 MB per token (7B-class default)
            return contextTokens * 131_072
        }
        let kvHeads = metadata.headCountKV ?? heads
        let headDim = embed / heads
        return 2 * contextTokens * layers * kvHeads * headDim * 2
    }

    /// Fit verdict for a model file at a given context size.
    /// Working set ≈ model weights + KV cache + ~15% compute overhead.
    public static func fit(fileSize: UInt64, metadata: GGUFMetadata?, contextTokens: UInt64) -> Fit {
        let kv = metadata.map { kvCacheBytes(metadata: $0, contextTokens: contextTokens) }
            ?? contextTokens * 131_072
        let workingSet = (fileSize + kv) * 115 / 100
        let budget = gpuBudget
        if workingSet <= budget * 80 / 100 { return .fits }
        if workingSet <= budget { return .tight }
        return .tooLarge
    }

    /// Preference order when several quantizations fit, best-regarded first.
    /// Q4_K_M leads because it's the community's quality/size/speed sweet spot;
    /// inference is memory-bandwidth bound, so a bigger quant is also a slower
    /// one on the same machine.
    private static let quantPreference = [
        "Q4_K_M", "Q4_K_S", "Q5_K_M", "Q5_K_S", "Q6_K", "Q8_0",
        "Q4_0", "IQ4_XS", "Q3_K_L", "Q3_K_M", "IQ3_M", "Q3_K_S", "Q2_K",
    ]

    /// Pick the quantization to recommend for this machine.
    ///
    /// Rules, in order:
    /// 1. Ignore split archives and (unless nothing else exists) full-precision
    ///    files — rarely what someone running locally wants.
    /// 2. If even the largest option is small next to the memory budget, take
    ///    it: extra quality costs nothing on a model this size.
    /// 3. Otherwise take the best-regarded option that still fits comfortably.
    /// 4. If nothing fits, suggest the smallest so there's always an answer.
    ///
    /// This is a *pre-download* estimate: the true KV-cache size depends on
    /// GGUF metadata that can't be read until the file is on disk.
    public static func recommendedQuant(from files: [HFHub.QuantFile],
                                        contextTokens: UInt64) -> HFHub.QuantFile? {
        let usable = files.filter { !$0.isSplit && $0.sizeBytes > 0 }
        guard !usable.isEmpty else { return nil }

        let fullPrecision: Set<String> = ["F32", "F16", "BF16"]
        let quantized = usable.filter { file in
            guard let quant = file.quant else { return true }
            return !fullPrecision.contains(quant)
        }
        let candidates = quantized.isEmpty ? usable : quantized

        let comfortable = candidates.filter {
            fit(fileSize: UInt64($0.sizeBytes), metadata: nil, contextTokens: contextTokens) == .fits
        }
        guard !comfortable.isEmpty else {
            return candidates.min { $0.sizeBytes < $1.sizeBytes }
        }

        // Rule 2: everything is comfortably small — quality is effectively free.
        if let largest = comfortable.max(by: { $0.sizeBytes < $1.sizeBytes }),
           UInt64(largest.sizeBytes) < gpuBudget / 4 {
            return largest
        }

        // Rule 3: best-regarded quant that fits.
        for preferred in quantPreference {
            if let match = comfortable.first(where: { $0.quant == preferred }) {
                return match
            }
        }
        return comfortable.max { $0.sizeBytes < $1.sizeBytes }
    }

    /// Estimated RAM requirement string for display, e.g. "~6.8 GB".
    public static func estimatedRAM(fileSize: UInt64, metadata: GGUFMetadata?, contextTokens: UInt64) -> String {
        let kv = metadata.map { kvCacheBytes(metadata: $0, contextTokens: contextTokens) }
            ?? contextTokens * 131_072
        let bytes = Double((fileSize + kv) * 115 / 100)
        return String(format: "~%.1f GB", bytes / 1_073_741_824)
    }
}
