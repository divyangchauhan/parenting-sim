# Task Board — Enough

Project managed as a sequence of PRs. Update status here as work moves.

**Status legend:** `📋 Not started` · `🔨 In progress` · `👀 In review` · `✅ Done` · `🚫 Blocked`

Each PR is a branch `pr/NN-slug` merged to `main`. Keep PRs small and verifiable
(`godot --headless --path game --quit` must pass; content PRs must pass the validator).

| PR | Title | Status | Depends on | Notes |
|----|-------|--------|-----------|-------|
| 00 | Repo scaffold + docs + Godot project + .gitignore | ✅ | — | Done. Boots headless exit 0. Pushed to `main`. |
| 01 | Core data model + GameState autoload | 🔨 | 00 | resources, hidden states, apply_effects, signals, constants |
| 02 | Content schema + EventDeck loader + sample events | 📋 | 01 | JSON schema, authoring guide, parser, day/condition filter, validator |
| 03 | DayShift loop + MetersHUD | 📋 | 01,02 | queue, serve cards, time clock, day start/end |
| 04 | Card scene + response/choice system | 📋 | 03 | render card, response buttons, defer, apply costs+effects |
| 05 | Fatigue/burnout system | 📋 | 04 | fatigue level, option gating, UI degradation hooks, signal |
| 06 | Interstitial narrative beats | 📋 | 03 | state-selected quiet beats between days |
| 07 | Endings | 📋 | 03 | compute from accumulated states, ending screens |
| 08 | Shell: MainMenu, Settings, Pause, SaveManager | 📋 | 01 | new/continue, settings, autosave |
| 09 | Art direction: Theme, palette, fonts, typography | 📋 | 04 | global theme.tres, design tokens, color script |
| 10 | Audio + Haptics | 📋 | 04 | AudioManager buses, ambient/motif, fatigue low-pass, vibration |
| 11 | Android export preset + build pipeline | 📋 | 03 | portrait AAB, min API 24, icons, headless CI |
| 12 | Content: full week (~40–60 cards) + interstitials + endings | 📋 | 02,06,07 | writer-led, passes validator |
| 13 | Polish / playtest / balancing pass | 📋 | all | tuning, juice, emotional read |

## Milestones
- **M1 — Vertical slice (feel test):** 00–05 + minimal content. One day plays, fatigue felt.
- **M2 — Full loop:** + 06, 07, 08. A whole week playable start→ending with save.
- **M3 — Polished build:** + 09, 10, 11. Looks/sounds/ships on Android.
- **M4 — v1.0:** + 12, 13. Full content, balanced, playtested, store-ready.

## Changelog
- 2026-06-17: Project kicked off. Engine decision: **Godot 4** (vs Flutter/web). Platform:
  **Android-first, premium paid, iOS optional later.** Docs (PRD, design, architecture,
  features) written. PR-00 in progress.
