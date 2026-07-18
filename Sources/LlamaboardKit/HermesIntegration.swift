import Foundation

/// Points a Hermes install (~/.hermes/config.yaml) at Llamaboard's endpoint.
///
/// Hermes reads `model.provider` / `model.base_url` / `model.api_key` /
/// `model.default` from its config.yaml; `provider: custom` is its generic
/// OpenAI-compatible mode (it even aliases "llamacpp" to "custom" internally),
/// and it live-fetches /v1/models from the base_url for its model picker.
/// Environment variables are NOT enough — the app manages its own provider
/// config — so App Control rewrites the `model:` block before launching.
public enum HermesIntegration {

    public static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes/config.yaml")
    }

    public static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: configURL.path)
    }

    /// Rewrite only the top-level `model:` block of the YAML: set
    /// default/provider/base_url/api_key, preserving every other key and all
    /// other blocks byte-for-byte. Pure function for testability.
    public static func rewriteConfig(_ yaml: String, baseURL: String, model: String,
                                     apiKey: String = "llamaboard") -> String {
        var lines = yaml.components(separatedBy: "\n")
        let desired: [(key: String, line: String)] = [
            ("default", "  default: \(model)"),
            ("provider", "  provider: custom"),
            ("base_url", "  base_url: \(baseURL)"),
            ("api_key", "  api_key: \(apiKey)"),
        ]

        // Locate the top-level `model:` block.
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "model:" && !$0.hasPrefix(" ") }) else {
            // No model block at all — prepend one.
            let block = ["model:"] + desired.map(\.line)
            return (block + lines).joined(separator: "\n")
        }
        // Block ends at the next non-indented, non-blank, non-comment-at-column-0 line.
        var end = start + 1
        while end < lines.count {
            let line = lines[end]
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if !isBlank && !line.hasPrefix(" ") && !line.hasPrefix("\t") { break }
            end += 1
        }

        // Replace or remember-to-insert each desired key. Only match direct
        // children (exactly two-space indent) so nested maps are untouched.
        var pending = desired
        for i in (start + 1)..<end {
            let line = lines[i]
            guard line.hasPrefix("  "), !line.hasPrefix("   ") else { continue }
            let trimmed = line.dropFirst(2)
            for (j, want) in pending.enumerated() {
                if trimmed.hasPrefix("\(want.key):") {
                    lines[i] = want.line
                    pending.remove(at: j)
                    break
                }
            }
        }
        // Insert any keys the block didn't have, right after `model:`.
        for want in pending.reversed() {
            lines.insert(want.line, at: start + 1)
        }
        return lines.joined(separator: "\n")
    }

    /// Apply the rewrite to the real config, backing the original up once.
    /// Returns the backup URL if a backup was created on this call.
    @discardableResult
    public static func configure(baseURL: String, model: String) throws -> URL? {
        let url = configURL
        let original = try String(contentsOf: url, encoding: .utf8)

        var backupMade: URL? = nil
        let backup = url.appendingPathExtension("pre-llamaboard")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try original.write(to: backup, atomically: true, encoding: .utf8)
            backupMade = backup
        }

        let updated = rewriteConfig(original, baseURL: baseURL, model: model)
        if updated != original {
            try updated.write(to: url, atomically: true, encoding: .utf8)
        }
        return backupMade
    }
}
