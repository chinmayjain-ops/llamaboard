# Llamaboard — GitHub Beta 1 Launch Guide

Everything you need to publish this repo well, in order. Budget ~45 minutes for
steps 1–6 and do step 7 (announcements) when you can watch the thread for a few hours.

---

## 0. What's already prepared in this repo

| File | Purpose |
|---|---|
| `README.md` | The landing page — hero, comparison table, confirmed/unconfirmed lists, quick start, roadmap, contributor pitch |
| `LICENSE` | MIT, in your name (see §2 for why MIT) |
| `.gitignore` | Excludes `.build/`, `.gguf` models, `.DS_Store`, tooling output |
| `CONTRIBUTING.md` | Dev setup, PR checklist, good-first-areas |
| `docs/RELEASE-NOTES-beta1.md` | Paste into the GitHub Release description |
| `docs/screenshots/` | Six app screenshots the README embeds (incl. a live download in progress) |
| `PRD.md` | The product spec — committing it publicly is a feature: contributors see exactly where the project is going |

## 1. Pre-flight checks (5 min)

```bash
cd "/Volumes/CN WD 1TB/Documents/Chinmay/Projects/Llama App"

# Everything builds and passes
swift build && swift run llamaboard-tests

# Nothing sensitive or oversized is about to be committed
grep -ri "api[_-]key\|token\|password" Sources/ --include="*.swift" | grep -v "API_KEY\"\] \|apiKey\|OPENAI"   # expect no real secrets
du -sh docs/screenshots Design                       # should be ~4 MB total
```

Also decide the **repo name** now: `llamaboard` (lowercase) is the convention. Check
it's free at github.com/new. If "Llamaboard" is taken or you want to re-brand later,
renaming a repo redirects old links, so this isn't irreversible.

## 2. License — use MIT (already in the repo)

Recommendation: **MIT.** Reasons:

- **Ecosystem match.** llama.cpp itself is MIT; Jan, and most tools in this space are
  MIT/Apache. Contributors in this community expect permissive.
- **Maximum adoption.** Homebrew formulas, corporate users, and packagers integrate
  MIT code without legal review friction. For a project whose growth strategy is
  "become the default llama.cpp front end," friction kills.
- **Simple.** One page, universally understood.

Alternatives, if your priorities differ:

| License | Choose it if… | Cost |
|---|---|---|
| **Apache-2.0** | You want an explicit patent grant (more corporate-defensive) | Slightly heavier; contributor sign-off culture |
| **AGPL-3.0** | You want to prevent closed-source forks/SaaS wrapping | Meaningfully reduces adoption and contributions; some companies ban AGPL outright |

For a community-driven beta, MIT is the clear call. If you later add a hosted
service, you can dual-license new components — you can't easily go the other way.

## 3. Create and push the repo (10 min)

```bash
cd "/Volumes/CN WD 1TB/Documents/Chinmay/Projects/Llama App"

git init
git add .
git status          # review the list — no .gguf, no .build/, no graphify-out/
git commit -m "Llamaboard beta 1: native macOS front end for llama.cpp"

# With GitHub CLI (easiest):
gh repo create llamaboard --public --source . --push \
  --description "Native macOS front end for llama.cpp — model management, per-model settings, and chat. SwiftUI, no Electron."

# Or manually: create the repo on github.com/new (public, NO auto-README/license —
# you have them), then:
# git remote add origin git@github.com:<you>/llamaboard.git
# git branch -M main && git push -u origin main
```

## 4. Repository settings (10 min)

On github.com → your repo → **Settings**, and the **About** gear on the repo page:

