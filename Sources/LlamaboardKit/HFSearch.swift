import Foundation

/// One repository returned by a Hugging Face model search.
public struct HFSearchResult: Identifiable, Sendable, Equatable {
    public var id: String { repo }
    public let repo: String            // "owner/name"
    public let author: String
    public let downloads: Int
    public let likes: Int
    public let gated: Bool             // license acceptance required before download
    public let pipelineTag: String?    // e.g. "text-generation", "feature-extraction"
    public let lastModified: Date?
    public let ggufFiles: [String]     // GGUF filenames in the repo

    public init(repo: String, author: String, downloads: Int, likes: Int, gated: Bool,
                pipelineTag: String?, lastModified: Date?, ggufFiles: [String]) {
        self.repo = repo
        self.author = author
        self.downloads = downloads
        self.likes = likes
        self.gated = gated
        self.pipelineTag = pipelineTag
        self.lastModified = lastModified
        self.ggufFiles = ggufFiles
    }

    /// Repository name without the owner prefix.
    public var name: String {
        repo.split(separator: "/").last.map(String.init) ?? repo
    }

    /// Quantizations available in the repo, derived from the filenames
    /// (e.g. ["Q4_K_M", "Q8_0"]).
    public var quantTags: [String] {
        var found: [String] = []
        for file in ggufFiles {
            if let tag = HFHub.quantTag(fromFileName: file), !found.contains(tag) {
                found.append(tag)
            }
        }
        return found.sorted()
    }

    /// True when every GGUF in the repo is a split multi-part file, which
    /// Llamaboard can't download yet.
    public var isSplitOnly: Bool {
        !ggufFiles.isEmpty && ggufFiles.allSatisfy {
            $0.range(of: #"-\d{5}-of-\d{5}"#, options: .regularExpression) != nil
        }
    }

    /// Chat-capable models are the common case; flag the others so users don't
    /// download an embedding model expecting a conversation.
    public var isLikelyChatModel: Bool {
        guard let tag = pipelineTag else { return true }
        return tag == "text-generation" || tag == "text2text-generation"
    }
}

/// Sort orders supported by the hub's model listing.
public enum HFSortOrder: String, CaseIterable, Sendable, Identifiable {
    case trending, downloads, likes, recent
    public var id: String { rawValue }

    /// The API's `sort` parameter value.
    public var apiValue: String {
        switch self {
        case .trending: return "trendingScore"
        case .downloads: return "downloads"
        case .likes: return "likes"
        case .recent: return "lastModified"
        }
    }

    public var label: String {
        switch self {
        case .trending: return "Trending"
        case .downloads: return "Downloads"
        case .likes: return "Likes"
        case .recent: return "Recent"
        }
    }
}

public enum HFSearchError: Error, CustomStringConvertible {
    case rateLimited
    case http(Int)
    case malformedResponse

    public var description: String {
        switch self {
        case .rateLimited:
            return "Hugging Face rate limit reached. Wait a moment and try again."
        case .http(let code):
            return "Hugging Face returned HTTP \(code)."
        case .malformedResponse:
            return "Couldn't read the response from Hugging Face."
        }
    }
}

extension HFHub {

    /// Search the hub for GGUF repositories.
    ///
    /// A single request with `full=true` returns the metadata *and* the file
    /// list, so results can be rendered — and quantizations listed — without a
    /// follow-up call per repo.
    public static func search(query: String,
                              sort: HFSortOrder = .trending,
                              limit: Int = 30) async throws -> [HFSearchResult] {
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        var items = [
            URLQueryItem(name: "filter", value: "gguf"),
            URLQueryItem(name: "sort", value: sort.apiValue),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "full", value: "true"),
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items.append(URLQueryItem(name: "search", value: trimmed))
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 429 ? HFSearchError.rateLimited : HFSearchError.http(http.statusCode)
        }
        return try parseSearchResults(data)
    }

