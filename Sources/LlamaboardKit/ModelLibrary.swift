import Foundation

/// A GGUF model discovered in the managed models directory.
public struct LibraryModel: Identifiable, Sendable, Equatable {
    public var id: String { url.path }
    public let url: URL
    public let fileName: String
    public let fileSize: UInt64
    public let metadata: GGUFMetadata?
    public let metadataError: String?

    public init(url: URL, fileName: String, fileSize: UInt64,
                metadata: GGUFMetadata?, metadataError: String?) {
        self.url = url
        self.fileName = fileName
        self.fileSize = fileSize
        self.metadata = metadata
        self.metadataError = metadataError
    }

    public var displayName: String {
        (fileName as NSString).deletingPathExtension
    }
    public var architecture: String { metadata?.architecture?.capitalized ?? "Unknown" }
    public var quant: String {
        metadata?.quantName ?? Self.quantFromName(fileName) ?? "—"
    }
    public var sizeGB: Double { Double(fileSize) / 1_073_741_824 }

    /// Fallback quant detection from filename, e.g. "…Q4_K_M.gguf".
    public static func quantFromName(_ name: String) -> String? {
        let upper = name.uppercased()
        for quant in GGUFReader.fileTypeNames.values.sorted(by: { $0.count > $1.count }) {
            if upper.contains(quant) { return quant }
        }
        return nil
    }
}

/// Scans and watches the managed models directory (PRD LIB-1..LIB-5).
/// The file system is the source of truth: models added or removed outside
/// the app are picked up by the directory watcher.
@MainActor
public final class ModelLibrary: ObservableObject {
    @Published public private(set) var models: [LibraryModel] = []
    @Published public private(set) var scanning = false
    @Published public private(set) var directory: URL

    private var watcher: DispatchSourceFileSystemObject?

    public init(directory: URL = AppPaths.models) {
        self.directory = directory
        startWatching()
        Task { await rescan() }
    }

    deinit {
        watcher?.cancel()
    }

    /// Point the library at a different folder (Settings → models folder).
    /// Models in the old folder are left untouched; the list reflects the new one.
    public func setDirectory(_ url: URL) {
        guard url != directory else { return }
        watcher?.cancel()
        watcher = nil
        directory = url
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        startWatching()
        Task { await rescan() }
    }

    /// Scan the directory for .gguf files and read their headers off-main.
    public func rescan() async {
        scanning = true
        defer { scanning = false }
        let dir = directory
        let found: [LibraryModel] = await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
            ) else { return [] }

            return entries
                .filter { $0.pathExtension.lowercased() == "gguf" }
                // Multi-part models: only list the first shard (LIB-4).
                .filter { !$0.lastPathComponent.contains("-of-") || $0.lastPathComponent.contains("-00001-of-") }
                .compactMap { url -> LibraryModel? in
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
                    var metadata: GGUFMetadata? = nil
                    var metadataError: String? = nil
                    do { metadata = try GGUFReader.read(url: url) }
                    catch { metadataError = "\(error)" }
                    return LibraryModel(url: url, fileName: url.lastPathComponent,
                                        fileSize: size, metadata: metadata, metadataError: metadataError)
                }
                .sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
        }.value
        models = found
    }

    /// Copy a GGUF file into the managed directory (drag-and-drop / Open panel import).
    public func importModel(from source: URL) async throws {
        let dest = directory.appendingPathComponent(source.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        let src = source
        try await Task.detached(priority: .utility) {
            try FileManager.default.copyItem(at: src, to: dest)
        }.value
        await rescan()
    }

    /// Delete a model file from disk (LIB-5).
    public func delete(_ model: LibraryModel) async throws {
        try FileManager.default.removeItem(at: model.url)
        await rescan()
    }

    private func startWatching() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            Task { await self?.rescan() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }
}
