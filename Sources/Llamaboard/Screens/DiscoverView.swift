import SwiftUI
import LlamaboardKit

/// Discover — paste-to-download from Hugging Face. Accepts the llama.cpp
/// command HF's "Use this model" dialog produces (`llama serve -hf owner/repo:QUANT`),
/// a bare `owner/repo:QUANT`, or a huggingface.co URL; resolves the GGUF and
/// downloads it into the models folder with live progress. Full hub browsing
/// arrives in beta 2.
struct DiscoverView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var pasted = ""
    @FocusState private var pasteFocused: Bool

    var body: some View {
        VScroll {
            VStack(alignment: .leading, spacing: 24) {
                header
                pasteBox
                if !app.downloads.items.isEmpty {
                    downloadsList
                }
                searchResults
                howTo
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.top, 96)
            .padding(.bottom, 24)
        }
        .onAppear { app.hubSearch.loadIfNeeded() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Discover Models").font(.headlineLg).foregroundStyle(Theme.onSurface)
            Text("Search Hugging Face from the toolbar, or paste a llama.cpp command to download a GGUF straight into your library.")
                .font(.bodyMd).foregroundStyle(Theme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Hub search results

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MonoLabel(app.searchQuery.isEmpty ? "Popular GGUF Models" : "Results")
                if app.hubSearch.isSearching {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                HStack(spacing: 4) {
                    ForEach(HFSortOrder.allCases) { order in
                        sortChip(order)
                    }
                }
            }

            if let error = app.hubSearch.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.systemOrange)
                    Text(error).font(.bodySm).foregroundStyle(Theme.onSurfaceVariant)
                    Spacer()
                }
                .padding(12)
                .background(Theme.systemOrange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            } else if app.hubSearch.results.isEmpty && !app.hubSearch.isSearching {
                Text(app.searchQuery.isEmpty
                     ? "No results yet."
                     : "No GGUF repositories match “\(app.searchQuery)”.")
                    .font(.bodySm).foregroundStyle(Theme.onSurfaceVariant)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                // Snapshot rendering can't scroll, so show a readable slice.
                ForEach(isSnapshot ? Array(app.hubSearch.results.prefix(4)) : app.hubSearch.results) { result in
                    HubResultRow(result: result)
                }
            }
        }
    }

    private func sortChip(_ order: HFSortOrder) -> some View {
        let isOn = app.hubSearch.sort == order
        return Button { app.hubSearch.sort = order } label: {
            Text(order.label)
                .font(.system(size: 11, weight: isOn ? .bold : .regular))
                .foregroundStyle(isOn ? Theme.onPrimary : Theme.onSurfaceVariant)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(isOn ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(Theme.surfaceContainerHigh),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Paste box

    private var pasteBox: some View {
        HStack(spacing: 10) {
            Image(systemName: "link").font(.system(size: 14)).foregroundStyle(Theme.primary)
            SnapshotSafeTextField(placeholder: "llama serve -hf owner/repo:Q4_K_M",
                                  text: $pasted, font: .monoData)
                .focused($pasteFocused)
                .onSubmit(startDownload)
            Button(action: startDownload) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 14))
                    Text("Download").font(.bodyMd.weight(.bold))
                }
                .foregroundStyle(Theme.onPrimary)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(pasted.isEmpty ? Theme.surfaceContainerHighest : Theme.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(pasted.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .glassPanel(cornerRadius: 16, fill: Theme.glassFillHi)
    }

    private func startDownload() {
        let input = pasted
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        pasted = ""
        Task { await app.downloads.start(input: input) }
    }

    // MARK: Downloads

    private var downloadsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MonoLabel("Downloads")
                Spacer()
                if app.downloads.items.contains(where: { $0.phase == .finished || isFailed($0.phase) }) {
                    Button { app.downloads.clearFinished() } label: {
                        Text("Clear Finished").font(.bodySm).foregroundStyle(Theme.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(app.downloads.items) { item in
                DownloadRow(item: item)
            }
        }
    }

    private func isFailed(_ phase: ModelDownload.Phase) -> Bool {
        if case .failed = phase { return true }
        return false
    }

    // MARK: How-to

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoLabel("How to get a command")
            VStack(alignment: .leading, spacing: 10) {
                howToStep("1", "On any GGUF model page on huggingface.co, open “Use this model” → llama.cpp.")
                howToStep("2", "Copy the `llama serve -hf owner/repo:QUANT` line (any of the install variants work).")
                howToStep("3", "Paste it above — Llamaboard resolves the right file and downloads it into your models folder.")
            }
            Text("Also accepted: owner/repo:Q4_K_M · owner/repo · a huggingface.co model URL. Without a quant tag, Q4_K_M is preferred (same default as llama.cpp). Split multi-part GGUFs aren't supported yet.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.onSurfaceVariant.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glassPanel(cornerRadius: 16)
    }

    private func howToStep(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.monoLabel).foregroundStyle(Theme.onPrimary)
                .frame(width: 18, height: 18)
                .background(Theme.primary, in: Circle())
            Text(text).font(.bodySm).foregroundStyle(Theme.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Hub result row

/// One Hugging Face repository in the search results.
private struct HubResultRow: View {
    @EnvironmentObject var app: AppState
    let result: HFSearchResult
    @State private var hovering = false

    private var alreadyInLibrary: Bool {
        // Quant tags vary, so match on the repo name appearing in a local file.
        app.library.models.contains { $0.displayName.localizedCaseInsensitiveContains(result.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(result.name).font(.bodyMd.weight(.bold)).foregroundStyle(Theme.onSurface)
                            .lineLimit(1).truncationMode(.middle)
                        if result.gated {
                            badge("GATED", Theme.systemOrange)
                        }
                        if !result.isLikelyChatModel, let tag = result.pipelineTag {
                            badge(tag.uppercased(), Theme.outline)
                        }
                    }
                    Text(result.author).font(.bodySm).foregroundStyle(Theme.onSurfaceVariant)
                }
                Spacer()
                downloadButton
            }

            HStack(spacing: 12) {
                stat("arrow.down.circle", compact(result.downloads))
                stat("heart", compact(result.likes))
                stat("doc", "\(result.ggufFiles.count) GGUF")
                if let modified = result.lastModified {
                    stat("clock", modified.formatted(.relative(presentation: .numeric)))
                }
            }

            if !result.quantTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(result.quantTags.prefix(6), id: \.self) { quant in
                        Text(quant)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.onSurfaceVariant)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Theme.surfaceContainer, in: RoundedRectangle(cornerRadius: 4))
                    }
                    if result.quantTags.count > 6 {
                        Text("+\(result.quantTags.count - 6)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.onSurfaceVariant.opacity(0.7))
                    }
                }
            }
        }
        .padding(14)
        .glassPanel(cornerRadius: 14, fill: hovering ? Theme.glassFillHi : Theme.glassFill)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var downloadButton: some View {
        if result.gated {
            Button {
                NSWorkspace.shared.open(URL(string: "https://huggingface.co/\(result.repo)")!)
            } label: {
                Text("Accept license ↗").font(.bodySm)
                    .foregroundStyle(Theme.systemOrange)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Theme.systemOrange.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("This repository requires accepting its license on Hugging Face first")
        } else if result.isSplitOnly {
            Text("Split file").font(.bodySm)
                .foregroundStyle(Theme.onSurfaceVariant.opacity(0.7))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .help("Only multi-part GGUFs are published here — not supported yet")
        } else if alreadyInLibrary {
            Text("In library").font(.bodySm)
                .foregroundStyle(Theme.systemGreen)
                .padding(.horizontal, 12).padding(.vertical, 7)
        } else {
            HStack(spacing: 6) {
                // Repos with more than one quant get the picker; single-file
                // repos would just show one row, so download straight away.
                if result.quantTags.count > 1 {
                    Button { app.quantPickerTarget = result } label: {
                        HStack(spacing: 5) {
                            Text("Choose quant").font(.bodySm.weight(.bold))
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Theme.onPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.primary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Compare sizes and memory fit for every quantization")
                } else {
                    Button {
                        Task { await app.downloads.start(input: result.repo) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down.circle.fill").font(.system(size: 12))
                            Text("Download").font(.bodySm.weight(.bold))
                        }
                        .foregroundStyle(Theme.onPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.primary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
    }

    private func stat(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10))
            Text(text).font(.system(size: 10, design: .monospaced))
        }
        .foregroundStyle(Theme.onSurfaceVariant)
    }

    private func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Download row

private struct DownloadRow: View {
    @EnvironmentObject var app: AppState
    let item: ModelDownload

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                phaseIcon
                Text(item.fileName)
                    .font(.bodyMd).foregroundStyle(Theme.onSurface)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                trailing
            }

            switch item.phase {
            case .downloading, .paused:
                ProgressBar(value: item.fractionDone,
                            color: item.phase == .paused ? Theme.systemOrange : Theme.primary)
                    .frame(height: 6)
                HStack {
                    Text("\(byteString(item.receivedBytes)) / \(byteString(item.totalBytes))")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.onSurfaceVariant)
                    Spacer()
                    if item.phase == .downloading, item.bytesPerSec > 0 {
                        Text("\(byteString(Int64(item.bytesPerSec)))/s · \(etaString)")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.onSurfaceVariant)
                    } else if item.phase == .paused {
                        Text("Paused").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.systemOrange)
                    }
                }
            case .failed(let message):
                Text(message).font(.bodySm).foregroundStyle(Theme.systemRed)
                    .fixedSize(horizontal: false, vertical: true)
            case .finished:
                Text("Added to your library").font(.bodySm).foregroundStyle(Theme.systemGreen)
            case .resolving:
                Text("Resolving on Hugging Face…").font(.bodySm).foregroundStyle(Theme.onSurfaceVariant)
            }
        }
        .padding(14)
        .glassPanel(cornerRadius: 14)
    }

    @ViewBuilder
    private var phaseIcon: some View {
        switch item.phase {
        case .resolving: ProgressView().controlSize(.small)
        case .downloading: Image(systemName: "arrow.down.circle").foregroundStyle(Theme.primary)
        case .paused: Image(systemName: "pause.circle").foregroundStyle(Theme.systemOrange)
        case .finished: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.systemGreen)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.systemRed)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 6) {
            switch item.phase {
            case .downloading:
                Text(String(format: "%.0f%%", item.fractionDone * 100))
                    .font(.monoData).foregroundStyle(Theme.primary)
                smallButton("pause.fill") { app.downloads.pause(item.id) }
                smallButton("xmark") { app.downloads.cancel(item.id) }
            case .paused:
                smallButton("play.fill") { app.downloads.resume(item.id) }
                smallButton("xmark") { app.downloads.cancel(item.id) }
            case .failed:
                smallButton("xmark") { app.downloads.cancel(item.id) }
            case .finished:
                Button { app.section = .library } label: {
                    Text("Show in Library").font(.bodySm).foregroundStyle(Theme.primary)
                }
                .buttonStyle(.plain)
            case .resolving:
                smallButton("xmark") { app.downloads.cancel(item.id) }
            }
        }
    }

    private func smallButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.onSurfaceVariant)
                .frame(width: 24, height: 24)
                .background(Theme.surfaceContainerHigh, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var etaString: String {
        guard item.bytesPerSec > 0, item.totalBytes > item.receivedBytes else { return "—" }
        let seconds = Int(Double(item.totalBytes - item.receivedBytes) / item.bytesPerSec)
        if seconds < 60 { return "\(seconds)s left" }
        return "\(seconds / 60)m \(seconds % 60)s left"
    }

    private func byteString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
