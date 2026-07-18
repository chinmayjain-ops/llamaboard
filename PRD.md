# PRD — Llamaboard
### A lightweight, native macOS interface for llama.cpp

| | |
|---|---|
| **Status** | Draft v1.1 — open questions resolved |
| **Date** | 2026-07-10 |
| **Author** | Chinmay Jain |
| **Platform** | macOS 26 (Tahoe) and later, Apple Silicon |
| **Doc type** | Product Requirements Document |

---

## 1. Overview

Llamaboard is a native macOS application that wraps llama.cpp in a clean, Mac-first interface. It lets users download, organize, and configure GGUF models; tune inference settings per model; run and monitor the llama.cpp server; and chat with models directly — all without touching a terminal.

The product philosophy is **"llama.cpp, but Mac-native"**: expose the real power of llama.cpp (samplers, context size, GPU offload, KV-cache quantization, chat templates) through an interface built in the macOS Tahoe design language — Liquid Glass materials, floating sidebars, and SF Pro typography — rather than hiding it behind a dumbed-down wrapper or shipping a heavyweight Electron app.

### 1.1 Problem statement

Running local LLMs on a Mac today forces a choice between two bad options:

1. **Raw llama.cpp** — maximum control and performance, but entirely CLI-driven: manually downloading GGUFs, memorizing flags (`-ngl`, `-c`, `--temp`, `--cache-type-k`), managing server processes by hand, and keeping binaries up to date with a fast-moving upstream.
2. **Heavy GUI wrappers** — LM Studio (Electron, ~500 MB+, closed source), Ollama (its own model format and registry, settings buried in Modelfiles, no real GUI for configuration), Jan (Electron). These trade away performance transparency, native feel, and fine-grained control.

There is no app that is simultaneously: **native (SwiftUI), lightweight (<50 MB app, near-zero idle footprint), faithful to llama.cpp** (same flags, same performance, current upstream builds), and **beautiful by macOS standards**.

### 1.2 Product one-liner

> *The missing Mac front end for llama.cpp: manage models, tune every setting, run the server, and chat — in a native Tahoe-style app that stays out of your way.*

---

## 2. Goals and non-goals

### 2.1 Goals

- **G1 — Zero-terminal workflow.** A user can go from fresh install to chatting with a downloaded model without opening Terminal once.
- **G2 — Full-fidelity settings.** Every practically useful llama-server flag is configurable per model through the UI, with sane defaults and inline documentation.
- **G3 — First-class model management.** Search and download GGUFs from Hugging Face with a quantization picker; import existing local files; see disk usage, metadata, and estimated memory requirements at a glance.
- **G4 — Native and lightweight.** SwiftUI app, < 50 MB download (excluding llama.cpp binaries ~30 MB), < 100 MB RAM when idle, instant launch. No Electron, no bundled Chromium, no background daemons unless the user runs a model.
- **G5 — Tahoe-native design.** The app should look like Apple shipped it in macOS 26: Liquid Glass toolbar/sidebar, vibrancy, SF Pro, full light/dark support, keyboard-first navigation.
- **G6 — Always-current runtime.** Bundled, Metal-enabled llama.cpp binaries with in-app updates decoupled from app updates, so users get upstream performance work and new model-architecture support within days, not months.
- **G7 — Serve other apps.** The managed llama-server exposes its OpenAI-compatible API so IDEs, browsers, and scripts can use the running model.

### 2.2 Non-goals (v1)

- **NG1 — Not a training/fine-tuning tool.** No LoRA training, dataset management, or evaluation harnesses. (Loading existing LoRA adapters *is* in scope.)
- **NG2 — Not a multi-provider chat client.** No OpenAI/Anthropic/cloud API connections. Local llama.cpp only.
- **NG3 — Not a RAG platform.** No document ingestion, vector stores, or knowledge bases in v1. (Simple file/image attachment in chat is in scope.)
- **NG4 — Not cross-platform.** macOS on Apple Silicon only. No Intel Mac support (Metal performance and upstream focus make this a poor investment), no Windows/Linux.
- **NG5 — No accounts, no telemetry-by-default, no cloud sync.** The app works fully offline after models are downloaded.
- **NG6 — Not a llama.cpp fork.** We consume upstream release binaries unmodified; all functionality is achieved through flags and the server API.

---

## 3. Target users

