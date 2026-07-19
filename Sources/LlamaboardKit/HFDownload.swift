import Foundation

// MARK: - Parsing pasted input

/// A reference to a GGUF model on the Hugging Face hub.
public struct HFModelRef: Equatable, Sendable {
    public let repo: String     // "owner/name"
    public let quant: String?   // e.g. "Q4_K_M" (nil = llama.cpp default)

    public init(repo: String, quant: String?) {
        self.repo = repo
        self.quant = quant
    }
}

public enum HFCommandParser {
    /// Accepts what users actually paste from a HF model page:
    ///   llama serve -hf owner/repo:Q4_K_M      (llama.cpp "Use this model" dialog)
    ///   llama-server -hf owner/repo            (real binary names too)
    ///   llama cli -hf owner/repo:Q8_0
    ///   owner/repo:Q4_K_M                      (bare reference)
    ///   https://huggingface.co/owner/repo      (page URL, any sub-path)
    public static func parse(_ input: String) -> HFModelRef? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // 1. `-hf <ref>` anywhere in a command line
        if let range = text.range(of: #"-hf\s+([^\s"']+)"#, options: .regularExpression) {
            let match = String(text[range]).replacingOccurrences(
                of: #"-hf\s+"#, with: "", options: .regularExpression)
            return splitRef(match)
        }

        // 2. huggingface.co URL
        if let range = text.range(of: #"huggingface\.co/([\w.\-]+/[\w.\-]+)"#, options: .regularExpression) {
            let path = String(text[range]).replacingOccurrences(of: "huggingface.co/", with: "")
            return splitRef(path)
        }

        // 3. Bare owner/repo[:quant] — a single token containing exactly one slash
        if !text.contains(" "), text.filter({ $0 == "/" }).count == 1, !text.hasPrefix("/") {
            return splitRef(text)
        }
        return nil
    }

    private static func splitRef(_ ref: String) -> HFModelRef? {
        let parts = ref.split(separator: ":", maxSplits: 1).map(String.init)
        let repo = parts[0]
        guard repo.split(separator: "/").count == 2 else { return nil }
        return HFModelRef(repo: repo, quant: parts.count > 1 ? parts[1] : nil)
    }
}

// MARK: - Hub resolution

public enum HFHubError: Error, CustomStringConvertible {
    case repoNotFound(String)
    case noGGUF(String)
    case quantNotFound(String, available: [String])
    case multipart(String)

    public var description: String {
        switch self {
        case .repoNotFound(let repo):
            return "Repository \"\(repo)\" not found on Hugging Face (or it requires authentication)."
        case .noGGUF(let repo):
            return "\"\(repo)\" contains no GGUF files."
        case .quantNotFound(let quant, let available):
            return "No file matches \"\(quant)\". Available: \(available.joined(separator: ", "))"
        case .multipart(let file):
            return "\"\(file)\" is a split GGUF (multi-part) — not supported yet."
        }
    }
}

public enum HFHub {
    /// Resolve a repo reference to a concrete downloadable GGUF, using the same
    /// matching rule as llama.cpp's -hf flag: filename contains the quant tag
    /// (case-insensitive); default preference Q4_K_M.
    public static func resolveGGUF(_ ref: HFModelRef) async throws -> (fileName: String, url: URL) {
        let api = URL(string: "https://huggingface.co/api/models/\(ref.repo)")!
        let (data, response) = try await URLSession.shared.data(from: api)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let siblings = json["siblings"] as? [[String: Any]] else {
            throw HFHubError.repoNotFound(ref.repo)
        }
        let ggufs = siblings.compactMap { $0["rfilename"] as? String }
            .filter { $0.lowercased().hasSuffix(".gguf") }
        guard !ggufs.isEmpty else { throw HFHubError.noGGUF(ref.repo) }

        let file: String
        if let quant = ref.quant {
            guard let match = ggufs.first(where: { $0.lowercased().contains(quant.lowercased()) }) else {
                throw HFHubError.quantNotFound(quant, available: ggufs)
            }
            file = match
        } else if let preferred = ggufs.first(where: { $0.lowercased().contains("q4_k_m") }) {
            file = preferred
        } else {
            file = ggufs[0]
        }
        if file.range(of: #"-\d{5}-of-\d{5}"#, options: .regularExpression) != nil {
            throw HFHubError.multipart(file)
        }

        let encoded = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
        let url = URL(string: "https://huggingface.co/\(ref.repo)/resolve/main/\(encoded)?download=true")!
        // Keep the basename only — repos sometimes nest files in folders.
        let name = (file as NSString).lastPathComponent
        return (name, url)
    }
}

// MARK: - Download manager

/// One in-flight (or finished) model download shown in the Discover list.
public struct ModelDownload: Identifiable, Sendable {
    public enum Phase: Equatable, Sendable {
        case resolving
        case downloading
        case paused
        case finished
        case failed(String)
    }
    public let id: UUID
    public let input: String          // what the user pasted, for display
    public var fileName: String
    public var phase: Phase
    public var receivedBytes: Int64 = 0
    public var totalBytes: Int64 = 0
    public var bytesPerSec: Double = 0

    public var fractionDone: Double {
        totalBytes > 0 ? Double(receivedBytes) / Double(totalBytes) : 0
    }
}

/// Downloads GGUFs into the models folder with progress, pause/resume, and
/// cancel (PRD DL-3, minimum viable slice). The library's folder watcher picks
/// finished files up automatically.
@MainActor
public final class DownloadManager: NSObject, ObservableObject {
    @Published public private(set) var items: [ModelDownload] = []

