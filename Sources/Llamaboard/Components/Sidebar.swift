import SwiftUI

/// The floating left navigation rail — a glass panel with the brand mark, section
/// links, a "loading model" progress card, and Settings/Help at the bottom.
struct Sidebar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gutter) {
            brand
            VStack(spacing: 4) {
                ForEach(Section.allCases) { section in
                    navItem(section)
                }
            }
            Spacer(minLength: 0)
            statusCard
            footerLink("Settings", "gearshape") { app.showSettings = true }
            footerLink("Help", "questionmark.circle") {
                NSWorkspace.shared.open(URL(string: "https://github.com/ggml-org/llama.cpp/tree/master/tools/server")!)
            }
        }
        .padding(Theme.lensPadding)
        .frame(width: Theme.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassPanel(cornerRadius: 20)
    }

    private var brand: some View {
        HStack(spacing: 12) {
            LogoMark(size: 40, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text("Llamaboard").font(.headlineMd).foregroundStyle(Theme.onSurface)
                Text("llama.cpp Native").font(.bodySm).foregroundStyle(Theme.onSurfaceVariant.opacity(0.7))
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }

    private func navItem(_ section: Section) -> some View {
        let active = app.section == section
        return Button {
            app.section = section
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.symbol)
                    .font(.system(size: 16, weight: active ? .semibold : .regular))
                    .frame(width: 20)
                Text(section.rawValue).font(.bodyMd)
                Spacer(minLength: 0)
            }
            .foregroundStyle(active ? Theme.onPrimary : Theme.onSurfaceVariant)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.primary)
                        .shadow(color: Theme.primary.opacity(0.25), radius: 14)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Live server status pill: spinner while loading, green dot while running,
    /// red dot on error, hidden when stopped.
    @ViewBuilder
    private var statusCard: some View {
        switch app.server.state {
        case .stopped:
            EmptyView()
        case .loading(let model):
            statusCardBody(label: "Loading Model", labelColor: Theme.primary, detail: model) {
                ProgressView().controlSize(.small).tint(Theme.primary)
            }
        case .running(let model):
            statusCardBody(label: "Running", labelColor: Theme.systemGreen, detail: model) {
                Circle().fill(Theme.systemGreen).frame(width: 8, height: 8)
            }
        case .error:
            statusCardBody(label: "Server Error", labelColor: Theme.systemRed, detail: "See Server tab") {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(Theme.systemRed)
            }
        }
    }

    private func statusCardBody(label: String, labelColor: Color, detail: String,
                                @ViewBuilder indicator: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MonoLabel(label, color: labelColor)
                Spacer()
                indicator()
            }
            Text(detail)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.onSurfaceVariant.opacity(0.7))
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(12)
        .background(Theme.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.glassBorder, lineWidth: 1))
        .padding(.bottom, 4)
    }

    private func footerLink(_ title: String, _ symbol: String,
                            action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 16)).frame(width: 20)
                Text(title).font(.bodyMd)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.onSurfaceVariant)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
