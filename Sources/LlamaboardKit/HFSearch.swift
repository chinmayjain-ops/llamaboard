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

    /// Quantizations available in the repo, ordered smallest-first by name,
    /// derived from the filenames (e.g. ["Q4_K_M", "Q8_0"]).
    public var quantTags: [String] {
        let known = Set(GGUFReader.fileTypeNames.values)
        var found: [String] = []
        for file in ggufFiles {
            let upper = file.uppercased()
            // Longest names first so Q4_K_M wins over Q4_K.
            for quant in known.sorted(by: { $0.count > $1.count })
            where upper.contains(quant) && !found.contains(quant) {
                found.append(quant)
                break
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

    static func parseISODate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}
