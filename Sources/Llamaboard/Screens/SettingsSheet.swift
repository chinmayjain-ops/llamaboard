import SwiftUI
import LlamaboardKit

/// App-level settings, presented as a glass modal (same idiom as the quant picker):
/// the models folder location and the llama-server binary source.
struct SettingsSheet: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 24) {
                modelsFolderSection
                serverBinarySection
                hardwareSection
            }
            .padding(20)
        }
        .frame(width: 520)
        .glassPanel(cornerRadius: 24, fill: Theme.glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 40, y: 12)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings").font(.headlineMd).foregroundStyle(Theme.onSurface)
                Text("Llamaboard preferences").font(.system(size: 11)).foregroundStyle(Theme.onSurfaceVariant)
            }
            Spacer()
            Button { app.showSettings = false } label: {
                Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(Theme.onSurfaceVariant)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(20)
        .background(Theme.surfaceContainerLow.opacity(0.8))
        .overlay(Rectangle().fill(Theme.glassBorder).frame(height: 1), alignment: .bottom)
    }

    // MARK: Models folder

    private var modelsFolderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Models Folder")
            pathRow(icon: "folder", path: app.library.directory.path)
            HStack(spacing: 8) {
                actionButton("Change…", prominent: true) { app.changeModelsFolder() }
                actionButton("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([app.library.directory])
                }
                Spacer()
                Text("\(app.library.models.count) model\(app.library.models.count == 1 ? "" : "s")")
                    .font(.monoData).foregroundStyle(Theme.onSurfaceVariant)
            }
            Text("GGUF files in this folder appear in the Library. Changing the folder does not move or delete existing files.")
                .font(.system(size: 10)).foregroundStyle(Theme.onSurfaceVariant.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Server binary

    private var serverBinarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("llama-server Binary")
            pathRow(icon: "terminal", path: app.resolvedServerBinaryPath,
                    badge: app.customServerBinaryPath == nil ? "AUTO" : "CUSTOM",
                    badgeColor: app.customServerBinaryPath == nil ? Theme.systemGreen : Theme.systemOrange)
            HStack(spacing: 8) {
                actionButton("Choose Custom…") { app.chooseServerBinary() }
                if app.customServerBinaryPath != nil {
                    actionButton("Use Auto-Detected") { app.resetServerBinary() }
                }
            }
            Text("Auto-detection checks the app bundle, then Homebrew. Point at a self-compiled build to use a custom llama.cpp. Takes effect on the next model start.")
                .font(.system(size: 10)).foregroundStyle(Theme.onSurfaceVariant.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Hardware summary

    private var hardwareSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("This Mac")
            HStack(spacing: 16) {
                StatField(label: "Unified Memory",
                          value: String(format: "%.0f GB", Double(HardwareInfo.totalMemory) / 1_073_741_824))
                StatField(label: "GPU Budget (est.)",
                          value: String(format: "%.0f GB", Double(HardwareInfo.gpuBudget) / 1_073_741_824))
            }
            Text("The GPU budget estimate drives the Fits VRAM badges in the Library.")
                .font(.system(size: 10)).foregroundStyle(Theme.onSurfaceVariant.opacity(0.7))
        }
    }

    // MARK: Bits

    private func pathRow(icon: String, path: String,
                         badge: String? = nil, badgeColor: Color = Theme.systemGreen) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Theme.primary)
            Text(path).font(.monoData).foregroundStyle(Theme.onSurface)
                .lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            if let badge {
                Text(badge).font(.monoLabel).foregroundStyle(badgeColor)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(badgeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.surfaceContainer, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.glassBorder, lineWidth: 1))
    }

    private func actionButton(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.bodySm.weight(prominent ? .bold : .regular))
                .foregroundStyle(prominent ? Theme.onPrimary : Theme.onSurface)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(prominent ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(Theme.glassFillHi),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(prominent ? .clear : Theme.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
