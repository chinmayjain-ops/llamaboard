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

    /// Estimated RAM requirement string for display, e.g. "~6.8 GB".
    public static func estimatedRAM(fileSize: UInt64, metadata: GGUFMetadata?, contextTokens: UInt64) -> String {
        let kv = metadata.map { kvCacheBytes(metadata: $0, contextTokens: contextTokens) }
            ?? contextTokens * 131_072
        let bytes = Double((fileSize + kv) * 115 / 100)
        return String(format: "~%.1f GB", bytes / 1_073_741_824)
    }
}