**Primary persona — "The local-AI power user."** A developer, researcher, or enthusiast who already knows what llama.cpp and GGUF are. They care about tokens/sec, quantization trade-offs, and context length. They currently juggle shell scripts and hand-edited flags. They want speed and control with less friction — not a simplified abstraction.

**Secondary persona — "The tinkering developer."** Uses local models as an OpenAI-API-compatible backend for coding tools (Zed, Continue, aider) or their own apps. Primarily needs reliable server lifecycle management, endpoint visibility, and quick model switching. May rarely open the chat view.

**Explicitly not designing for (v1):** non-technical consumers who don't know what a model is. The UI should still be approachable, but when a trade-off arises between simplicity and control, control wins.

---

## 4. Competitive landscape

| | Llamaboard | LM Studio | Ollama | Jan |
|---|---|---|---|---|
| Native macOS UI | ✅ SwiftUI | ❌ Electron | ⚠️ Minimal menu bar + CLI | ❌ Electron |
| App footprint | < 100 MB | ~600 MB | ~450 MB | ~300 MB |
| Full llama.cpp settings exposure | ✅ Per-model, in UI | ⚠️ Partial | ❌ Modelfile editing | ⚠️ Partial |
| Upstream llama.cpp currency | ✅ Days (runtime updates) | ⚠️ Weeks | ⚠️ Weeks–months | ⚠️ Weeks |
| Standard GGUF file management | ✅ Plain files, user-visible | ✅ | ❌ Proprietary blob store | ✅ |
| HF model browsing | ✅ | ✅ | ❌ (own registry) | ✅ |
| OpenAI-compatible local API | ✅ (llama-server native) | ✅ | ✅ | ✅ |
| Open source | ✅ (from public beta) | ❌ | ⚠️ Partially | ✅ |

**Positioning:** Llamaboard wins on *native experience + settings fidelity + upstream currency*. It does not try to beat LM Studio on breadth (no MLX runtime in v1, no plugin ecosystem) — it beats it on feel, footprint, and transparency.

---

## 5. Product principles

1. **Respect the user's machine.** No login items, no daemons, no phoning home. Models are plain GGUF files in a user-visible folder.
2. **Progressive disclosure, never amputation.** Common settings up front, everything else one click away — but *everything* is reachable. Advanced fields show the equivalent CLI flag so knowledge transfers both ways.
3. **Honest numbers.** Show real tokens/sec, real memory usage, real context consumption. Never hide performance behind spinners.
4. **The file system is the source of truth.** Deleting the app or its database never strands a model; re-importing a folder reconstructs the library.
5. **Feels like macOS 26.** Follow the Tahoe HIG. When in doubt, do what Apple's own apps (Notes, Podcasts, System Settings) do.

---

## 6. Feature requirements

Priorities: **P0** = must ship in v1.0, **P1** = fast follow (v1.x), **P2** = future consideration.

### 6.1 Model library

The library is the app's home screen: every model the user has, with status and key facts visible at a glance.

| ID | Requirement | Priority |
|---|---|---|
| LIB-1 | List all models in the managed models directory (`~/Library/Application Support/Llamaboard/Models` by default; user-relocatable, e.g. to an external drive). Auto-detect files added/removed outside the app via folder watching. | P0 |
| LIB-2 | For each model show: name, parameter count, quantization (e.g. Q4_K_M), architecture, file size, context length (from GGUF metadata), and an **estimated RAM requirement** for the model at its configured context size. | P0 |
| LIB-3 | Read GGUF metadata (architecture, tokenizer, embedded chat template, training context) directly from the file header without loading the model. | P0 |
| LIB-4 | Import existing GGUF files or folders via drag-and-drop onto the window/Dock icon, an Open panel, or "Add folder to library" (reference in place — no forced copy). Multi-part GGUFs (`-00001-of-0000N`) are treated as one model. | P0 |
| LIB-5 | Model actions: rename (display name), reveal in Finder, delete (with confirmation and freed-space figure), duplicate settings profile, copy file path. | P0 |
| LIB-6 | Sort and filter: by name, size, last used, parameter count, quantization; free-text search. | P0 |
| LIB-7 | A storage summary (total disk used by models, per-model breakdown) with quick delete access. | P1 |
| LIB-8 | "Fits check" badge: green/yellow/red indicator for whether the model + configured context fits in this Mac's unified memory, with explanation on hover. | P1 |
| LIB-9 | Support for auxiliary files attached to a model: multimodal projector files (mmproj) and LoRA adapters, associated via the model's settings. | P1 |

