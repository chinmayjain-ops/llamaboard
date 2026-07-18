import SwiftUI

/// Chat Playground — a centered transcript of user/assistant messages with inline
/// inference metrics, plus a floating glass composer capsule pinned to the bottom.
/// Streams live from the running llama-server.
struct ChatView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                VScroll {
                    VStack(spacing: 40) {
                        if app.messages.isEmpty && !app.isGenerating {
                            emptyState
                        }
                        ForEach(app.messages) { message in
                            MessageRow(message: message, modelLabel: app.runningModelName)
                        }
                        if app.isGenerating {
                            GeneratingRow(modelLabel: app.runningModelName,
                                          tokens: app.streamedTokens)
                                .id("generating")
                        }
                        if let error = app.chatError {
                            errorRow(error)
                        }
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 96)
                    .padding(.bottom, 150)
                }
                .onChange(of: app.isGenerating) {
                    // Scroll once when generation starts; the indicator has a
                    // fixed height, so nothing moves while tokens stream in.
                    if app.isGenerating {
                        withAnimation { proxy.scrollTo("generating", anchor: .bottom) }
                    }
                }
                .onChange(of: app.messages.count) {
                    if let last = app.messages.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
            Composer()
                .frame(maxWidth: 780)
                .padding(.bottom, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(Theme.onSurfaceVariant.opacity(0.3))
            Text(app.server.state.isRunning
                 ? "Model ready. Say something."
                 : "Start a model from the Library to begin chatting.")
                .font(.bodyMd).foregroundStyle(Theme.onSurfaceVariant)
        }
        .padding(.top, 120)
    }

    private func errorRow(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.systemRed)
            Text(error).font(.bodySm).foregroundStyle(Theme.systemRed)
        }
        .padding(12)
        .background(Theme.systemRed.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let modelLabel: String

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 8) {
                Text(message.text)
                    .font(.bodyMd).foregroundStyle(Theme.onSurface)
                    .multilineTextAlignment(.leading)
                    .padding(16)
                    .frame(maxWidth: 520, alignment: .leading)
                    .background(Theme.surfaceContainerHigh,
                                in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                                                           bottomTrailingRadius: 18, topTrailingRadius: 2,
                                                           style: .continuous))
                    .overlay(
                        UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                                               bottomTrailingRadius: 18, topTrailingRadius: 2, style: .continuous)
                            .strokeBorder(Theme.glassBorder, lineWidth: 1))
                MonoLabel(message.timestamp)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

        case .assistant:
            VStack(alignment: .leading, spacing: 16) {
                AssistantHeader(label: message.timestamp)
                Text(LocalizedStringKey(message.text))
                    .font(.bodyMd).foregroundStyle(Theme.onSurface)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if let tps = message.tokensPerSec {
                    HStack(spacing: 12) {
                        metric("speedometer", String(format: "%.1f t/s", tps))
                        dot
                        metric("cylinder.split.1x2", "\(message.tokens ?? 0) tokens")
                        dot
                        metric("timer", String(format: "%.2fs TTFT", message.ttft ?? 0))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.glassFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.glassBorder.opacity(0.3), lineWidth: 1))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dot: some View { Text("•").foregroundStyle(Theme.glassBorder) }

    private func metric(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Theme.primary)
            Text(text).font(.monoData).foregroundStyle(Theme.onSurfaceVariant)
        }
    }
}

/// Fixed-height indicator shown while the model generates. The full answer is
/// rendered once, when complete — no mid-stream re-layout, no jumping.
private struct GeneratingRow: View {
    let modelLabel: String
    let tokens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AssistantHeader(label: modelLabel)
            HStack(spacing: 10) {
                ProgressView().controlSize(.small).tint(Theme.primary)
                Text("Generating response…")
                    .font(.bodyMd).foregroundStyle(Theme.onSurfaceVariant)
                if tokens > 0 {
                    Text("\(tokens) tokens")
                        .font(.monoData.monospacedDigit())
                        .foregroundStyle(Theme.onSurfaceVariant.opacity(0.7))
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassPanel(cornerRadius: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AssistantHeader: View {
    let label: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain")
                .font(.system(size: 15)).foregroundStyle(Theme.onPrimary)
                .frame(width: 32, height: 32)
                .background(Theme.primary, in: Circle())
            Text(label).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.onSurface)
        }
    }
}

private struct Composer: View {
    @EnvironmentObject var app: AppState
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var ready: Bool { app.server.state.isRunning }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { } label: {
                    Image(systemName: "paperclip").font(.system(size: 16)).foregroundStyle(Theme.onSurfaceVariant)
                        .frame(width: 32, height: 32)
                }.buttonStyle(.plain)
                Group {
                    if isSnapshot {
                        Text(ready ? "Message \(app.runningModelName)…" : "Start a model to chat…")
                            .font(.bodyMd)
                            .foregroundStyle(Theme.onSurfaceVariant.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        TextField(ready ? "Message \(app.runningModelName)…" : "Start a model to chat…",
                                  text: $draft, axis: .vertical)
                            .textFieldStyle(.plain).font(.bodyMd).lineLimit(1...5)
                            .padding(.vertical, 8)
                            .focused($focused)
                            .onSubmit(send)
                            .disabled(!ready || app.isGenerating)
                    }
                }
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.onPrimary)
                        .frame(width: 36, height: 36)
                        .background(ready && !app.isGenerating ? Theme.primary : Theme.surfaceContainerHighest, in: Circle())
                }.buttonStyle(.plain)
                .disabled(!ready || app.isGenerating)
            }
            .padding(.horizontal, 8)

            HStack {
                HStack(spacing: 8) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(statusText).font(.monoLabel).foregroundStyle(Theme.onSurfaceVariant)
                }
                Spacer()
                if app.isGenerating {
                    Button { app.stopGeneration() } label: {
                        Text("Stop Generation").font(.monoLabel).foregroundStyle(Theme.systemOrange)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.top, 6)
            .overlay(Rectangle().fill(Theme.glassBorder.opacity(0.2)).frame(height: 1), alignment: .top)
        }
        .padding(8)
        .glassPanel(cornerRadius: 20, fill: Theme.glassFillHi)
        .shadow(color: Theme.primary.opacity(0.15), radius: 20)
    }

    private var statusColor: Color {
        switch app.server.state {
        case .running: return Theme.systemGreen
        case .loading: return Theme.systemOrange
        case .error: return Theme.systemRed
        case .stopped: return Theme.outlineVariant
        }
    }

    private var statusText: String {
        switch app.server.state {
        case .running(let model): return "MODEL READY: \(model.uppercased())"
        case .loading(let model): return "LOADING: \(model.uppercased())"
        case .error: return "SERVER ERROR — SEE SERVER TAB"
        case .stopped: return "NO MODEL RUNNING"
        }
    }

    private func send() {
        let text = draft
        draft = ""
        app.sendMessage(text)
    }
}
