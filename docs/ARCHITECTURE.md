# Architecture — Enough

Godot 4.3, GDScript. Mobile portrait. **Data-driven** so writers add content without code.

## Project root
The Godot project lives in [`game/`](../game/) (`project.godot` there). Repo root holds docs.

## Directory layout (`game/`)
```
game/
  project.godot
  autoload/
    GameState.gd        # singleton: resources, hidden states, day index, run flags
    EventDeck.gd        # loads content, builds/serves the day's card queue
    AudioManager.gd     # music/ambient/sfx buses, ducking
    SaveManager.gd      # save/load run + settings (user://)
    Haptics.gd          # Android vibration wrapper (no-op elsewhere)
  scenes/
    Boot.tscn / Boot.gd            # splash -> main menu
    MainMenu.tscn
    DayShift.tscn / DayShift.gd    # the core loop screen (queue + HUD)
    Card.tscn / Card.gd            # a single request card + response buttons
    MetersHUD.tscn / MetersHUD.gd  # Time / Energy / Patience display
    Interstitial.tscn              # quiet narrative beat between days
    Ending.tscn
    Settings.tscn
  ui/
    theme.tres                     # global Theme (fonts, colors, button styles)
    fonts/  palette.gd             # design tokens
  content/                         # *** writers edit here ***
    events/*.json                  # card definitions (see schema below)
    interstitials/*.json
    endings.json
    schema.md                      # authoring guide
  assets/  art/  audio/
  tests/                           # GUT or simple headless test scripts
```

## Autoload singletons (global state)
- **GameState** — source of truth for a run. Holds `time`, `energy`, `patience` (visible
  resources) and a `Dictionary` of hidden states (`connection`, `security`, `partnership`,
  `wellbeing`, `standing`). Exposes `apply_effects(effects)`, `start_day()`, `end_day()`,
  signals: `resources_changed`, `state_changed`, `day_ended`, `fatigue_level_changed`.
- **EventDeck** — parses `content/events/*.json` into `EventCard` data objects, filters by
  day + conditions (required hidden-state ranges / flags), shuffles within constraints, and
  serves the day's queue. Keeps content fully separate from logic.
- **AudioManager** — buses: music, ambient, sfx. Crossfade, duck on dialogue, fatigue-driven
  low-pass when tired.
- **SaveManager** — JSON in `user://save.json`; autosaves at day boundaries; stores settings.
- **Haptics** — `Input.vibrate_handheld()` wrapper; respects settings.

## Data model
```gdscript
# EventCard (parsed from JSON)
id: String                      # "child_bedtime_story"
day_min, day_max: int           # eligible day range
source: String                  # child | partner | work | self
priority: int                   # queue ordering weight
weight_min: int                 # min cards-from-this-source guard (optional)
prompt: String                  # the need, shown on the card
conditions: Dictionary          # optional gating on hidden states / flags
responses: Array[Response]

# Response
text: String
cost: { time:int, energy:int, patience:int }
gated_by: { energy_min:int, patience_min:int }  # disabled/locked if below
effects: Dictionary             # deltas to hidden states, e.g. {connection:+2, wellbeing:-1}
sets_flags: Array[String]       # narrative flags for branching/interstitials
followup: String                # optional event id this enqueues (deferred consequence)
tone: String                    # warm | neutral | curt  (drives surfacing & art)
```

See `game/content/schema.md` (authoring guide) — the canonical, writer-facing version.

## Fatigue system
A derived **fatigue level 0–3** from current Energy+Patience. Drives:
- `Response.gated_by` enforcement (warm options lock when reserve too low).
- UI theme modulation (desaturation, animation speed, type terseness variant).
- AudioManager low-pass + tempo. Implemented as one signal `fatigue_level_changed(level)`
  that scenes subscribe to, so the "tiredness" is centrally controlled, not per-scene hacks.

## Scene flow
`Boot → MainMenu → DayShift (loop N days, Interstitial between) → Ending → MainMenu`

## Save format
One active run + settings. Day-boundary autosave. Versioned (`save_version`) for migration.

## Testing / CI
- Headless smoke: `godot --headless --path game --quit` (import + parse must not error).
- Content validation: a headless script asserts every event JSON matches schema, every
  `followup`/`set` referenced id exists, no response with impossible gating.
- Keep logic in autoloads testable without the scene tree where practical.

## Conventions
- GDScript, `snake_case` funcs/vars, `PascalCase` classes/nodes, `SCREAMING_SNAKE` consts.
- Signals over polling. No business logic in `Card.gd` — it renders data + emits intent.
- All tunable numbers in `GameState` constants or content JSON, never magic-buried in scenes.
- All player-facing text lives in content/, not in code (eases tone editing & future i18n).
