# Game Design — Enough *(working title)*

## Design philosophy
Borrow the *Papers, Please* spine: a constrained, repeated decision under pressure that, in
aggregate, makes you *feel* the thing. Mechanics stay deliberately mundane. Every system
exists to serve one feeling: **there is never enough of you to go around, and you love them
anyway.**

## The day / shift loop
1. **Day opens** with a one-line frame ("Tuesday. You slept four hours.").
2. **Cards arrive** in a queue. Each card is a *need* from one of four sources:
   - **Child** — "Daddy, watch me!", "I'm scared of the dark", "I don't want to go to school"
   - **Partner** — "Can you do bedtime? I'm wiped", "We never talk anymore"
   - **Work** — "Quick call at 6?", "The deck's due tonight"
   - **Self** — "You haven't eaten", "Your friend texted again", body/quiet needs
3. Player picks **one response** per card (2–3 options). Some cards can be **dismissed/deferred**
   (swipe away) — which is itself a choice with weight.
4. Each response **spends resources** and **nudges hidden states**.
5. The day ends when **Time runs out** or the queue empties. Unaddressed cards may have
   consequences (a deferred child need resurfaces harder).

## Resources (visible)
| Resource | Meaning | Refills |
|----------|---------|---------|
| **Time** | The clock of the day. The hard limit. | Resets each day. |
| **Energy** | Physical reserve. Low energy → fewer/worse options, slower UI. | Partial overnight; sleep choices affect it. |
| **Patience** | Emotional reserve. Low patience → warm options cost more or lock; snappy/curt options appear. | Partial overnight; some cards restore it (a hug), some drain it. |

Resources are **scarce by design.** You cannot do everything well. The game is the
arithmetic of insufficiency.

## Hidden states (never shown as numbers)
Tracked silently, surfaced only through tone, narrative beats, and ending:
- **Connection** (you ↔ child) — warmth, presence, trust.
- **Security** (child's felt safety/stability).
- **Partnership** (you ↔ partner).
- **Wellbeing** (you — your own erosion or care).
- **Standing** (work/external obligations).

No bars for these. The player feels them via the writing, not a dashboard.

## Burnout model (the core texture)
As **Energy** and **Patience** drop within and across days:
- Warm/attentive response options **cost more** Patience, or become **disabled** ("you don't
  have it in you right now"), leaving only the curt/transactional option.
- New, harsher options appear (snap, ignore, screen-time-as-babysitter).
- **UI degrades**: palette desaturates, animations slow/jitter, text gets terser, ambient
  sound dulls. The interface itself feels tired.
- Choosing self-care or accepting help restores reserve — but spends Time you "should" give
  elsewhere. Guilt is mechanical.

## Choices have no right answer
Every option trades one good for another. Reading the bedtime story (Connection↑) costs Time
and Energy you needed for the work deck (Standing↓) and your own sleep (Wellbeing↓). The
design never tells you which mattered more. Consequences are quiet and sometimes delayed.

## Interstitials (between shifts)
A short, quiet beat: a single illustrated moment + a line or two, chosen by current hidden
states. Examples: standing in a dark hallway listening to them breathe; a cold dinner; a text
you didn't answer. This is where the emotional undercurrent surfaces. No choices, or one tiny
one. Pacing: breathe.

## Endings
After the final day, compute an ending from accumulated hidden states + *how* you got there
(e.g., consistently sacrificed self vs. child). 3–5 variants, tonal not judgmental — e.g.
"They'll remember the stories." / "You held it together. Barely. That counts." / "Something
quiet went missing this week." Never "YOU WIN / Score: 8200." The ending is a mirror.

## Pacing & length
- v1.0 = **one week**, 5–7 days. ~6–10 cards/day. ~30–60 min total.
- Difficulty curve = accumulating fatigue, not enemy stats. Later days start more depleted.

## Feel / juice (where the polish lives)
- Tactile card interactions (drag, settle, weight), haptics on Android.
- Type-on dialogue with rhythm; silence used deliberately.
- Restrained, warm-then-draining color script per day.
- Sound: domestic ambient (a ticking clock, distant TV, a kettle), sparse piano motif,
  diegetic interruptions (a cry, a notification buzz).
- Everything serves tiredness and tenderness. Nothing flashy.

## Art direction (north star)
Stylized, intimate, restrained. Muted domestic palette that drains as you tire. Hand-feel
linework or soft flat shapes. Strong typography (it's a text game — type *is* the art).
Reference moods: *Florence*, *A Mortician's Tale*, Carson Ellis illustration, late-evening
domestic light. Portrait, thumb-reachable layout.
