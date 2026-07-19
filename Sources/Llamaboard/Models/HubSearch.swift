import Foundation
import LlamaboardKit

/// Drives Hugging Face model search for the Discover screen.
///
/// The hub allows 500 requests per 5 minutes, so keystrokes are debounced and
/// every (query, sort) pair is cached for the session — retyping or flipping
/// back to a previous search costs nothing.
@MainActor
final class HubSearch: ObservableObject {
    @Published private(set) var results: [HFSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    @Published var sort: HFSortOrder = .trending {
        didSet { guard sort != oldValue else { return }; run(query: lastQuery, immediate: true) }
    }

    private var cache: [String: [HFSearchResult]] = [:]
    private var searchTask: Task<Void, Never>?
    private var lastQuery = ""
    private let debounce = Duration.milliseconds(350)

    private func cacheKey(_ query: String, _ sort: HFSortOrder) -> String {
        "\(sort.rawValue)|\(query.trimmingCharacters(in: .whitespaces).lowercased())"
    }

    /// Search after a short pause in typing. `immediate` skips the debounce
    /// (used for sort changes and the initial load).
    func run(query: String, immediate: Bool = false) {
        lastQuery = query
        searchTask?.cancel()

        let key = cacheKey(query, sort)
        if let cached = cache[key] {
            results = cached
            errorMessage = nil
            isSearching = false
            return
        }

        searchTask = Task {
            if !immediate {
                try? await Task.sleep(for: debounce)
                if Task.isCancelled { return }
            }
            isSearching = true
            errorMessage = nil
            defer { isSearching = false }
            do {
                let found = try await HFHub.search(query: query, sort: sort)
                if Task.isCancelled { return }
                cache[key] = found
                results = found
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                results = []
                errorMessage = "\(error)"
            }
        }
    }

    /// Load the default listing the first time Discover is opened.
    func loadIfNeeded() {
        guard results.isEmpty, !isSearching, errorMessage == nil else { return }
        run(query: "", immediate: true)
    }
}
