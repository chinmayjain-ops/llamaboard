# Contributing to Llamaboard

Thanks for your interest! Llamaboard is in beta and moving fast — this is the best
time to shape it.

## Ground rules

- **The PRD is the map.** [PRD.md](PRD.md) defines scope, priorities (P0/P1/P2), and
  non-goals. Features outside it start as a Discussion, not a PR.
- **Native or nothing.** SwiftUI + Foundation. No Electron, no bundled web views,
  no new heavyweight dependencies without discussion.
- **Honest numbers.** UI must not present estimates as measurements. If a value is
  a heuristic, label it.
- **No orphaned processes.** Anything that spawns a process must guarantee teardown.

## Dev setup

```bash
brew install llama.cpp        # runtime for local testing
git clone <your fork>
cd llamaboard
swift build
swift run Llamaboard          # run the app
```

Useful during development:

- `swift run llamaboard-tests` — unit tests (assert-based; works with Command Line
  Tools alone, no Xcode needed)
- `swift run llamaboard-smoke <model.gguf>` — headless end-to-end: parse → serve →
  streamed chat → teardown
- `.build/debug/Llamaboard --snapshot /tmp/snaps [--live]` — renders every screen
  to PNG (add `--live` to start a model and capture the running state)

## Before you open a PR

1. `swift build` clean, `swift run llamaboard-tests` all green.
2. If you touched the server/chat path, run the smoke test against a real GGUF
   (SmolLM2-135M is a 105 MB download and plenty).
3. If you touched UI, attach `--snapshot` renders of the affected screens.
4. Match the existing style: design tokens from `Theme.swift`, backend logic in
   `LlamaboardKit` (Foundation-only), UI in `Llamaboard`.

## Good first areas

Check issues labeled `good first issue`. Highlights:

- **Companion app registry entries** — one struct in `CompanionApps.swift` adds a
  new launchable app (detection paths + optional config writer)
- **Fits-check accuracy** — the KV-cache estimate ignores sliding-window attention;
  tighten it per-architecture with real measurements
- **More GGUF metadata** — expose more header fields in the model detail view
- **Hardware reports** — run the smoke test on your Mac and post the numbers

## Bigger projects (coordinate first via Discussions)

- Hugging Face hub search/browse for Discover (paste-to-download and the download
  manager ship in beta 1 — this adds the search UI + hub queries on top)
- Chat persistence: SQLite (GRDB) conversation store
- Bench panel: llama-bench runner + results history (SRV-11 in the PRD)
- App packaging: `.app` bundle, codesigning, Sparkle updates
