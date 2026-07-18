# Llamaboard v0.1.0-beta.1 — "First Light"

> Paste this file's contents into the GitHub Release description when publishing.
> Mark the release as a **pre-release**.

The first public beta of **Llamaboard** — a lightweight, fully native macOS front end
for llama.cpp. SwiftUI, no Electron, no telemetry, plain GGUF files.

This beta is **source-only**: clone and `swift run Llamaboard` (see the README quick
start). A signed, notarized `.app` is planned for v1.0.

## Highlights

- 📚 **Model Library** with native GGUF header parsing (no model load needed),
  live folder watching, search, size/parameter/fit filters, and per-model
  Fits-VRAM badges
- ⬇️ **Paste-to-download** — paste the `llama serve -hf owner/repo:QUANT` command
  from any Hugging Face model page (or a bare repo ref / page URL) and the GGUF is
  resolved with llama.cpp's own quant-matching rules and downloaded into your
  library with progress, speed, ETA, and pause/resume/cancel
- 🎛 **Per-model settings profiles** (context, full sampler set, system prompt,
  GPU layers, KV-cache types, flash attention, escape-hatch args) persisted as
  human-readable JSON, with an explicit restart-to-apply notice when the running
  server disagrees with the slider
- ⚡️ **One-click llama-server lifecycle** with health checks, live logs, and
  guaranteed process teardown
- 💬 **Calm chat** — a fixed-height indicator while generating, then the full
  answer rendered once, with per-response tokens/sec, token count, and TTFT
- 📊 **Measured telemetry** — the server's actual `n_ctx` from `/props`, resident
  memory including the mmapped weights (plus app footprint), sampled live
- 🚀 **App Control** — launch companion apps against your local endpoint; Hermes
  is configured automatically (provider config written for you, original backed up)
- 🔍 Inspector with real Model / Inference / System tabs; relocatable models
  folder; custom llama-server binary override

## ✅ Confirmed working in this beta

Verified on an M4 Mac mini (16 GB), macOS 26, Homebrew llama.cpp:

- GGUF parsing (SmolLM2, Gemma; synthetic-file unit tests)
- Library scan/watch/import/delete; models-folder relocation; search + filters
- Paste-to-download end to end: HF command parsed verbatim → hub-resolved →
  downloaded with live progress → auto-imported into the Library
- Settings profiles incl. a 64K-context run verified against the server's own `/props`
- Server start/stop with zero orphaned processes across all test runs
- Chat at 289–314 t/s (SmolLM2-135M) and ~8–12 t/s (8B-class Gemma), UI responsive
  during generation
- Hermes launch + automatic endpoint configuration, inference confirmed end-to-end
- 42 unit test checks and a headless smoke test (parse → serve → chat →
  measured-telemetry assertions → teardown)

## ⚠️ Not yet working / not yet verified

- **Hub browsing/search** inside Discover — beta 2 (paste-to-download ships now)
- **Split multi-part GGUFs** are refused with a clear error — not downloadable yet
- **Bench tab shows sample data** — llama-bench integration planned
- **Chat history is not persisted** across app launches yet
- Fits-VRAM badge overestimates KV cache for sliding-window models (Gemma) — advisory
- Draft/MTP companion GGUFs can't run standalone; the server error is surfaced but
  the Library doesn't label them yet
- Custom llama-server binary path untested against a real self-compiled build;
  OpenClaw launch implemented but untested; custom-app env injection depends on the
  target app honoring `OPENAI_BASE_URL`
- Apple Silicon only; no multimodal/LoRA/multi-model/LAN/gated-repo support in this beta

## Requirements

- Apple Silicon Mac, macOS 14+
- `brew install llama.cpp`
- Swift 6 toolchain (Xcode or Command Line Tools)

## We need you

This beta ships with honest gaps and a full [PRD](../PRD.md) describing where it's
going. If you run it, please report:

1. Your hardware + the model you ran + the tokens/sec you saw
2. Whether the Fits-VRAM badge told you the truth
3. A model that paste-to-download couldn't fetch (and what you pasted)
4. Anything that surprised you (good or bad)

`good first issue` labels are waiting. See [CONTRIBUTING.md](../CONTRIBUTING.md).

**Full changelog:** first public release.
