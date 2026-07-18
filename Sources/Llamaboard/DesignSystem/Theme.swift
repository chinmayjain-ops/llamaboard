import SwiftUI

/// Llamaboard design tokens, translated from the Stitch "macOS Native App Design"
/// system. Colors are dark-mode "Liquid Glass"; fonts map to native SF Pro / SF Mono
/// (the PRD's stated typography) rather than the web mockup's Inter / JetBrains Mono.
enum Theme {

    // MARK: - Surfaces
    static let background            = Color(hex: 0x10131B)
    static let surfaceContainerLowest = Color(hex: 0x0B0E16)
    static let surfaceContainerLow  = Color(hex: 0x181C23)
    static let surfaceContainer     = Color(hex: 0x1C2028)
    static let surfaceContainerHigh = Color(hex: 0x272A32)
    static let surfaceContainerHighest = Color(hex: 0x31353D)

    // MARK: - Accent
    static let primary          = Color(hex: 0xADC6FF)
    static let primaryContainer = Color(hex: 0x4B8EFF)
    static let onPrimary        = Color(hex: 0x002E69)
    static let onPrimaryContainer = Color(hex: 0x00285C)

    // MARK: - Foreground
    static let onSurface        = Color(hex: 0xE0E2ED)
    static let onSurfaceVariant = Color(hex: 0xC1C6D7)
    static let outline          = Color(hex: 0x8B90A0)
    static let outlineVariant   = Color(hex: 0x414755)

    // MARK: - System status
    static let systemGreen  = Color(hex: 0x34C759)
    static let systemOrange = Color(hex: 0xFF9500)
    static let systemRed    = Color(hex: 0xFF3B30)

    // MARK: - Glass
    static let glassFill   = Color.white.opacity(0.06)
    static let glassFillHi = Color.white.opacity(0.10)
    static let glassBorder = Color.white.opacity(0.15)

    // MARK: - Layout metrics
    static let windowMargin: CGFloat = 24
    static let gutter: CGFloat = 12
    static let lensPadding: CGFloat = 16
    static let sidebarWidth: CGFloat = 232
    static let inspectorWidth: CGFloat = 312
}

// MARK: - Typography

extension Font {
    static let headlineLg = Font.system(size: 28, weight: .bold)
    static let headlineMd = Font.system(size: 20, weight: .semibold)
    static let bodyMd     = Font.system(size: 14, weight: .regular)
    static let bodySm     = Font.system(size: 12, weight: .regular)
    static let monoData   = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let monoLabel  = Font.system(size: 10, weight: .bold, design: .monospaced)
}

// MARK: - Hex color helper

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
