import SwiftUI

/// App Control (PRD §6.7) — companion apps that consume Llamaboard's local
/// endpoint, each launchable with the endpoint injected. Known apps (Hermes,
/// OpenClaw) plus user-added custom entries.
struct AppsView: View {
    @EnvironmentObject var app: AppState

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 20)]

    var body: some View {
        VScroll {
            VStack(alignment: .leading, spacing: 24) {
                header
                endpointBanner
                if let error = app.companionApps.lastLaunchError {
                    errorBanner(error)
                }
                if let note = app.companionApps.lastLaunchNote {
                    noteBanner(note)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(app.filteredCompanionApps) { companion in
                        CompanionCard(companion: companion)
                    }
                }
                if app.filteredCompanionApps.isEmpty {
                    noResults
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 88)
            .padding(.bottom, 24)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("App Control").font(.headlineLg).foregroundStyle(Theme.onSurface)
                Text("Launch companion apps pre-wired to your local model endpoint.")
                    .font(.bodyMd).foregroundStyle(Theme.onSurfaceVariant)
            }
            Spacer()
            Button { app.addCustomCompanionApp() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 13))
                    Text("Add Custom App…").font(.bodyMd)
                }
                .foregroundStyle(Theme.onSurface)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glassPanel(cornerRadius: 12)
            }
            .buttonStyle(.plain)
        }
    }

    /// APP-3: show what launched apps will receive, or how to get there.
    @ViewBuilder
    private var endpointBanner: some View {
        if app.server.state.isRunning {
            HStack(spacing: 10) {
                Circle().fill(Theme.systemGreen).frame(width: 8, height: 8)
                Text("Apps launch with").font(.bodySm).foregroundStyle(Theme.onSurfaceVariant)
                Text("OPENAI_BASE_URL = \(app.server.baseURL.absoluteString)/v1")
                    .font(.monoData).foregroundStyle(Theme.primary)
                Spacer()
                Text(app.runningModelName)
                    .font(.monoLabel).foregroundStyle(Theme.systemGreen)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .glassPanel(cornerRadius: 14)
        } else {
            HStack(spacing: 10) {
                Circle().fill(Theme.systemOrange).frame(width: 8, height: 8)
                Text("No model running — apps will open without an endpoint. Start a model so they connect to Llamaboard.")
                    .font(.bodySm).foregroundStyle(Theme.onSurfaceVariant)
                Spacer()
                AccentButton(title: "Start Model", systemImage: "play.fill") { app.toggleServer() }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassPanel(cornerRadius: 14)
        }
    }

    private func noteBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle").foregroundStyle(Theme.systemGreen)
            Text(message).font(.bodySm).foregroundStyle(Theme.onSurfaceVariant)
            Spacer()
        }
        .padding(12)
        .background(Theme.systemGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.systemRed)
            Text(message).font(.bodySm).foregroundStyle(Theme.systemRed)
            Spacer()
        }
        .padding(12)
        .background(Theme.systemRed.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private var noResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(Theme.onSurfaceVariant.opacity(0.4))
            Text("No apps match “\(app.searchQuery)”")
                .font(.bodyMd).foregroundStyle(Theme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

private struct CompanionCard: View {
    @EnvironmentObject var app: AppState
    let companion: CompanionApp
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                iconView
                VStack(alignment: .leading, spacing: 2) {
                    Text(companion.name).font(.headlineMd).foregroundStyle(Theme.onSurface)
                    if companion.isCustom {
                        Text("Custom app").font(.system(size: 11)).foregroundStyle(Theme.outlineVariant)
                    }
                }
                Spacer()
                StatusChip(text: companion.isInstalled ? "Ready" : "Not installed",
                           color: companion.isInstalled ? Theme.systemGreen : Theme.outline)
            }

            Text(companion.tagline)
                .font(.bodyMd).foregroundStyle(Theme.onSurfaceVariant)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let path = companion.resolvedPath {
                Text(path).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.onSurfaceVariant.opacity(0.6))
                    .lineLimit(1).truncationMode(.middle)
            }

            HStack(spacing: 8) {
                if companion.isInstalled {
                    Button { app.launchCompanionApp(companion) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.forward.app").font(.system(size: 13, weight: .semibold))
                            Text("Launch").font(.bodyMd.weight(.bold))
                        }
                        .foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Theme.primary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: Theme.primary.opacity(0.25), radius: 10)
                    }
                    .buttonStyle(.plain)
                } else if let installURL = companion.installURL {
                    Button { NSWorkspace.shared.open(installURL) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "safari").font(.system(size: 13))
                            Text("Get \(companion.name)").font(.bodyMd)
                        }
                        .foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Theme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.primary.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Not found on this Mac")
                        .font(.bodySm).foregroundStyle(Theme.onSurfaceVariant.opacity(0.6))
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                }
                if companion.isCustom {
                    Button { app.companionApps.removeCustomApp(companion) } label: {
                        Image(systemName: "trash").font(.system(size: 13))
                            .foregroundStyle(Theme.onSurfaceVariant)
                            .frame(width: 36, height: 36)
                            .glassPanel(cornerRadius: 10)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from launcher")
                }
            }
        }
        .padding(20)
        .glassPanel(cornerRadius: 20, fill: hovering ? Theme.glassFillHi : Theme.glassFill)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Theme.primary.opacity(hovering ? 0.35 : 0), lineWidth: 1))
        .offset(y: hovering ? -2 : 0)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = companion.icon {
            Image(nsImage: icon)
                .resizable().interpolation(.high)
                .frame(width: 44, height: 44)
        } else {
            Image(systemName: companion.fallbackSymbol)
                .font(.system(size: 20))
                .foregroundStyle(Theme.primary)
                .frame(width: 44, height: 44)
                .background(Theme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.primary.opacity(0.2), lineWidth: 1))
        }
    }
}
