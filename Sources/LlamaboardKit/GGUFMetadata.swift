import Foundation

/// Metadata extracted from a GGUF file's header — read directly from the key/value
/// section and tensor table without loading tensor data (PRD LIB-3).
public struct GGUFMetadata: Sendable, Equatable {
    public let version: UInt32
    public let architecture: String?
    public let modelName: String?
    public let sizeLabel: String?          // e.g. "8B", from general.size_label
    public let quantName: String?          // e.g. "Q4_K_M", from general.file_type
    public let contextLength: UInt64?      // {arch}.context_length
    public let blockCount: UInt64?         // {arch}.block_count (layer count)
    public let embeddingLength: UInt64?
    public let headCount: UInt64?
    public let headCountKV: UInt64?
    public let chatTemplate: String?
    public let parameterCount: UInt64      // sum of tensor element counts
    public let tensorCount: UInt64

    /// Human label like "135M" / "7.2B" derived from the tensor table when
    /// general.size_label is absent.
    public var parameterLabel: String {
        if let sizeLabel, !sizeLabel.isEmpty { return sizeLabel }
        let p = Double(parameterCount)
        if p >= 1e9 { return String(format: "%.1fB", p / 1e9) }
        if p >= 1e6 { return String(format: "%.0fM", p / 1e6) }
        return "\(parameterCount)"
    }
}

public enum GGUFError: Error, CustomStringConvertible {
    case notGGUF
    case unsupportedVersion(UInt32)
    case truncated(String)

    public var description: String {
        switch self {
        case .notGGUF: return "Not a GGUF file (bad magic)"
        case .unsupportedVersion(let v): return "Unsupported GGUF version \(v)"
        case .truncated(let what): return "Truncated GGUF header while reading \(what)"
        }
    }
}

/// Sequential little-endian reader over a file's leading bytes.
/// GGUF headers (including tokenizer vocab arrays) are typically well under
/// 64 MB; we read lazily in chunks so small headers stay cheap.
private final class HeaderReader {
    private let handle: FileHandle
    private var buffer = Data()
    private var offset = 0
    private let chunkSize = 4 << 20

    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
    }
    deinit { try? handle.close() }

    private func ensure(_ count: Int, context: String) throws {
        while buffer.count - offset < count {
            guard let more = try handle.read(upToCount: chunkSize), !more.isEmpty else {
                throw GGUFError.truncated(context)
            }
            // Compact consumed prefix occasionally to bound memory.
            if offset > (32 << 20) {
                buffer.removeSubrange(0..<offset)
                offset = 0
            }
            buffer.append(more)
        }
    }

    func bytes(_ count: Int, context: String) throws -> Data {
        try ensure(count, context: context)
        defer { offset += count }
        return buffer.subdata(in: offset..<(offset + count))
    }

    func skip(_ count: Int, context: String) throws {
        try ensure(count, context: context)
        offset += count
    }

    func u32(_ context: String) throws -> UInt32 {
        try bytes(4, context: context).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }
    func u64(_ context: String) throws -> UInt64 {
        try bytes(8, context: context).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
    }
    func string(_ context: String) throws -> String {
        let len = Int(try u64(context))
        let data = try bytes(len, context: context)
        return String(decoding: data, as: UTF8.self)
    }
}

public enum GGUFReader {

    /// llama.cpp `llama_ftype` → quantization display name.
    static let fileTypeNames: [UInt32: String] = [
        0: "F32", 1: "F16", 2: "Q4_0", 3: "Q4_1", 7: "Q8_0", 8: "Q5_0", 9: "Q5_1",
        10: "Q2_K", 11: "Q3_K_S", 12: "Q3_K_M", 13: "Q3_K_L", 14: "Q4_K_S", 15: "Q4_K_M",
        16: "Q5_K_S", 17: "Q5_K_M", 18: "Q6_K", 19: "IQ2_XXS", 20: "IQ2_XS", 21: "Q2_K_S",
        22: "IQ3_XS", 23: "IQ3_XXS", 24: "IQ1_S", 25: "IQ4_NL", 26: "IQ3_S", 27: "IQ3_M",
        28: "IQ2_S", 29: "IQ2_M", 30: "IQ4_XS", 31: "IQ1_M", 32: "BF16"
    ]

    /// GGUF metadata value type tags.
    private enum ValueType: UInt32 {
        case uint8 = 0, int8 = 1, uint16 = 2, int16 = 3, uint32 = 4, int32 = 5
        case float32 = 6, bool = 7, string = 8, array = 9
        case uint64 = 10, int64 = 11, float64 = 12
    }

    /// KV values we care about. Everything else is skipped without allocation.
    private enum Value {
        case number(UInt64)
        case text(String)
        case skipped
    }