### 6.2 Model discovery & download (Hugging Face)

| ID | Requirement | Priority |
|---|---|---|
| DL-1 | Built-in search of Hugging Face for GGUF repositories (HF public API; no account required for public models). Results show downloads, likes, last-updated, and gated/licensed status. | P0 |
| DL-2 | **Quantization picker**: when a repo contains multiple GGUF quants, present them as a list with file size and estimated RAM, and a recommendation ("Q4_K_M — best quality that fits comfortably in your 32 GB") based on the machine's memory. | P0 |
| DL-3 | Download manager: parallel chunked downloads, pause/resume, resume after app relaunch or network failure, checksum verification against HF metadata, progress in the UI and Dock icon. | P0 |
| DL-4 | Handle multi-part GGUF downloads as a single logical download. | P0 |
| DL-5 | Optional HF token (stored in Keychain) for gated/private models. Clear error path when a model requires license acceptance: deep-link to the repo page. | P1 |
| DL-6 | Curated "Staff picks" starter list (5–10 known-good models across sizes, e.g. small/medium/large general chat + a coding model) shown on first launch when the library is empty. Static JSON, remotely updatable. | P1 |
| DL-7 | Paste a Hugging Face URL (repo or direct file) anywhere in the app to trigger the download flow. | P1 |

### 6.3 Per-model settings & presets

This is the app's core differentiator. Every model has a **settings profile** persisted independently of the model file.

**Structure:**
- Each model has one **active profile**; users can create named profiles per model (e.g. "Creative", "Deterministic", "Long context") and switch between them.
- Every setting shows: a human explanation, its default, and the equivalent llama.cpp flag (e.g. *"GPU layers — how many layers to offload to Metal. `-ngl`"*).
- Settings are grouped with progressive disclosure: **Common** (always visible) → **Sampling**, **Memory & performance**, **Chat template**, **Server** (collapsible sections).
- Any changed-from-default setting gets a visible marker and one-click reset (mirroring Xcode build settings / System Settings conventions).

**Settings coverage (P0 unless marked):**

| Group | Settings |
|---|---|
| **Common** | Context size (`-c`, with slider snapping to 2k/4k/8k/…/max-from-metadata and RAM impact preview), temperature (`--temp`), system prompt, GPU layers (`-ngl`, default: all) |
| **Sampling** | top-k, top-p, min-p, typical-p, repeat penalty + range, presence/frequency penalty, DRY sampler (P1), XTC (P1), Mirostat mode/tau/eta, seed, max tokens to generate, grammar/JSON-schema constraint (P1) |
| **Memory & performance** | Threads (`-t`), batch/ubatch size, flash attention toggle, KV cache type K/V (f16/q8_0/q4_0) with RAM savings preview, mlock, mmap toggle, keep-model-loaded idle timeout |
| **Chat template** | Use embedded GGUF template (default) / choose from llama.cpp's built-in template list / custom Jinja template editor with validation and live preview against a sample conversation |
| **Server** | Port (global default, per-model override), API key requirement toggle, parallel slots (`--parallel`), continuous batching, LoRA adapter selection (P1), mmproj selection for multimodal (P1) |
| **Escape hatch** | "Additional arguments" free-text field appended verbatim to the llama-server invocation — guarantees no upstream flag is ever unreachable | 

**Additional requirements:**

| ID | Requirement | Priority |
|---|---|---|
| SET-1 | Profiles are stored as human-readable JSON in Application Support; exportable/importable as files for sharing. | P0 |
| SET-2 | Changing a setting while the model is running shows a "Restart to apply" affordance for server-level flags; sampler-level settings apply live to the next chat request (sent per-request via the API) without restart. The UI clearly distinguishes the two classes. | P0 |
| SET-3 | Validation with inline errors before launch (e.g. context size exceeding training context → warning; port collision → error with fix suggestion). | P0 |
| SET-4 | "Copy as command" — copy the full equivalent `llama-server` command for the current profile to the clipboard. Great for debugging and for CLI-users' trust. | P1 |

### 6.4 Server & runtime management

