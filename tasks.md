# Task Board — Enough

Project managed as a sequence of PRs. Update status here as work moves.

**Status legend:** `📋 Not started` · `🔨 In progress` · `👀 In review` · `✅ Done` · `🚫 Blocked`

Each PR is a branch `pr/NN-slug` merged to `main`. Keep PRs small and verifiable
(`godot --headless --path game --quit` must pass; content PRs must pass the validator).

| PR | Title | Status | Depends on | Notes |
|----|-------|--------|-----------|-------|
| 00 | Repo scaffold + docs + Godot project + .gitignore | ✅ | — | Done. Boots headless exit 0. Pushed to `main`. |
| 01 | Core data model + GameState autoload | ✅ | 00 | Done + tested headless. Merged. |
| 02 | Content schema + EventDeck loader + sample events | ✅ | 01 | Done. EventDeck service + validator + 11 cards / 2 interstitials / 4 endings. Merged. |
| 03 | DayShift loop + MetersHUD | ✅ | 01,02 | Done (with PR-04). Queue/clock/day lifecycle/followup/defer. AUTOPLAY harness plays 7 days e2e. Merged. |
| 04 | Card scene + response/choice system | ✅ | 03 | Done with PR-03 on one branch. Card renders + gates responses, emits chosen/deferred. Merged. |
| 05 | Fatigue/burnout system | ✅ | 04 | Done. FatigueFX (desaturation+dim+vignette shader, anim slowdown, terser microcopy), HUD kept readable on a higher CanvasLayer, stress-autoplay reaches L2, unit + e2e tested. |
| 06 | Interstitial narrative beats | ✅ | 03 | Done (with PR-07). Type-on reveal, state-selected, unified day flow. Merged. |
| 07 | Endings | ✅ | 03 | Done with PR-06. Ending screen (no score, tonal), select_ending routing, autoplay traverses to ending. Merged. |
| 08 | Shell: MainMenu, Settings, Pause, SaveManager | ✅ | 01 | Done. Menu/continue/new, settings (volume/haptics/text-size/reduce-motion), pause, autosave at day boundary. Save tests pass. Merged. |
| 09 | Art direction: Theme, palette, fonts, typography | ✅ | 04 | Done. Lora+Inter (OFL), warm paper theme, per-day color script, layout fixes; verified by screenshot (fresh + L3 burnout look). Merged. |
| 10 | Audio + Haptics | ✅ | 04 | Done. AudioManager (Master/Music/Ambient/SFX buses, fatigue low-pass + volume sag, ducking, SFX pool), synthesized placeholder sfx/ambient/piano (tools/make_audio.gd, docs/AUDIO.md), haptics wired. Headless-safe. Merged. |
| 11 | Android export preset + build pipeline | ✅ | 03 | Done. export_presets.cfg (AAB + debug APK), com.divyangchauhan.enough, min API 24 / target 34, arm64+armv7, VIBRATE only; adaptive icons from SVG; android.yml CI; docs/BUILD_ANDROID.md. Preset recognized (template/SDK gate only). Merged. |
| 12 | Content: full week (~40–60 cards) + interstitials + endings | ✅ | 02,06,07 | Done. 46 cards (child 22/partner 9/self 8/work 7), 9 interstitials, 7 endings, 5 followup chains. Stress play reaches L3. Merged. |
| 13 | Polish / playtest / balancing pass | ✅ | all | Done. Pause-icon polish, balance harness (tools/balance_report) + docs/BALANCE.md validating the emotional arithmetic across warm/curt/balanced/defer playstyles, FEATURES reconciled. Merged. |

## Milestones
- **M1 — Vertical slice (feel test):** 00–05 + minimal content. One day plays, fatigue felt.
- **M2 — Full loop:** + 06, 07, 08. A whole week playable start→ending with save.
- **M3 — Polished build:** + 09, 10, 11. Looks/sounds/ships on Android.
- **M4 — v1.0:** + 12, 13. Full content, balanced, playtested, store-ready.

## Changelog
- 2026-06-17: Project kicked off. Engine decision: **Godot 4** (vs Flutter/web). Platform:
  **Android-first, premium paid, iOS optional later.** Docs (PRD, design, architecture,
  features) written. PR-00 in progress.
- 2026-06-17: **M1 (vertical slice)** done — PR-00..05. A full day plays through real scenes
  with the fatigue/burnout feel (stress autoplay verified).
- 2026-06-17: **M2 (full loop)** done — PR-06/07 (interstitials + endings + unified day flow),
  PR-08 (shell + save/continue/settings/pause), PR-12 (full week: 46 cards / 9 interstitials /
  7 endings, 5 followup chains). Full week plays start→ending; stress play reaches fatigue L3.
  Remaining: PR-09 (art/theme), PR-10 (audio/haptics), PR-11 (Android export), PR-13 (polish).
- 2026-06-18: **M3 (polished build)** done — PR-09 (theme/palette/typography/layout, verified by
  screenshot incl. L3 burnout look), PR-10 (audio system + procedural placeholders + haptics),
  PR-11 (Android export preset/icons/CI/docs). Added a Screenshot dev-QA harness. Remaining for
  v1.0: PR-13 (polish / playtest / balancing) and a future real-audio + interstitial-art pass.
- 2026-06-18: **M4 (v1.0 baseline)** done — PR-13 polish + balance validation. **All 14 PRs
  complete.** The full week plays start→ending with art, audio (placeholder), save, settings,
  fatigue arc, and is Android-export configured. Remaining before store launch are content/asset
  passes, not engineering: real audio, interstitial illustration, human playtest + ending tuning
  (see docs/BALANCE.md), and the manual Android signing/SDK steps in docs/BUILD_ANDROID.md.
