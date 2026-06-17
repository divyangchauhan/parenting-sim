# PRD — Enough *(working title)*

## 1. Vision
A premium, short-form emotional simulation that makes the player *feel* what daily parenting
is like. We are not building a caretaking/optimization game (Tamagotchi). We are building an
experience whose mechanics — like *Papers, Please* — are mundane and repetitive on purpose,
so that the aggregate produces emotional and moral weight.

**One-line pitch:** *Papers, Please*, but the documents are your child's needs and the
stamp is your patience running out.

## 2. Goals
- Convey: relentless small decisions, finite time/energy, guilt vs. love, no right answer.
- Be **simple in scope** yet **polished enough that people pay for it** (premium, ~$4.99).
- Solo/small-team buildable in Godot 4, Android-first.
- A complete play-through in **30–60 minutes**, high replay-reflection value, not grind.

## 3. Non-goals
- No stat-min-maxing or "perfect parent" win state.
- No twitch/action mechanics, no physics, no open world.
- No live-service, ads, or microtransactions. One purchase, whole game.
- No photorealism. Stylized, restrained art.

## 4. Target player
Adults 25–45, many of them parents or parents-to-be; players who liked *Papers, Please*,
*Reigns*, *Florence*, *A Mortician's Tale*, *Cart Life*. People who buy "feel-something"
indie games.

## 5. Platforms
1. **Android** (primary) — phones, portrait, touch. Min API 24 (Android 7).
2. **iOS** (optional, post-launch if Android validates).
3. Desktop builds may be used internally for dev/playtest; not a launch target.

## 6. Core experience (the loop)
A **day = a shift.** Needs arrive as cards in a queue. You have three depleting resources:
**Time** (the day's clock), **Energy**, and **Patience**. Each card offers 2–3 responses;
each response spends resources and silently nudges hidden relationship/wellbeing states.
There is no correct answer. As Energy/Patience fall, the warm/attentive options become more
expensive or unavailable, and the UI itself frays — modeling burnout. Between days, a short
quiet narrative beat surfaces the emotional undercurrent. After the final day, an ending
reflects the accumulated *tone* of how you parented — never a score.

See [GAME_DESIGN.md](GAME_DESIGN.md) for full mechanics.

## 7. Success metrics
- **Emotional resonance** (qualitative): playtesters report recognition / being moved.
- Completion rate > 60% of starts reach an ending.
- Store rating ≥ 4.4. Refund rate < 5%.
- Wishlist→purchase and word-of-mouth (it's a "you have to play this" game).

## 8. Content scope (MVP → v1.0)
- **MVP:** one vertical slice — 1 full day, ~8 cards, meters, fatigue effect, 1 interstitial,
  1 ending stub. Proves the feel.
- **v1.0:** a **week** (5–7 days). ~40–60 authored cards. 3 life-stage flavors optional
  (infant / toddler / school-age) — start with one band, data-driven so more can be added.
  Full audio, 3–5 ending variants, menu/settings/save, Android release build.

## 9. Monetization
Premium one-time purchase on Google Play. No ads, no IAP. Possible later: paid "chapters"
(new life stages) as DLC — only if v1.0 succeeds.

## 10. Risks
- **Tone failure:** comes across preachy or bleak instead of true. → Writer-led, playtest
  emotional read early and often.
- **Too thin:** "it's just a menu." → Lean hard on polish: animation, sound, haptics, pacing.
- **Solo content load:** writing is the bottleneck. → Data-driven content pipeline so writing
  is decoupled from engineering.