| ID | Requirement | Priority |
|---|---|---|
| SRV-1 | Start/stop a model with one click (or ⌘R / ⌘.). The app spawns `llama-server` as a child process with flags derived from the active profile; the process is torn down when the app quits (no orphans). | P0 |
| SRV-2 | Status states surfaced in UI: *Stopped → Loading (with model-load progress) → Running → Error*. Error state surfaces the actual stderr tail with a "Copy logs" button. | P0 |
| SRV-3 | **Endpoint panel** when running: base URL (`http://localhost:PORT/v1`), copy button, curl example snippet, optional API key. One model served at a time in v1; switching models stops the current one after confirmation. | P0 |
| SRV-4 | Live telemetry while running: tokens/sec (prompt + generation), memory in use, context slots in use, request count. Lightweight sparkline history. | P0 |
| SRV-5 | Full server log viewer (searchable, follow mode, export). | P0 |
| SRV-6 | **Bundled runtime**: app ships with a current Metal build of llama.cpp (`llama-server`, `llama-cli`, `llama-bench` + required dylibs), consumed directly from upstream ggml-org GitHub releases. The in-app updater checks for new upstream releases, shows the changelog, and swaps binaries after SHA-256 checksum verification against a pinned manifest — independent of app updates. Users can pin a version or roll back one version if a regression hits. | P0 |
| SRV-7 | Power users can point a profile (or the app globally) at a custom llama.cpp binary path. Unsupported-configuration banner shown when active. | P1 |
| SRV-8 | Idle auto-stop (optional, default off): stop the server after N minutes without a request to free memory. | P1 |
| SRV-9 | Multiple models running concurrently on different ports, with aggregate memory guardrails. | P2 |
| SRV-10 | LAN exposure toggle (bind 0.0.0.0) with an explicit warning, for serving other devices on the network. Default: localhost only. | P2 |
| SRV-11 | **Bench panel**: a power-user tab in the Server section wrapping `llama-bench` — pick a model + parameter matrix (batch sizes, GPU layers, flash attention on/off, KV types), run, and get a results table (pp/tg tokens/sec) with history per runtime version, so users can quantify the impact of settings changes and runtime updates. Results exportable as Markdown/CSV. | P1 |

### 6.5 Built-in chat

A clean playground for direct use and for validating settings — not a kitchen-sink chat product.

| ID | Requirement | Priority |
|---|---|---|
| CHAT-1 | Streaming chat UI against the running model: markdown rendering (code blocks with syntax highlighting + copy button, tables, lists, math), stop generation, regenerate, edit-and-resubmit a previous user message. | P0 |
| CHAT-2 | Conversations persist locally (SQLite); sidebar list with search, rename, delete. Each conversation records which model + profile produced each response. | P0 |
| CHAT-3 | Per-conversation system prompt and sampler overrides (inherits from the model profile by default; overrides are scoped to the conversation). | P0 |
| CHAT-4 | Inline metrics per response: tokens/sec, tokens generated, time-to-first-token. Toggleable. Context-usage meter for the conversation (n of max tokens) with clear behavior when full (llama-server context shifting; UI indicates truncation point). | P0 |
| CHAT-5 | Quick model switcher within a conversation (stops/starts server as needed; a divider notes the switch point). | P1 |
| CHAT-6 | Attach text files (source code, markdown, txt) inlined into the prompt with a token-cost preview. | P1 |
| CHAT-7 | Image attachments for multimodal models with an associated mmproj file. | P1 |
| CHAT-8 | Export conversation as Markdown or JSON. | P1 |
| CHAT-9 | Prompt library: saved/pinned system prompts reusable across models. | P2 |

### 6.6 Menu bar presence

| ID | Requirement | Priority |
|---|---|---|
| MB-1 | Optional menu bar item (default on; removable in Settings): shows run state, current model, tokens/sec when active. Menu: start/stop recent models, copy endpoint URL, open main window, quit. | P1 |
| MB-2 | "Close window keeps server running" behavior — closing the main window while a model is running keeps the process alive with the menu bar item as the control surface; quitting the app stops everything (with confirmation if requests were served recently). | P1 |

### 6.7 App Control — companion app launcher

Llamaboard's endpoint is only half the story; the other half is the ecosystem of
AI apps that can consume it (G7). App Control makes Llamaboard the hub: a section
that detects companion apps on the user's Mac — **Hermes**, **OpenClaw**, and any
custom app the user adds — and launches them pre-wired to the running llama-server
endpoint, so the user never pastes a base URL by hand.

