import SwiftUI
import LlamaboardKit

/// Choose which quantization to download from a Hugging Face repository.
///
/// Every row shows the real file size from the hub plus an estimated memory
/// requirement and fit verdict for *this* Mac, so the trade-off between
/// quality and "will it actually run" is visible before downloading.
struct QuantPickerSheet: View {
    @EnvironmentObject var app: AppState
    let result: HFSearchResult
    /// Pre-fetched files, used by `--quant-picker` snapshots because
    /// ImageRenderer never runs `.task`.
    var preloaded: [HFHub.QuantFile]?

    @State private var files: [HFHub.QuantFile] = []
    @State private var recommended: HFHub.QuantFile?
    @State private var isLoading = true

    init(result: HFSearchResult, preloaded: [HFHub.QuantFile]? = nil) {
        self.result = result
        self.preloaded = preloaded
        if let preloaded {
            _files = State(initialValue: preloaded)
            _isLoading = State(initialValue: false)
        }
    }
    @State private var errorMessage: String?

    /// Estimates use the context a freshly downloaded model gets, not the
    /// context of whatever model happens to be selected — a 64K setting from an
    /// unrelated profile would make every option here look too large.
    private var contextTokens: UInt64 { UInt64(ModelSettings().contextSize) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.glassBorder)
            content
        }
        .frame(width: 560)
        .frame(maxHeight: 640)
        .glassPanel(cornerRadius: 24, fill: Theme.glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 40, y: 12)
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose a Quantization").font(.headlineMd).foregroundStyle(Theme.onSurface)
                Text(result.repo).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button { app.quantPickerTarget = nil } label: {
                Image(systemName: "xmark").font(.system(size: 14))
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Theme.surfaceContainerLow.opacity(0.8))
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading file sizes…").font(.bodySm).foregroundStyle(Theme.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 50)
        } else if let errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.systemOrange)
                Text(errorMessage).font(.bodySm).foregroundStyle(Theme.onSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(30)
        } else {
            VScroll {
                VStack(spacing: 8) {
                    ForEach(files) { file in
                        row(file)
                    }
                }
                .padding(16)
            }
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle").font(.system(size: 10))
            Text("Estimates assume the default \(ModelSettings().contextSize)-token context; a larger context needs proportionally more memory. Actual use depends on the model's architecture.")
                .font(.system(size: 10))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.onSurfaceVariant.opacity(0.7))
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceContainerLow.opacity(0.5))
    }

    private func row(_ file: HFHub.QuantFile) -> some View {
        let isRecommended = file.id == recommended?.id
        let fitStatus = HardwareInfo.fit(fileSize: UInt64(file.sizeBytes),
                                         metadata: nil, contextTokens: contextTokens)
        let estRAM = HardwareInfo.estimatedRAM(fileSize: UInt64(file.sizeBytes),
                                               metadata: nil, contextTokens: contextTokens)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(file.label)
                        .font(.bodyMd.weight(.bold).monospaced())
                        .foregroundStyle(Theme.onSurface)
                    if isRecommended {
                        Text("RECOMMENDED")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.onPrimary)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 3))
                    }
                    if file.isSplit {
                        Text("SPLIT")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.systemOrange)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Theme.systemOrange.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                HStack(spacing: 10) {
                    label("internaldrive", byteString(file.sizeBytes))
                    label("memorychip", "\(estRAM) est.")
                }
            }
            Spacer()
            StatusChip(text: fitLabel(fitStatus), color: fitColor(fitStatus))
            downloadButton(file)
        }
        .padding(14)
        .background(isRecommended ? Theme.primary.opacity(0.08) : Theme.glassFill,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(isRecommended ? Theme.primary.opacity(0.4) : Theme.glassBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func downloadButton(_ file: HFHub.QuantFile) -> some View {
        if file.isSplit {
            Text("Unsupported")
                .font(.bodySm).foregroundStyle(Theme.onSurfaceVariant.opacity(0.6))
                .help("Multi-part GGUFs can't be downloaded yet")
        } else {
            Button {
                // The resolver matches on the quant tag; fall back to the exact
                // file name for repos whose files carry no recognisable tag.
                let reference = file.quant.map { "\(result.repo):\($0)" } ?? result.repo
                Task { await app.downloads.start(input: reference) }
                app.quantPickerTarget = nil
                app.section = .discover
            } label: {
                Text("Download").font(.bodySm.weight(.bold))
                    .foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Theme.primary, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func label(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10))
            Text(text).font(.system(size: 10, design: .monospaced))
        }
        .foregroundStyle(Theme.onSurfaceVariant)
    }

    private func fitLabel(_ fit: HardwareInfo.Fit) -> String {
        switch fit {
        case .fits: return "Fits"
        case .tight: return "Tight"
        case .tooLarge: return "Too large"
        }
    }
    private func fitColor(_ fit: HardwareInfo.Fit) -> Color {
        switch fit {
        case .fits: return Theme.systemGreen
        case .tight: return Theme.systemOrange
        case .tooLarge: return Theme.systemRed
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func load() async {
        if let preloaded {
            files = preloaded
            recommended = HardwareInfo.recommendedQuant(from: preloaded, contextTokens: contextTokens)
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let found = try await HFHub.quantFiles(repo: result.repo)
            files = found
            recommended = HardwareInfo.recommendedQuant(from: found, contextTokens: contextTokens)
            if found.isEmpty { errorMessage = "This repository has no downloadable GGUF files." }
        } catch {
            errorMessage = "\(error)"
        }
    }
}
