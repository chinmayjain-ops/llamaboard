import AppKit
import SwiftUI

/// The Stitch-designed llama glass-tile logo, bundled as a resource.
/// Used for the Dock icon and the sidebar brand mark.
enum AppLogo {
    // NSImage isn't Sendable; this is only ever read from the app delegate and
    // SwiftUI bodies, so pin it to the main actor rather than opting out of
    // concurrency checking.
    @MainActor static let image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "AppLogo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

/// Sidebar/brand rendering of the logo with the app's rounded-tile treatment.
/// Falls back to the old gradient CPU tile if the resource is missing.
struct LogoMark: View {
    var size: CGFloat = 40
    var cornerRadius: CGFloat = 10

    var body: some View {
        Group {
            if let logo = AppLogo.image {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.primary, Theme.primaryContainer],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Image(systemName: "cpu.fill").foregroundStyle(Theme.onPrimary))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: Theme.primaryContainer.opacity(0.4), radius: 6, y: 1)
    }
}