| ID | Requirement | Priority |
|---|---|---|
| APP-1 | An **Apps** section in the sidebar lists known companion apps with detection status (Ready / Not installed): GUI apps found by bundle path, CLI tools found on common install paths. Launch set at v1: Hermes, OpenClaw. The registry is data-driven so new apps are additions, not code changes. | P1 |
| APP-2 | **One-click launch.** GUI apps launch via NSWorkspace with the endpoint injected through the OpenAI-compatible environment convention (`OPENAI_BASE_URL`, `OPENAI_API_KEY`) for apps that honor it; CLI tools open in Terminal with the same variables prefixed. | P1 |
| APP-3 | Endpoint awareness: each card shows the endpoint it will hand the app; when no model is running, the section explains that apps connect to the local endpoint and offers to start the selected model first. | P1 |
| APP-4 | **Custom apps**: the user can add any `.app` bundle or executable to the launcher; entries persist and can be removed. | P1 |
| APP-5 | "Not installed" cards deep-link to the app's install page. | P2 |
| APP-6 | Running-state detection for launched apps (show "Running" instead of "Ready") and quick-quit. | P2 |

### 6.8 Onboarding & first run

| ID | Requirement | Priority |
|---|---|---|
| ON-1 | First-run flow: welcome → hardware summary ("M3 Pro, 36 GB unified memory — models up to ~24 GB will run well") → choose models folder (or accept default / point at an existing GGUF folder) → starter model suggestions (DL-6) sized to the machine. Skippable in two clicks for users who just want to import. | P0 |
| ON-2 | Empty states everywhere teach the next step (empty library → import or browse; no running model in chat → start one inline). | P0 |

---

## 7. Design & UX specification

### 7.1 Design language — macOS Tahoe

The app adopts the macOS 26 (Tahoe) design system natively, not as a skin:

- **Liquid Glass chrome.** Toolbar and sidebar use the system Liquid Glass material — translucent, refracting the content beneath, floating over the content layer with the Tahoe capsule/lens treatment. Content scrolls *under* the glass. Achieved with stock SwiftUI materials/toolbar APIs — no custom re-implementation of Apple's material.
- **Structure.** `NavigationSplitView` two-column layout: glass sidebar (sections: **Chat**, **Library**, **Discover**, **Apps**, **Server**) + content area. Inspector panel (right side, toggleable, ⌥⌘I) for model settings — mirroring Xcode/Freeform inspector conventions.
- **Typography.** SF Pro throughout; SF Mono for logs, code, endpoints, and CLI-flag captions. System Dynamic Type sizes; no custom fonts.
- **Color.** System accent color respected. Semantic colors only (labels, fills, separators) so light/dark/increased-contrast all work for free. Status colors: system green (running), orange (loading), red (error).
- **Icon.** Layered Tahoe-style app icon designed with Apple's Icon Composer treatment (specular glass layers), avoiding the "flat sticker on a squircle" look.
- **Motion.** Standard system animations and springs; model-load progress uses a determinate progress ring in the sidebar row. No gratuitous animation during token streaming (performance principle: honest numbers, smooth text).

### 7.2 Key screens

1. **Library (default tab).** Grid or list of model cards: name, quant badge, size, fits-check dot, last used. Hover reveals Run/Chat quick actions. Selecting a model opens its detail: metadata, profiles, and the settings inspector.
2. **Model detail + settings inspector.** Left: model facts (from GGUF header) and profile picker. Right inspector: grouped settings per §6.3 with search-within-settings (like System Settings).
3. **Discover.** HF search with filter chips (size class, task, license); repo page → quant picker sheet → download. Active downloads live in a bottom bar (Safari-style downloads popover on the toolbar).
4. **Chat.** Conversation sidebar (within the tab), transcript center, composer bottom (glass field, ⌘↩ to send, model/profile chip showing what will serve the request). Per-response metrics as subtle captions.
5. **Server.** Big status header (state, model, uptime, endpoint w/ copy), telemetry sparklines, slots table, log viewer below. A **Bench** tab (SRV-11) hosts the llama-bench runner and results history.
6. **Apps (App Control).** Grid of companion-app cards (icon from the installed bundle, name, detection status chip, the endpoint it will receive) with a Launch action per card and an "Add Custom App…" affordance (§6.7).