    /// Decode a hub search payload. Pure and side-effect free so it can be
    /// tested against captured fixtures.
    public static func parseSearchResults(_ data: Data) throws -> [HFSearchResult] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw HFSearchError.malformedResponse
        }
        return array.compactMap { entry -> HFSearchResult? in
            guard let repo = entry["id"] as? String else { return nil }
            let files = (entry["siblings"] as? [[String: Any]] ?? [])
                .compactMap { $0["rfilename"] as? String }
                .filter { $0.lowercased().hasSuffix(".gguf") }
            // Repos can match the gguf filter without shipping one (e.g. a
            // base model referenced by a quantized fork) — skip those.
            guard !files.isEmpty else { return nil }

            return HFSearchResult(
                repo: repo,
                author: entry["author"] as? String
                    ?? repo.split(separator: "/").first.map(String.init) ?? "",
                downloads: entry["downloads"] as? Int ?? 0,
                likes: entry["likes"] as? Int ?? 0,
                // `gated` is false, "auto", or "manual".
                gated: {
                    if let flag = entry["gated"] as? Bool { return flag }
                    if let mode = entry["gated"] as? String { return mode != "false" }
                    return false
                }(),
                pipelineTag: entry["pipeline_tag"] as? String,
                lastModified: (entry["lastModified"] as? String).flatMap(parseISODate),
                ggufFiles: files)
        }
    }

    /// One downloadable GGUF in a repository, with the size the hub reports.
    public struct QuantFile: Identifiable, Sendable, Equatable {
        public var id: String { fileName }
        public let fileName: String      // path within the repo
        public let quant: String?        // detected tag, e.g. "Q4_K_M"
        public let sizeBytes: Int64
        public let isSplit: Bool

        public init(fileName: String, quant: String?, sizeBytes: Int64, isSplit: Bool) {
            self.fileName = fileName
            self.quant = quant
            self.sizeBytes = sizeBytes
            self.isSplit = isSplit
        }

        /// Label for the picker: the quant tag when known, else the file name.
        public var label: String {
            quant ?? (fileName as NSString).lastPathComponent
        }
    }

    /// List every GGUF in a repo with its exact size.
    ///
    /// `?blobs=true` returns sizes for all files in a single request, so the
    /// picker needs no per-file HEAD requests.
    public static func quantFiles(repo: String) async throws -> [QuantFile] {
        let url = URL(string: "https://huggingface.co/api/models/\(repo)?blobs=true")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 429 ? HFSearchError.rateLimited : HFSearchError.http(http.statusCode)
        }
        return try parseQuantFiles(data)
    }

    /// Extract the quantization token from a GGUF filename.
    ///
    /// Read from the filename rather than matched against llama.cpp's ftype
    /// list, because repos publish variants that list doesn't contain —
    /// ARM-tuned `Q4_0_4_4`, "large embedding" `Q2_K_L`, `Q3_K_XL` and so on.
    /// Matching the known list alone would label all four `Q4_0_*` files
    /// identically.
    public static func quantTag(fromFileName name: String) -> String? {
        let stem = ((name as NSString).lastPathComponent as NSString).deletingPathExtension
        let pattern = #"(?:^|[-_.])(IQ\d+(?:_[A-Z0-9]+)*|Q\d+(?:_[A-Z0-9]+)*|BF16|F16|F32)(?:$|[-_.])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(stem.startIndex..., in: stem)
        // Take the last match: the quant sits at the end of conventional names.
        guard let match = regex.matches(in: stem, range: range).last,
              let tokenRange = Range(match.range(at: 1), in: stem) else { return nil }
        return String(stem[tokenRange]).uppercased()
    }

    /// Decode a `?blobs=true` payload into sized quantization entries.
    /// Pure, so it can be tested against a captured response.
    public static func parseQuantFiles(_ data: Data) throws -> [QuantFile] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let siblings = json["siblings"] as? [[String: Any]] else {
            throw HFSearchError.malformedResponse
        }
        return siblings.compactMap { entry -> QuantFile? in
            guard let name = entry["rfilename"] as? String,
                  name.lowercased().hasSuffix(".gguf") else { return nil }
            let size = (entry["size"] as? NSNumber)?.int64Value ?? 0
            let isSplit = name.range(of: #"-\d{5}-of-\d{5}"#, options: .regularExpression) != nil
            return QuantFile(fileName: name, quant: quantTag(fromFileName: name),
                             sizeBytes: size, isSplit: isSplit)
        }
        // Split archives list every shard; keep only the first so the picker
        // shows one row per model rather than N confusing parts.
        .filter { !$0.isSplit || $0.fileName.contains("-00001-of-") }
        .sorted { $0.sizeBytes < $1.sizeBytes }
    }

    static func parseISODate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}
