import SwiftUI

/// The floating centered "pill" toolbar: brand, a search field, the Start Model
/// accent button, model filters, and the inspector toggle. Rendered as an
/// overlay at the top of the main content area.
struct TopBar: View {
    @EnvironmentObject var app: AppState
    @State private var showFilters = false
    var searchPlaceholder = "Search library..."

    var body: some View {
        HStack(spacing: 14) {
            Text("Llamaboard").font(.headlineMd).foregroundStyle(Theme.onSurface)
            Rectangle().fill(Theme.glassBorder).frame(width: 1, height: 16)

            search

            startStopButton

            HStack(spacing: 2) {
                filterButton
                iconButton("sidebar.right") { app.inspectorVisible.toggle() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassPanel(cornerRadius: 26)
        .fixedSize()
    }

    /// Filter popover: narrows the Library by size, parameter count, and fit.
    private var filterButton: some View {
        Button { showFilters.toggle() } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15))
                    .foregroundStyle(app.filtersActive ? Theme.primary : Theme.onSurfaceVariant)
                    .frame(width: 30, height: 30)
                if app.filtersActive {
                    Circle().fill(Theme.primary).frame(width: 7, height: 7)
                        .offset(x: -3, y: 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showFilters, arrowEdge: .bottom) {
            FilterPopover()
                .environmentObject(app)
        }
    }

    @ViewBuilder
    private var startStopButton: some View {
        switch app.server.state {
        case .stopped, .error:
            AccentButton(title: "Start Model", systemImage: "play.fill") { app.toggleServer() }
        case .loading:
            Button { app.toggleServer() } label: {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Loading…").font(.bodyMd.weight(.semibold))
                }
                .foregroundStyle(Theme.onSurface)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Theme.surfaceContainerHigh, in: Capsule())
            }
            .buttonStyle(.plain)
        case .running:
            Button { app.toggleServer() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill").font(.system(size: 12, weight: .semibold))
                    Text("Stop Model").font(.bodyMd.weight(.semibold))
                }
                .foregroundStyle(Theme.onSurface)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Theme.surfaceContainerHigh, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.systemGreen.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12)).foregroundStyle(Theme.onSurfaceVariant)
            SnapshotSafeTextField(placeholder: searchPlaceholder, text: $app.searchQuery)
                .frame(width: 150)
            if !app.searchQuery.isEmpty {
                Button { app.searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.onSurfaceVariant.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Theme.surfaceContainerHigh, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.glassBorder, lineWidth: 1))
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Theme.onSurfaceVariant)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Model filter controls shown from the top bar's slider icon.
private struct FilterPopover: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Filter Models").font(.bodyMd.weight(.bold)).foregroundStyle(Theme.onSurface)
                Spacer()
                if app.filtersActive {
                    Button { app.clearFilters() } label: {
                        Text("Clear All").font(.bodySm).foregroundStyle(Theme.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("File Size")
                chipRow(AppState.SizeFilter.allCases, selected: app.sizeFilter) { app.sizeFilter = $0 }
            }
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("Parameters")
                chipRow(AppState.ParamFilter.allCases, selected: app.paramFilter) { app.paramFilter = $0 }
            }
            Toggle(isOn: $app.fitsOnly) {
                Text("Only models that fit in memory")
                    .font(.bodySm).foregroundStyle(Theme.onSurface)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Theme.primary)

            Text("\(app.filteredModels.count) of \(app.library.models.count) models shown")
                .font(.monoData).foregroundStyle(Theme.onSurfaceVariant)
        }
        .padding(16)
        .frame(width: 300)
        .background(Theme.surfaceContainer)
    }

    private func chipRow<F: Identifiable & RawRepresentable & Equatable>(
        _ options: [F], selected: F, choose: @escaping (F) -> Void
    ) -> some View where F.RawValue == String {
        HStack(spacing: 6) {
            ForEach(options) { option in
                let isOn = option == selected
                Button { choose(option) } label: {
                    Text(option.rawValue)
                        .font(.system(size: 11, weight: isOn ? .bold : .regular))
                        .foregroundStyle(isOn ? Theme.onPrimary : Theme.onSurfaceVariant)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(isOn ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(Theme.surfaceContainerHigh),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