### 7.3 Interaction standards

- Full keyboard navigation; ⌘1–4 tab switching; ⌘K global "anywhere" switcher (jump to model, conversation, or action — Raycast/Spotlight idiom).
- All destructive actions undoable or confirmed; deletions state the disk space freed.
- Drag-and-drop as a first-class path (GGUF into window = import; file into composer = attach).
- Accessibility: VoiceOver labels on all controls, Reduced Transparency fallback (glass → opaque), Reduced Motion respected, full contrast-mode support. Target: passes Accessibility Inspector audit with zero critical issues.
- Localization architecture in place (String Catalogs); English-only at launch.

---

## 8. Technical architecture

### 8.1 Stack

- **App:** Swift 6 / SwiftUI, macOS 26 SDK, deployment target macOS 26.0. AppKit interop only where SwiftUI has gaps (e.g., advanced text view for the log viewer).
- **Persistence:** SQLite (via GRDB or SwiftData) for conversations and settings profiles; JSON export format for profiles. Models directory watched with FSEvents/DispatchSource.
- **GGUF metadata:** small native Swift reader for the GGUF header (magic, KV pairs, tensor summary) — no model load required, no llama.cpp dependency for inspection.
- **Runtime integration:** `llama-server` run as a supervised child `Process` per model. All inference traffic over its OpenAI-compatible HTTP API on localhost (loopback only) — the app is a client of the same API it advertises to third parties, guaranteeing endpoint parity. stdout/stderr piped to ring buffer + on-disk rotating log.
- **Downloads:** `URLSession` background-capable download tasks with range-resume; HF Hub REST API for search/metadata.
- **Updates:** Sparkle (or TUF-style signed manifest) for app updates. Runtime updates consume upstream ggml-org macOS release binaries directly (fastest path to upstream currency); we publish a small signed manifest (release tag + SHA-256 checksums) that gates which upstream releases the updater will install, after an automated smoke test (launch server, run a completion) passes.

### 8.2 Sandboxing & distribution

- **Distribution: Developer ID + notarization, outside the Mac App Store** (v1). Rationale: spawning downloaded/updated `llama-server` binaries conflicts with MAS sandbox rules; runtime updatability (G6) is a core requirement. MAS build with a fixed bundled runtime is a P2 exploration.
- Hardened runtime on the app; binaries bundled at build time are signed with our Developer ID. Runtime-updated binaries come from upstream ggml-org releases as-is: integrity is enforced via SHA-256 pinning in our signed manifest, quarantine attributes are handled on install, and the app's entitlements permit launching them as child processes (a consequence of the Developer-ID-outside-MAS distribution choice).
- Security-scoped bookmarks for user-chosen model folders.
- Network: outbound to huggingface.co/CDN + GitHub releases (runtime updates) only; the server binds to 127.0.0.1 by default (SRV-10 gate for LAN).

### 8.3 Process & failure model

- The app owns the server lifecycle: launch → readiness poll (`/health`) → running; watchdog restarts on crash (max 2 auto-retries, then error state with logs).
- App quit / crash: `llama-server` is in the app's process group and receives SIGTERM; a stale-PID check at launch cleans up any orphan from a hard crash.
- Out-of-memory protection: pre-launch fits-check warning (LIB-8); if the process is jetsam-killed, error state explains the memory cause and suggests fixes (smaller quant, lower context, KV-cache quantization).

---

## 9. Non-functional requirements

| Area | Requirement |
|---|---|
| App size | ≤ 50 MB app + ≤ 45 MB bundled runtime (`llama-server`, `llama-cli`, `llama-bench` share dylibs) |
| Launch time | Cold launch to interactive library < 1 s on M1 |
| Idle footprint | < 100 MB RAM, ~0% CPU with no model running |
| Inference overhead | Chat UI adds < 5 ms latency vs. curl against the same server; UI stays 60/120 fps during streaming |
| Reliability | No orphaned processes ever; downloads survive relaunch; profile data never lost on crash (WAL) |
| Privacy | Zero data leaves the machine except HF/GitHub requests the user initiates. **v1.0 ships with no analytics or crash reporting at all**; product feedback comes from the beta cohort. Any future telemetry would be strictly opt-in and re-evaluated post-1.0. |
| Compatibility | Every model architecture the bundled llama.cpp release supports; graceful "unsupported architecture — update runtime?" error otherwise |