    public static func read(url: URL) throws -> GGUFMetadata {
        let reader = try HeaderReader(url: url)

        let magic = try reader.bytes(4, context: "magic")
        guard magic == Data("GGUF".utf8) else { throw GGUFError.notGGUF }
        let version = try reader.u32("version")
        guard (1...3).contains(version) else { throw GGUFError.unsupportedVersion(version) }

        let tensorCount = try reader.u64("tensor count")
        let kvCount = try reader.u64("kv count")

        var kv: [String: Value] = [:]
        // Keys are interesting if we might use them; arch-specific keys are matched
        // by suffix since we may not know the architecture until we've read it.
        func isInteresting(_ key: String) -> Bool {
            key.hasPrefix("general.") ||
            key.hasSuffix(".context_length") || key.hasSuffix(".block_count") ||
            key.hasSuffix(".embedding_length") ||
            key.hasSuffix(".attention.head_count") || key.hasSuffix(".attention.head_count_kv") ||
            key == "tokenizer.chat_template"
        }

        for _ in 0..<kvCount {
            let key = try reader.string("kv key")
            let typeRaw = try reader.u32("kv type")
            guard let type = ValueType(rawValue: typeRaw) else {
                throw GGUFError.truncated("unknown value type \(typeRaw) for \(key)")
            }
            let keep = isInteresting(key)
            let value = try readValue(reader, type: type, keep: keep, context: key)
            if keep { kv[key] = value }
        }

        // Tensor table: name, n_dims, dims, type, offset. Summing dim products
        // gives the parameter count.
        var paramCount: UInt64 = 0
        for _ in 0..<tensorCount {
            _ = try reader.string("tensor name")
            let nDims = Int(try reader.u32("tensor n_dims"))
            var elements: UInt64 = 1
            for _ in 0..<nDims {
                elements = elements &* (try reader.u64("tensor dim"))
            }
            _ = try reader.u32("tensor type")
            _ = try reader.u64("tensor offset")
            paramCount &+= elements
        }

        func text(_ key: String) -> String? {
            if case .text(let s)? = kv[key] { return s }
            return nil
        }
        func number(_ key: String) -> UInt64? {
            if case .number(let n)? = kv[key] { return n }
            return nil
        }
        func archNumber(_ suffix: String, arch: String?) -> UInt64? {
            if let arch, let n = number("\(arch).\(suffix)") { return n }
            // Fallback: any key with the suffix
            for (k, v) in kv where k.hasSuffix(".\(suffix)") {
                if case .number(let n) = v { return n }
            }
            return nil
        }

        let arch = text("general.architecture")
        let fileType = number("general.file_type").map { UInt32($0) }

        return GGUFMetadata(
            version: version,
            architecture: arch,
            modelName: text("general.name"),
            sizeLabel: text("general.size_label"),
            quantName: fileType.flatMap { fileTypeNames[$0] },
            contextLength: archNumber("context_length", arch: arch),
            blockCount: archNumber("block_count", arch: arch),
            embeddingLength: archNumber("embedding_length", arch: arch),
            headCount: archNumber("attention.head_count", arch: arch),
            headCountKV: archNumber("attention.head_count_kv", arch: arch),
            chatTemplate: text("tokenizer.chat_template"),
            parameterCount: paramCount,
            tensorCount: tensorCount
        )
    }

    private static func readValue(_ r: HeaderReader, type: ValueType, keep: Bool, context: String) throws -> Value {
        switch type {
        case .uint8, .int8, .bool:
            let d = try r.bytes(1, context: context)
            return keep ? .number(UInt64(d[d.startIndex])) : .skipped
        case .uint16, .int16:
            let d = try r.bytes(2, context: context)
            return keep ? .number(UInt64(d.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) })) : .skipped
        case .uint32, .int32:
            let v = try r.u32(context)
            return keep ? .number(UInt64(v)) : .skipped
        case .float32:
            try r.skip(4, context: context); return .skipped
        case .uint64, .int64:
            let v = try r.u64(context)
            return keep ? .number(v) : .skipped
        case .float64:
            try r.skip(8, context: context); return .skipped
        case .string:
            if keep { return .text(try r.string(context)) }
            let len = Int(try r.u64(context))
            try r.skip(len, context: context)
            return .skipped
        case .array:
            let elemTypeRaw = try r.u32(context)
            guard let elemType = ValueType(rawValue: elemTypeRaw) else {
                throw GGUFError.truncated("unknown array element type \(elemTypeRaw) in \(context)")
            }
            let count = try r.u64(context)
            switch elemType {
            case .string, .array:
                for _ in 0..<count {
                    _ = try readValue(r, type: elemType, keep: false, context: context)
                }
            default:
                let width: Int
                switch elemType {
                case .uint8, .int8, .bool: width = 1
                case .uint16, .int16: width = 2
                case .uint32, .int32, .float32: width = 4
                default: width = 8
                }
                try r.skip(width * Int(count), context: context)
            }
            return .skipped
        }
    }
}