    public var destinationDirectory: URL

    private var tasks: [UUID: URLSessionDownloadTask] = [:]
    private var resumeData: [UUID: Data] = [:]
    private var lastProgress: [UUID: (date: Date, bytes: Int64)] = [:]
    private lazy var session: URLSession = {
        let queue = OperationQueue()
        queue.underlyingQueue = .main
        return URLSession(configuration: .default, delegate: Delegate(manager: self), delegateQueue: queue)
    }()

    public init(destinationDirectory: URL) {
        self.destinationDirectory = destinationDirectory
    }

    public var hasActiveDownloads: Bool {
        items.contains { $0.phase == .downloading || $0.phase == .resolving || $0.phase == .paused }
    }

    /// Parse, resolve, and start downloading whatever the user pasted.
    public func start(input: String) async {
        guard let ref = HFCommandParser.parse(input) else {
            items.insert(ModelDownload(id: UUID(), input: input, fileName: input,
                                       phase: .failed("Couldn't find a model reference. Paste a llama.cpp command (llama serve -hf owner/repo:QUANT), owner/repo:QUANT, or a huggingface.co URL.")),
                         at: 0)
            return
        }
        let id = UUID()
        items.insert(ModelDownload(id: id, input: input,
                                   fileName: ref.quant.map { "\(ref.repo):\($0)" } ?? ref.repo,
                                   phase: .resolving), at: 0)
        do {
            let (fileName, url) = try await HFHub.resolveGGUF(ref)
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            if FileManager.default.fileExists(atPath: destinationDirectory.appendingPathComponent(fileName).path) {
                items[index].fileName = fileName
                items[index].phase = .failed("\(fileName) already exists in the models folder.")
                return
            }
            items[index].fileName = fileName
            items[index].phase = .downloading
            let task = session.downloadTask(with: url)
            task.taskDescription = id.uuidString
            tasks[id] = task
            task.resume()
        } catch {
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index].phase = .failed("\(error)")
            }
        }
    }

    public func pause(_ id: UUID) {
        guard let task = tasks[id] else { return }
        task.cancel { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.resumeData[id] = data
                self.tasks[id] = nil
                if let index = self.items.firstIndex(where: { $0.id == id }) {
                    self.items[index].phase = .paused
                    self.items[index].bytesPerSec = 0
                }
            }
        }
    }

    public func resume(_ id: UUID) {
        guard let data = resumeData[id],
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        resumeData[id] = nil
        items[index].phase = .downloading
        let task = session.downloadTask(withResumeData: data)
        task.taskDescription = id.uuidString
        tasks[id] = task
        task.resume()
    }

    public func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        resumeData[id] = nil
        items.removeAll { $0.id == id }
    }

    public func clearFinished() {
        items.removeAll { $0.phase == .finished || isFailed($0.phase) }
    }
    private func isFailed(_ phase: ModelDownload.Phase) -> Bool {
        if case .failed = phase { return true }
        return false
    }

    // MARK: internal callbacks (main queue)

    fileprivate func progress(id: UUID, written: Int64, total: Int64) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].receivedBytes = written
        items[index].totalBytes = total
        let now = Date()
        if let last = lastProgress[id] {
            let dt = now.timeIntervalSince(last.date)
            if dt > 0.8 {
                items[index].bytesPerSec = Double(written - last.bytes) / dt
                lastProgress[id] = (now, written)
            }
        } else {
            lastProgress[id] = (now, written)
        }
    }

    fileprivate func finished(id: UUID, location: URL) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let dest = destinationDirectory.appendingPathComponent(items[index].fileName)
        do {
            try? FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: dest)
            items[index].phase = .finished
            items[index].receivedBytes = items[index].totalBytes
        } catch {
            items[index].phase = .failed("Couldn't move into models folder: \(error.localizedDescription)")
        }
        tasks[id] = nil
        lastProgress[id] = nil
    }

    fileprivate func failed(id: UUID, error: Error) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        // cancel(byProducingResumeData:) also reports as an error — ignore those.
        if (error as NSError).code == NSURLErrorCancelled { return }
        items[index].phase = .failed(error.localizedDescription)
        tasks[id] = nil
    }

    private final class Delegate: NSObject, URLSessionDownloadDelegate {
        // URLSession delegate protocols are Sendable, which forbids mutable
        // stored properties. This is safe because the session's delegateQueue
        // runs on the main queue, so every access below is main-actor bound —
        // hence the MainActor.assumeIsolated in each callback.
        nonisolated(unsafe) weak var manager: DownloadManager?
        init(manager: DownloadManager) { self.manager = manager }

        private func id(of task: URLSessionTask) -> UUID? {
            task.taskDescription.flatMap(UUID.init(uuidString:))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            guard let id = id(of: downloadTask) else { return }
            MainActor.assumeIsolated {
                manager?.progress(id: id, written: totalBytesWritten, total: totalBytesExpectedToWrite)
            }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            guard let id = id(of: downloadTask) else { return }
            // Move synchronously — the temp file is deleted when this returns.
            MainActor.assumeIsolated {
                manager?.finished(id: id, location: location)
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        didCompleteWithError error: Error?) {
            guard let error, let id = id(of: task) else { return }
            MainActor.assumeIsolated {
                manager?.failed(id: id, error: error)
            }
        }
    }
}