1. **About / description:** same one-liner as above.
2. **Topics** (this is your #1 discovery lever — searches and the topic pages):
   `llama-cpp` `llm` `local-llm` `macos` `swiftui` `gguf` `apple-silicon`
   `llama` `ai` `machine-learning` `metal` `openai-api`
3. **Social preview image** (Settings → General → Social preview): upload
   `docs/screenshots/chat-live.png`. Links shared on X/Discord/Reddit show this
   image — it does more for click-through than anything else.
4. **Features:** enable **Discussions** (critical for "community-driven" — questions
   go there, bugs go to Issues) and **Issues**. Disable Wiki and Projects for now
   (empty sections look abandoned).
5. **Labels** (Issues → Labels): add `good first issue` 🟢, `help wanted`,
   `hardware-report`, `beta-feedback`, `discover`, `bench`, `companion-apps`.

## 5. Seed the community surface (10 min)

Empty repos don't get engagement; seeded ones do.

1. **Create 4–6 real issues yourself** from the "not confirmed" list, e.g.:
   - `[help wanted] Hub search/browse for Discover (paste-to-download already ships)` — link the PRD section
   - `[good first issue] Add a companion app to the App Control registry`
   - `[good first issue] Tighten the fits-check KV estimate for sliding-window models (Gemma)`
   - `[hardware-report] Post your Mac + model + tokens/sec here` (pin this one)
   - `Chat persistence (SQLite)` — labeled `help wanted`
2. **Open one pinned Discussion:** "What should beta 2 prioritize?" with the roadmap
   options as a poll. People love voting; voters become watchers.
3. **Issue templates** (optional but nice): add `.github/ISSUE_TEMPLATE/bug.yml`
   asking for macOS version, chip, RAM, llama.cpp version, and the model used —
   you'll need those on every bug anyway.

## 6. Tag and publish the release (5 min)

```bash
git tag v0.1.0-beta.1
git push origin v0.1.0-beta.1

gh release create v0.1.0-beta.1 \
  --title "Llamaboard v0.1.0-beta.1 — First Light" \
  --notes-file docs/RELEASE-NOTES-beta1.md \
  --prerelease
```

(Or on the web: Releases → Draft a new release → choose the tag → paste
`docs/RELEASE-NOTES-beta1.md` → check **"Set as a pre-release"**.)

Note: source-only release is correct for beta 1. Don't attach an unsigned `.app` —
Gatekeeper warnings on first launch create worse first impressions than
`swift run` does for this audience (they all have Homebrew anyway).

## 7. Announce it (the engagement plan)

**Where, in order of expected return:**

1. **r/LocalLLaMA** — this is your exact audience. Title formula that works there:
   *"I built a native macOS front end for llama.cpp — SwiftUI, no Electron, no
   telemetry, plain GGUF files [open source, beta]"*. Lead with 2–3 screenshots and
   the honest "what works / what doesn't" list — that transparency is rare and gets
   rewarded there. Answer every comment for the first 3–4 hours.
2. **Hacker News "Show HN"** — *"Show HN: Llamaboard – Native macOS front end for
   llama.cpp (SwiftUI, no Electron)"*. Post on a weekday morning US time. First
   comment should be yours: why you built it, the LM Studio/Ollama comparison, and
   what's honestly not done yet.
3. **llama.cpp GitHub Discussions** (show-and-tell category) — the most qualified
   audience there is; also a respectful nod to the upstream project.
4. **X/Twitter + Mastodon** — short video/GIF beats screenshots here. Record
   Library → Run → chat streaming (QuickTime screen recording, trim to ~20s).
   Tag it #localllama #llamacpp.
5. **Discord servers** (Nous Research — relevant given the Hermes integration,
   LM Studio adjacent communities are fine too; don't spam, share once in the
   appropriate channel).

**Engagement mechanics that actually work:**

- **Respond fast for the first 48 hours.** Early responsiveness converts drive-by
  commenters into watchers and contributors. This matters more than the post text.
- **The honesty angle is your differentiator.** "Measured, not estimated" telemetry
  and a public "NOT confirmed working" table are unusual — make them the story.
- **Convert feedback into labeled issues live** ("great catch — tracked in #12")
  during announcement threads. Public evidence the project listens.
- **The pinned hardware-report issue** gives every lurker a zero-effort way to
  contribute on day one; each report is also social proof.
- **Ship beta 2 within 3–6 weeks.** Nothing sustains a community like visible
  momentum; hub search/browse is the feature people will ask for most, and it's already
  scoped in the PRD.

## 8. After launch (ongoing)

- Watch → "Participating and @mentions" is not enough during launch week; use
  "All activity" temporarily.
- Add a `README` badge for the Discussions once active.
- When the first external PR lands, add the contributor to a CREDITS section —
  first-PR friction and recognition determine whether there's a second PR.
- Set up a simple CI check when convenient (GitHub Actions macOS runner:
  `swift build && swift run llamaboard-tests`) so PRs get automatic verification —
  worth doing before merging external code.

---

## Quick answers

**Which license?** MIT (§2). Already in the repo under your name.

**Binary or source release?** Source-only for beta 1 (§6).

**Version string?** `v0.1.0-beta.1`, marked pre-release. Next: `v0.1.0-beta.2`, then `v1.0.0`.

**Repo visibility?** Public from day one — the PRD explicitly commits to open-sourcing at public beta.

**Should PRD.md stay in the repo?** Yes. A public spec is a contributor magnet and keeps scope arguments short.
