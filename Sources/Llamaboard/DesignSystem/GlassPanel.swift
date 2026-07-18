import SwiftUI

/// The core "Liquid Glass" surface: a translucent material with a hairline white
/// border and inner highlight, sitting over the dark window background. This is the
/// native equivalent of the mockup's `backdrop-blur` + `rgba(255,255,255,x)` panels.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 16
    var fill: Color = Theme.glassFill
    var strokeOpacity: Double = 0.15

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), .clear],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .blendMode(.overlay)
            )
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 16,
                    fill: Color = Theme.glassFill,
                    strokeOpacity: Double = 0.15) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, fill: fill, strokeOpacity: strokeOpacity))
    }
}

// MARK: - Small shared building blocks

/// Uppercase monospaced caption used for section headers and data labels.
struct MonoLabel: View {
    let text: String
    var color: Color = Theme.onSurfaceVariant
    init(_ text: String, color: Color = Theme.onSurfaceVariant) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text.uppercased())
            .font(.monoLabel)
            .tracking(0.6)
            .foregroundStyle(color)
    }
}

/// A rounded status chip with a leading dot, e.g. "Fits VRAM" / "Tight Fit".
struct StatusChip: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text.uppercased())
                .font(.monoLabel)
                .tracking(0.4)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1))
    }
}

/// The primary "vibrant accent" pill button (Start Model, Download & Install…).
struct AccentButton: View {
    let title: String
    var systemImage: String? = nil
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(.bodyMd.weight(.semibold))
            }
            .foregroundStyle(Theme.onPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.primary, in: Capsule())
            .shadow(color: Theme.primary.opacity(0.35), radius: 12, y: 2)
        }
        .buttonStyle(.plain)
    }
}

/// A labelled statistic value pair used across Library / Discover cards.
struct StatField: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.onSurface
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            MonoLabel(label, color: Theme.onSurfaceVariant.opacity(0.7))
            Text(value).font(.monoData).foregroundStyle(valueColor)
        }
    }
}
