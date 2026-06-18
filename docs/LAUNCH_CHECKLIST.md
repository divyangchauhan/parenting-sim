# Launch checklist — Enough (Google Play)

Status: **engineering for v1.0 is complete** (PR-00..13 merged). Everything below is
content, assets, ops, and store work — no further core code required to ship.

Legend: `[ ]` todo · `[~]` partially done / system ready · `[x]` done

---

## 1. Content & assets (the "feel" pass)
- [~] **Real audio** — replace the synthesized placeholders. System + asset slots are ready
  (`game/audio/`, `AudioManager`); swap the streams and retune `AudioManager.CUTOFF_BY_LEVEL`
  if needed. Source: a soft domestic ambient bed, a sparse piano motif, gentle UI/diegetic sfx.
- [~] **Interstitial illustrations** — `ArtSlot` placeholders exist in `Interstitial.tscn`,
  keyed by each interstitial's `art` field. Add real art (intimate, restrained, late-evening
  domestic light per GAME_DESIGN).
- [ ] **Title & key art** — finalize the game title (currently working title "Enough"), wordmark,
  and store feature graphic.
- [ ] **Final content polish** — proofread all 46 cards / 9 interstitials / 7 endings for voice
  consistency and typos. Consider 1–2 more endings if playtest wants finer differentiation.

## 2. Playtest & balance
- [ ] **Human playtest** (5–10 parents + non-parents) — does it *land emotionally*? Is the
  burnout arc felt by day 5–7? Are choices genuinely hard?
- [ ] **Ending-priority tuning** — see `docs/BALANCE.md`. Known dial: connection-based endings
  dominate by priority even when self (wellbeing) is gutted. Decide whether relentless
  self-sacrifice should surface a bittersweet ending. Re-run `tools/balance_report.tscn` after.
- [ ] **Difficulty read** — confirm a *careful* player still feels scarcity (overnight refills
  are currently generous). Tune `GameState` constants if late-week doesn't bite.
- [ ] **Length check** — confirm full playthrough lands in the 30–60 min target.

## 3. Build & signing (Android) — see `docs/BUILD_ANDROID.md`
- [ ] Install Godot 4.3 **export templates** (Editor → Manage Export Templates).
- [ ] Install **JDK 17** + **Android SDK/NDK**; point Godot's editor settings at them.
- [ ] Generate a **release keystore**; store passwords as secrets (NOT in the repo).
- [ ] Build a signed **AAB**: `godot --headless --path game --export-release "Android" ../build/enough.aab`
- [ ] Build a debug **APK** and test on a real device (touch targets, haptics, portrait,
  back button, audio routing, save/continue across app kill).
- [ ] Decide whether to bump `target_sdk` 34 → 35 (Play deadline; one line in both presets).
- [ ] Wire the GitHub release keystore secrets so `.github/workflows/android.yml` can build on tag.

## 4. Device / QA matrix
- [ ] Test on a range: small + large phones, low-end (llvmpipe-class) GPU, high-DPI.
- [ ] Verify accessibility: text-size options, reduce-motion, haptics toggle, volume sliders.
- [ ] Verify save robustness: kill mid-day, resume; finished run doesn't offer broken Continue.
- [ ] Performance: stable framerate on a budget device; reasonable battery/heat.

## 5. Store listing (Google Play Console)
- [ ] Create app; set as **paid** with price (PRD suggests ~$4.99) and target countries.
- [ ] Store text: short + full description, keywords; emphasize the emotional/narrative hook.
- [ ] Screenshots (phone) + optional 15–30s trailer. (Use real in-game frames — the look is the pitch.)
- [ ] **Data safety**: declare **no data collected / no ads / no IAP** (premium offline).
- [ ] **Content rating** questionnaire (mature themes, no violence/explicit content).
- [ ] Privacy policy URL (even for no-data apps Play requires one).
- [ ] Set up **closed testing** track → promote to production after feedback.

## 6. Pre-submit gate (must pass)
- [ ] CI green on `main` (import + unit tests + autoplay end-to-end).
- [ ] `godot --headless --path game tools/balance_report.tscn` reviewed after final content.
- [ ] Manual full playthrough on device, start → ending, with sound + haptics on.
- [ ] No console errors/leaks during a normal (non-forced-quit) playthrough.

---

## Post-launch / backlog (not blocking v1.0)
- [ ] iOS export (if Android validates).
- [ ] Localization (player text is already externalized in `game/content/`).
- [ ] Additional life-stage chapters (infant / toddler / school-age) as DLC.
