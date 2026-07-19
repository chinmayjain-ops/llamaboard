import SwiftUI
import LlamaboardKit

/// Assembles the Tahoe-style floating layout: a dark ambient background with a glass
/// sidebar, main content area (with the floating top pill overlaid), and an optional
/// inspector — plus the modal quantization picker.
struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            background

            HStack(spacing: Theme.gutter) {
                Sidebar()

                mainArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showsInspector {
                    Inspector()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(Theme.windowMargin)

            if app.showSettings {
                settingsOverlay
            }
            if let target = app.quantPickerTarget {
                quantPickerOverlay(target)
            }
        }
        .frame(minWidth: 1120, minHeight: 720)
        .animation(.easeInOut(duration: 0.2), value: app.inspectorVisible)
        .animation(.easeInOut(duration: 0.2), value: app.section)
        .preferredColorScheme(.dark)
    }

    /// Inspector only makes sense on Library and Chat (Server has its own right pane).
    private var showsInspector: Bool {
        app.inspectorVisible && (app.section == .library || app.section == .chat)
    }

    private var mainArea: some View {
        ZStack(alignment: .top) {
            Group {
                switch app.section {
                case .chat:     ChatView()
                case .library:  LibraryView()
                case .discover: DiscoverView()
                case .apps:     AppsView()
                case .server:   ServerView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            TopBar(searchPlaceholder: {
                switch app.section {
                case .discover: "Search Hugging Face models…"
                case .apps:     "Search apps…"
                default:        "Search library…"
                }
            }())
                .padding(.top, 4)
        }
    }

    private var background: some View {
        ZStack {
            Theme.background
            // Soft ambient glow, echoing the mockup's shader backdrop.
            RadialGradient(colors: [Theme.primaryContainer.opacity(0.18), .clear],
                           center: .init(x: 0.15, y: 0.0), startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Theme.primary.opacity(0.10), .clear],
                           center: .init(x: 0.95, y: 0.9), startRadius: 0, endRadius: 600)
        }
        .ignoresSafeArea()
    }

    private func quantPickerOverlay(_ target: HFSearchResult) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { app.quantPickerTarget = nil }
            QuantPickerSheet(result: target, preloaded: app.quantPickerPreload)
        }
        .transition(.opacity)
    }

    private var settingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { app.showSettings = false }
            SettingsSheet()
        }
        .transition(.opacity)
    }
}
