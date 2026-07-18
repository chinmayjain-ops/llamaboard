import SwiftUI

/// ImageRenderer (used by `--snapshot`) cannot lay out ScrollView contents, so in
/// snapshot mode these wrappers degrade to plain stacks and static text.
private struct IsSnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSnapshot: Bool {
        get { self[IsSnapshotKey.self] }
        set { self[IsSnapshotKey.self] = newValue }
    }
}

/// A vertical ScrollView that becomes a plain container in snapshot mode.
struct VScroll<Content: View>: View {
    @Environment(\.isSnapshot) private var isSnapshot
    private let showsIndicators: Bool
    private let content: Content

    init(showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    var body: some View {
        if isSnapshot {
            content.frame(maxHeight: .infinity, alignment: .top).clipped()
        } else {
            ScrollView(showsIndicators: showsIndicators) { content }
        }
    }
}

/// A TextField that renders as its placeholder text in snapshot mode
/// (offscreen AppKit text fields draw as focus artifacts).
struct SnapshotSafeTextField: View {
    @Environment(\.isSnapshot) private var isSnapshot
    let placeholder: String
    @Binding var text: String
    var font: Font = .bodySm

    var body: some View {
        if isSnapshot {
            Text(placeholder).font(font)
                .foregroundStyle(Theme.onSurfaceVariant.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(font)
        }
    }
}
