import SwiftUI
import LlamaboardKit

// MARK: - Navigation

enum Section: String, CaseIterable, Identifiable {
    case chat = "Chat"
    case library = "Library"
    case discover = "Discover"
    case apps = "Apps"
    case server = "Server"

    var id: String { rawValue }

    /// SF Symbol standing in for the mockup's Material Symbol.
    var symbol: String {
        switch self {
        case .chat:     return "bubble.left.and.bubble.right"
        case .library:  return "books.vertical"
        case .discover: return "safari"
        case .apps:     return "square.grid.2x2"
        case .server:   return "server.rack"
        }
    }
}

// MARK: - Fit badge

enum FitStatus {
    case fits, tight, tooLarge

    var label: String {
        switch self {
        case .fits:     return "Fits VRAM"
        case .tight:    return "Tight Fit"
        case .tooLarge: return "Too Large"
        }
    }
    var color: Color {
        switch self {
        case .fits:     return Theme.systemGreen
        case .tight:    return Theme.systemOrange
        case .tooLarge: return Theme.systemRed
        }
    }
}

extension LibraryModel {
    /// Icon for a library card, keyed off the model architecture.
    var cardSymbol: String {
        switch metadata?.architecture?.lowercased() ?? "" {
        case "llama": return "brain"
        case "mistral": return "wind"
        case "phi3", "phi2", "phi": return "cube.transparent"
        case "gemma", "gemma2": return "diamond"
        case "qwen2", "qwen3": return "circle.hexagongrid"
        default: return "cpu"
        }
    }
    /// Short display ID from the file name, e.g. "SMOLLM2-135M".
    var shortID: String {
        let stem = (fileName as NSString).deletingPathExtension
        return stem.split(separator: "-").prefix(3).joined(separator: "-").uppercased()
    }
}

// MARK: - Chat

struct ChatMessage: Identifiable {
    let id = UUID()
    enum Role { case user, assistant }
    let role: Role
    let text: String
    let timestamp: String
    var tokensPerSec: Double? = nil
    var tokens: Int? = nil
    var ttft: Double? = nil
}

// MARK: - Bench (sample history until SRV-11 lands)

struct BenchRun: Identifiable {
    let id = UUID()
    let model: String
    let quant: String
    let promptTS: String
    let evalTS: String
    let date: String
}

// MARK: - Server log display

extension ServerLogLine.Level {
    var tag: String {
        switch self {
        case .info: return "[INFO]"
        case .success: return "[SUCCESS]"
        case .warn: return "[WARN]"
        case .error: return "[ERROR]"
        case .debug: return "[DEBUG]"
        }
    }
    var color: Color {
        switch self {
        case .info: return Theme.primary
        case .success: return Theme.systemGreen
        case .warn: return Theme.systemOrange
        case .error: return Theme.systemRed
        case .debug: return Theme.onSurfaceVariant
        }
    }
}
