import SwiftUI
import LlamaboardKit

/// Discover — paste-to-download from Hugging Face. Accepts the llama.cpp
/// command HF's "Use this model" dialog produces (`llama serve -hf owner/repo:QUANT`),
/// a bare `owner/repo:QUANT`, or a huggingface.co URL; resolves the GGUF and
/// downloads it into the models folder with live progress. Full hub browsing
/// arrives in beta 2.
struct DiscoverView: View {
    @EnvironmentObject var app: AppState
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
                howTo
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.top, 96)
            .padding(.bottom, 24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Discover Models").font(.headlineLg).foregroundStyle(Theme.onSurface)
            Text("Paste a llama.cpp command, owner/repo:QUANT, or Hugging Face link to download a GGUF straight into your library.")
                .font(.bodyMd).foregroundStyle(Theme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
