import Foundation

/// A role/content pair for the OpenAI-compatible chat API.
public struct ChatTurn: Codable, Sendable {
    public let role: String
    public let content: String
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// Metrics measured client-side over one streamed response (CHAT-4).
public struct ChatMetrics: Sendable {
    public let tokens: Int
    public let tokensPerSec: Double
    public let ttft: TimeInterval
}

/// Events emitted while streaming a completion.
public enum ChatEvent: Sendable {
    case delta(String)
    case finished(ChatMetrics)
}

public enum ChatError: Error, CustomStringConvertible {
    case badStatus(Int, String)
    public var description: String {
        switch self {
        case .badStatus(let code, let body): return "Server returned \(code): \(body)"
        }
    }
}

/// Streams chat completions from llama-server's OpenAI-compatible endpoint via SSE.
public struct ChatClient: Sendable {
    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// POST /v1/chat/completions with stream:true, yielding text deltas then metrics.
    /// Sampler settings ride along per-request (SET-2's "live" class of settings).
    public func stream(messages: [ChatTurn], settings: ModelSettings) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var turns = messages
                    if !settings.systemPrompt.isEmpty && messages.first?.role != "system" {
                        turns.insert(ChatTurn(role: "system", content: settings.systemPrompt), at: 0)
                    }

                    var body: [String: Any] = [
                        "messages": turns.map { ["role": $0.role, "content": $0.content] },
                        "stream": true,
                        "temperature": settings.temperature,
                        "top_k": settings.topK,
                        "top_p": settings.topP,
                        "min_p": settings.minP,
                        "repeat_penalty": settings.repeatPenalty,
                    ]
                    if settings.maxTokens > 0 { body["max_tokens"] = settings.maxTokens }
                    if settings.seed >= 0 { body["seed"] = settings.seed }

                    var request = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    request.timeoutInterval = 600

                    let start = Date()
                    var firstTokenAt: Date?
                    var tokenCount = 0

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var errBody = ""
                        for try await line in bytes.lines { errBody += line; if errBody.count > 500 { break } }
                        throw ChatError.badStatus(http.statusCode, errBody)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String, !content.isEmpty
                        else { continue }

                        if firstTokenAt == nil { firstTokenAt = Date() }
                        tokenCount += 1  // one SSE delta ≈ one token from llama-server
                        continuation.yield(.delta(content))
                    }

                    let generationTime = firstTokenAt.map { Date().timeIntervalSince($0) } ?? 0
                    let metrics = ChatMetrics(
                        tokens: tokenCount,
                        tokensPerSec: generationTime > 0 ? Double(tokenCount) / generationTime : 0,
                        ttft: firstTokenAt.map { $0.timeIntervalSince(start) } ?? 0
                    )
                    continuation.yield(.finished(metrics))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
