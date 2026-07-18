import SwiftUI
import Combine
import LlamaboardKit

/// Central UI state, backed by the real LlamaboardKit services: the model library
/// scanner, the llama-server process manager, per-model settings profiles, and the
/// streaming chat client. Discover content remains curated sample data (M2 scope —
/// the HF client ships with the download manager).
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: Services
    let library: ModelLibrary
    let server = ServerManager()
    let settingsStore = SettingsStore()
    let companionApps = CompanionAppsManager()
    let downloads: DownloadManager

    // MARK: Persisted app preferences
    private enum PrefKey {
        static let modelsDirectory = "modelsDirectory"
        static let serverBinary = "serverBinary"
    }

    // MARK: Navigation & chrome
    @Published var section: Section = .library
    @Published var inspectorVisible = true
    @Published var showSettings = false
    @Published var searchQuery = ""

    // MARK: Selection & settings
    @Published var selectedModelID: LibraryModel.ID?
    /// Settings profile of the selected (or running) model; saved on change.
    @Published var activeSettings = ModelSettings() {
        didSet {
            guard let model = activeModel, !suppressSettingsSave else { return }
            try? settingsStore.save(activeSettings, for: model.fileName)
        }
    }
    private var suppressSettingsSave = false

    // MARK: Chat
    @Published var messages: [ChatMessage] = []
    /// Accumulated internally during a stream; rendered only on completion.
    /// Deliberately NOT @Published — publishing per token re-renders the whole
    /// window for every delta and makes the UI unresponsive during generation.
    var streamingText = ""
    /// Published every 10 tokens (not each one) to drive the indicator counter.
    @Published var streamedTokens = 0
    @Published var isGenerating = false
    @Published var chatError: String?
    private var chatTask: Task<Void, Never>?

    private var cancellables: Set<AnyCancellable> = []

    init() {
        // Restore persisted preferences before the services spin up.
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: PrefKey.modelsDirectory), !path.isEmpty {
            library = ModelLibrary(directory: URL(fileURLWithPath: path, isDirectory: true))
        } else {
            library = ModelLibrary()
        }
        downloads = DownloadManager(destinationDirectory: library.directory)
        ServerManager.customBinaryPath = defaults.string(forKey: PrefKey.serverBinary)
        // Forward nested ObservableObject changes so views observing AppState update.
        library.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        server.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        companionApps.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        downloads.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        // Downloads land in whatever folder the library currently points at.
        library.$directory.sink { [weak self] dir in self?.downloads.destinationDirectory = dir }.store(in: &cancellables)
        // Auto-select the first model once the initial scan lands.
        library.$models.receive(on: RunLoop.main).sink { [weak self] models in
            guard let self else { return }
            if self.selectedModelID == nil || !models.contains(where: { $0.id == self.selectedModelID }) {
                self.select(models.first)
            }
        }.store(in: &cancellables)
    }

    // MARK: - Search & filters (LIB-6)

    enum SizeFilter: String, CaseIterable, Identifiable {
        case any = "Any size"
        case small = "< 2 GB"
        case medium = "2–8 GB"
        case large = "> 8 GB"
        var id: String { rawValue }

        func matches(_ model: LibraryModel) -> Bool {
            switch self {
            case .any: return true
            case .small: return model.sizeGB < 2
            case .medium: return model.sizeGB >= 2 && model.sizeGB <= 8
            case .large: return model.sizeGB > 8
            }
        }
    }

    enum ParamFilter: String, CaseIterable, Identifiable {
        case any = "Any params"
        case small = "< 3B"
        case medium = "3–8B"
        case large = "> 8B"
        var id: String { rawValue }

        func matches(_ model: LibraryModel) -> Bool {
            guard self != .any else { return true }
            // Unknown parameter counts only match "Any".
            guard let params = model.metadata?.parameterCount, params > 0 else { return false }
            let billions = Double(params) / 1e9
            switch self {
            case .any: return true
            case .small: return billions < 3
            case .medium: return billions >= 3 && billions <= 8
            case .large: return billions > 8
            }
        }
    }

    @Published var sizeFilter: SizeFilter = .any
    @Published var paramFilter: ParamFilter = .any
    @Published var fitsOnly = false

    var filtersActive: Bool {
        sizeFilter != .any || paramFilter != .any || fitsOnly
    }

    func clearFilters() {
        sizeFilter = .any
        paramFilter = .any
        fitsOnly = false
    }

    /// Library models matching the search query and active filters.
    var filteredModels: [LibraryModel] {
        var result = library.models
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter {
                $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.quant.localizedCaseInsensitiveContains(query)
                || $0.architecture.localizedCaseInsensitiveContains(query)
            }
        }
        result = result.filter { sizeFilter.matches($0) && paramFilter.matches($0) }
        if fitsOnly {
            result = result.filter { fit(for: $0) == .fits }
        }
        return result
    }

    /// Companion apps matching the search query.
    var filteredCompanionApps: [CompanionApp] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return companionApps.apps }
        return companionApps.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// Launch a companion app, handing it the live endpoint when a model is running.
    func launchCompanionApp(_ companion: CompanionApp) {
        let endpoint = server.state.isRunning
            ? server.baseURL.appendingPathComponent("v1")
            : nil
        companionApps.launch(companion, endpoint: endpoint,
                             modelName: server.state.modelName)
    }

    func addCustomCompanionApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an app or executable to add to the launcher."
        panel.prompt = "Add App"
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        companionApps.addCustomApp(path: url.path)
    }

    // MARK: - Settings actions

    /// Where the resolved llama-server binary lives, for display in Settings.
    var resolvedServerBinaryPath: String {
        ServerManager.findServerBinary()?.path ?? "Not found"
    }
    var customServerBinaryPath: String? {
        ServerManager.customBinaryPath
    }

    func changeModelsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = library.directory
        panel.message = "Choose the folder where Llamaboard looks for GGUF models."
        panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        library.setDirectory(url)
        UserDefaults.standard.set(url.path, forKey: PrefKey.modelsDirectory)
    }

    func chooseServerBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Choose a llama-server executable (e.g. a self-compiled build)."
        panel.prompt = "Use Binary"
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        ServerManager.customBinaryPath = url.path
        UserDefaults.standard.set(url.path, forKey: PrefKey.serverBinary)
        objectWillChange.send()
    }

    func resetServerBinary() {
        ServerManager.customBinaryPath = nil
        UserDefaults.standard.removeObject(forKey: PrefKey.serverBinary)
        objectWillChange.send()
    }

    // MARK: - Model selection & lifecycle

    var activeModel: LibraryModel? {
        server.currentModel
            ?? library.models.first { $0.id == selectedModelID }
            ?? library.models.first
    }

    func select(_ model: LibraryModel?) {
        selectedModelID = model?.id
        suppressSettingsSave = true
        activeSettings = model.map { settingsStore.load(for: $0.fileName) } ?? ModelSettings()
        suppressSettingsSave = false
    }

    func fit(for model: LibraryModel) -> FitStatus {
        let ctx = UInt64(model.id == activeModel?.id ? activeSettings.contextSize : 4096)
        switch HardwareInfo.fit(fileSize: model.fileSize, metadata: model.metadata, contextTokens: ctx) {
        case .fits: return .fits
        case .tight: return .tight
        case .tooLarge: return .tooLarge
        }
    }

    func startSelectedModel() {
        guard let model = activeModel else { return }
        select(model)
        server.start(model: model, settings: activeSettings)
    }

    func toggleServer() {
        if server.state.isRunning || server.state.isBusy {
            server.stop()
        } else {
            startSelectedModel()
        }
    }

    func start(_ model: LibraryModel) {
        select(model)
        server.start(model: model, settings: activeSettings)
    }

    func deleteModel(_ model: LibraryModel) {
        if server.currentModel?.id == model.id { server.stop() }
        Task { try? await library.delete(model) }
    }

    func importModelViaPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = []
        panel.title = "Import GGUF Models"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where url.pathExtension.lowercased() == "gguf" {
            Task { try? await library.importModel(from: url) }
        }
    }

    // MARK: - Chat

    var runningModelName: String {
        server.state.modelName ?? activeModel?.displayName ?? "No model"
    }

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating, server.state.isRunning else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        messages.append(ChatMessage(role: .user, text: trimmed,
                                    timestamp: "User • \(formatter.string(from: Date()))"))
        chatError = nil
        streamingText = ""
        streamedTokens = 0
        isGenerating = true

        let history = messages.map {
            ChatTurn(role: $0.role == .user ? "user" : "assistant", content: $0.text)
        }
        let client = ChatClient(baseURL: server.baseURL)
        let settings = activeSettings
        let modelLabel = runningModelName

        chatTask = Task {
            var tokenCount = 0
            do {
                for try await event in client.stream(messages: history, settings: settings) {
                    switch event {
                    case .delta(let piece):
                        streamingText += piece
                        tokenCount += 1
                        if tokenCount % 10 == 0 { streamedTokens = tokenCount }
                    case .finished(let metrics):
                        messages.append(ChatMessage(
                            role: .assistant,
                            text: streamingText,
                            timestamp: modelLabel,
                            tokensPerSec: metrics.tokensPerSec,
                            tokens: metrics.tokens,
                            ttft: metrics.ttft))
                        server.recordChatMetrics(tokensPerSec: metrics.tokensPerSec)
                    }
                }
            } catch is CancellationError {
                if !streamingText.isEmpty {
                    messages.append(ChatMessage(role: .assistant, text: streamingText, timestamp: modelLabel))
                }
            } catch {
                chatError = "\(error)"
            }
            streamingText = ""
            isGenerating = false
        }
    }

    func stopGeneration() {
        chatTask?.cancel()
    }

    // MARK: - Estimated memory (telemetry cards)

    var estimatedModelBytes: UInt64 { activeModel?.fileSize ?? 0 }
    var estimatedKVBytes: UInt64 {
        guard let model = activeModel else { return 0 }
        return HardwareInfo.kvCacheBytes(
            metadata: model.metadata,
            contextTokens: UInt64(activeSettings.contextSize))
    }
    var gpuBudgetBytes: UInt64 { HardwareInfo.gpuBudget }

    // MARK: - Sample content (bench history is SRV-11/P1)

    let benchRuns: [BenchRun] = [
        BenchRun(model: "Llama-3-8B-Instruct", quant: "Q4_K_M", promptTS: "142.4", evalTS: "48.2", date: "2h ago"),
        BenchRun(model: "Mistral-7B-v0.3", quant: "Q8_0", promptTS: "128.1", evalTS: "41.9", date: "Yesterday"),
        BenchRun(model: "Phi-3-Mini-4K", quant: "FP16", promptTS: "256.0", evalTS: "84.5", date: "3d ago"),
        BenchRun(model: "Gemma-2b-it", quant: "Q4_K_M", promptTS: "310.2", evalTS: "92.1", date: "1w ago")
    ]
}
