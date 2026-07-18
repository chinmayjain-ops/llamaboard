import SwiftUI
import LlamaboardKit

/// Model Library — the home screen. A header with an Import action over a responsive
/// grid of glass model cards, backed by the real managed-directory scanner.
struct LibraryView: View {
    @EnvironmentObject var app: AppState

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 20)]

    var body: some View {
        VScroll {
            VStack(alignment: .leading, spacing: 28) {
                header
                if app.library.models.isEmpty {
                    emptyState
                } else if app.filteredModels.isEmpty {
                    noResults
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(app.filteredModels) { model in
                            ModelCard(model: model)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 88)   // clear the floating top bar
            .padding(.bottom, 24)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Model Library").font(.headlineLg).foregroundStyle(Theme.onSurface)
                Text("Manage and launch your local inference models.")
                    .font(.bodyMd).foregroundStyle(Theme.onSurfaceVariant)
            }
            Spacer()
            Button { app.importModelViaPanel() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 13))
                    Text("Import").font(.bodyMd)
                }
                .foregroundStyle(Theme.onSurface)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glassPanel(cornerRadius: 12)
            }
            .buttonStyle(.plain)
        }
    }

    private var noResults: some View {
        let searching = !app.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(spacing: 10) {
            Image(systemName: searching ? "magnifyingglass" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 28))
                .foregroundStyle(Theme.onSurfaceVariant.opacity(0.4))
            Text(searching
                 ? "No models match “\(app.searchQuery)”\(app.filtersActive ? " with the active filters" : "")"
                 : "No models match the active filters")
                .font(.bodyMd).foregroundStyle(Theme.onSurfaceVariant)
            HStack(spacing: 16) {
                if searching {
                    Button { app.searchQuery = "" } label: {
                        Text("Clear Search").font(.bodySm).foregroundStyle(Theme.primary)
                    }
                    .buttonStyle(.plain)
                }
                if app.filtersActive {
                    Button { app.clearFilters() } label: {
                        Text("Clear Filters").font(.bodySm).foregroundStyle(Theme.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "shippingbox")
                .font(.system(size: 40))
                .foregroundStyle(Theme.onSurfaceVariant.opacity(0.3))
                .frame(width: 96, height: 96)
                .glassPanel(cornerRadius: 48)
                .padding(.bottom, 24)
            Text("Library is Empty").font(.headlineMd).foregroundStyle(Theme.onSurface)
                .padding(.bottom, 8)
            Text("No models found in \(app.library.directory.path). Start by importing a GGUF file or browsing the Discover tab.")
                .font(.bodyMd).foregroundStyle(Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.bottom, 32)
            HStack(spacing: 16) {
                AccentButton(title: "Browse Discover") { app.section = .discover }
                Button { app.importModelViaPanel() } label: {
                    Text("Import Model").font(.bodyMd)
                        .foregroundStyle(Theme.onSurface)
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        .glassPanel(cornerRadius: 12)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

private struct ModelCard: View {
    @EnvironmentObject var app: AppState
    let model: LibraryModel
    @State private var hovering = false
    @State private var confirmingDelete = false

    private var fit: FitStatus { app.fit(for: model) }
    private var isRunning: Bool { app.server.currentModel?.id == model.id }
    private var isSelected: Bool { app.selectedModelID == model.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: model.cardSymbol)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 38, height: 38)
                    .background(Theme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.primary.opacity(0.2), lineWidth: 1))
                Spacer()
                StatusChip(text: isRunning ? "Running" : fit.label,
                           color: isRunning ? Theme.primary : fit.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(model.displayName).font(.headlineMd).foregroundStyle(Theme.onSurface)
                    .lineLimit(1).truncationMode(.middle)
                Text("ID: \(model.shortID)")
                    .font(.monoLabel).foregroundStyle(Theme.onSurfaceVariant.opacity(0.6))
            }

            VStack(spacing: 12) {
                HStack {
                    StatField(label: "Size", value: String(format: "%.2f GB", model.sizeGB))
                    Spacer()
                    StatField(label: "Quant", value: model.quant)
                    Spacer()
                    StatField(label: "Params", value: model.metadata?.parameterLabel ?? "—")
                }
                StatField(label: "Architecture", value: model.architecture)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
            .overlay(Rectangle().fill(Theme.glassBorder.opacity(0.5)).frame(height: 1), alignment: .top)
            .overlay(Rectangle().fill(Theme.glassBorder.opacity(0.5)).frame(height: 1), alignment: .bottom)

            HStack(spacing: 8) {
                Button {
                    if isRunning { app.server.stop() } else { app.start(model) }
                } label: {
                    Text(isRunning ? "Stop" : "Run").font(.bodyMd)
                        .foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Theme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.primary.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([model.url])
                } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 13))
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .frame(width: 38, height: 38)
                        .glassPanel(cornerRadius: 10)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
                Button { confirmingDelete = true } label: {
                    Image(systemName: "trash").font(.system(size: 14))
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .frame(width: 38, height: 38)
                        .glassPanel(cornerRadius: 10)
                }
                .buttonStyle(.plain)
                .confirmationDialog(
                    "Delete \(model.displayName)? This frees \(String(format: "%.2f GB", model.sizeGB)) of disk space.",
                    isPresented: $confirmingDelete, titleVisibility: .visible
                ) {
                    Button("Delete Model", role: .destructive) { app.deleteModel(model) }
                }
            }
        }
        .padding(20)
        .glassPanel(cornerRadius: 20, fill: hovering ? Theme.glassFillHi : Theme.glassFill)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.primary.opacity(hovering || isSelected ? 0.4 : 0), lineWidth: 1)
        )
        .offset(y: hovering ? -2 : 0)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture { app.select(model) }
    }
}