---

## 10. Release plan

### Milestone 1 — Private alpha (~6 weeks)
Library (import, metadata, list), per-model settings for the Common + Sampling + Memory groups, server start/stop with logs, minimal chat (streaming, markdown, persistence). Bundled runtime, no updater.

### Milestone 2 — Public beta (~+6 weeks)
HF Discover + download manager, quantization picker with recommendations, settings profiles + export, chat template editor, telemetry panel, onboarding flow, runtime updater, fits-check badges. **Repository open-sourced at this milestone** (license selected, contribution guidelines, issue templates, public runtime-update manifest).

### Milestone 3 — v1.0 (~+4 weeks)
Menu bar item, Bench panel (SRV-11), **App Control launcher (APP-1..4)**, per-conversation overrides, "Copy as command", file attachments, polish pass (accessibility audit, Reduced Transparency, keyboard map), docs/website, notarized distribution + Sparkle updates.

### Post-1.0 candidates (prioritized by beta feedback)
Multimodal (mmproj) & LoRA UI · multiple concurrent models · LAN serving · grammar/JSON-schema builder · MLX runtime as a second backend · prompt library · MAS edition.

---

## 11. Success metrics

- **Activation:** ≥ 70% of first-launch users reach a first successful chat response within 15 minutes. With no in-app analytics (see §9 Privacy), measured via the public beta cohort: structured feedback surveys and moderated first-run sessions.
- **Retention:** ≥ 40% of activated beta users report running a model in week 4 (beta survey; GitHub issue/discussion activity as a secondary signal once open-sourced).
- **Performance parity:** tokens/sec within 2% of bare `llama-server` with identical flags (benchmarked per release).
- **Currency:** new llama.cpp release → runtime update shipped in ≤ 7 days, tracked publicly.
- **Quality bar:** crash-free sessions ≥ 99.5%; zero P0 "orphan process" or "lost model file" bugs post-1.0.

---

## 12. Risks & mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| llama.cpp upstream churn (flag renames, server API changes) | Runtime updates break profiles | Flag-mapping layer versioned per runtime release; CI smoke test (launch server, run completion) against each upstream release before publishing an update; user can pin/roll back runtime |
| Tahoe Liquid Glass APIs still maturing | UI rework mid-development | Use only stock materials/toolbar APIs; no custom glass re-implementations |
| HF API rate limits / gated-model friction | Broken Discover experience | Cache search results; clear gated-model handoff to browser; Discover degrades to URL-paste + local import, which never depends on HF |
| Memory misjudgment → system-wide pressure/freeze | User blames the app | Conservative fits-check defaults, pre-launch warnings, jetsam-aware error messaging, idle auto-stop |
| Scope creep toward "LM Studio clone" | Loses the lightweight identity | Non-goals section enforced; every feature must serve the manage → tune → run → chat loop |
| One-person/small-team maintenance load | Stalls post-launch | Open-sourcing at public beta to attract contributors early; runtime updater decouples the fastest-moving dependency from app releases |
| Upstream release binaries lack our signature / could change packaging | Broken or blocked runtime updates | SHA-256 pinning via our signed manifest + automated smoke test gate before a release is offered; if upstream packaging breaks, the updater simply doesn't offer that release and users stay on the last good version (fallback option: switch to own CI builds without app changes, since the manifest abstracts the source) |

---

## 13. Resolved decisions

Formerly open questions, resolved 2026-07-10:

1. **Name & branding** — **Llamaboard** confirmed as the product name.
2. **Open-source timing** — **at public beta** (Milestone 2), to attract contributors and build trust before 1.0.
3. **Analytics** — **1.0 ships with none.** Product signal comes from the beta cohort and, post-open-sourcing, GitHub activity. Reflected in §9 (Privacy) and §11 (metrics).
4. **Runtime update channel** — **consume upstream ggml-org release binaries directly** for the fastest upstream currency; integrity via our signed SHA-256 manifest with a smoke-test gate (§8.1, §8.2, §12). The manifest abstraction keeps a switch to own CI builds available as a fallback.
5. **Runtime bundle contents** — **ship `llama-cli` and `llama-bench` alongside `llama-server`**, powering a Bench panel in the Server section (SRV-11, P1, lands in Milestone 3).
