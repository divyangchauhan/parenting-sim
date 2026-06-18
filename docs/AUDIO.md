# Audio (PR-10)

Restrained, domestic, tired-and-tender audio. Sound serves the same feeling as
the rest of the game (see `GAME_DESIGN.md` — "Feel / juice", "Burnout model"):
a quiet house, a sparse motif, a few diegetic interruptions. Nothing flashy. As
the player tires, the audio **dulls** in lock-step with `FatigueFX`.

## Bus layout (`audio/default_bus_layout.tres`)

Set as the project bus layout via `project.godot` →
`audio/buses/default_bus_layout`.

```
Master            (AudioEffectCompressor — gentle glue)
  ├─ Music        (AudioEffectLowPassFilter — fatigue dulling)
  ├─ Ambient      (AudioEffectLowPassFilter — fatigue dulling)
  └─ SFX          (no filter — diegetic cues stay crisp/legible through the dull)
```

`AudioManager` resolves these buses **by name** on `_ready` (robust to
reordering) and falls back to Master if a child bus is missing.

## AudioManager API

Pure, device-free mappings (unit-tested in `tests/test_audio.gd`, like
`FatigueFX.params_for_level`):

- `static cutoff_for_level(level) -> float` — low-pass cutoff (Hz) per fatigue
  level. Monotone **non-increasing**: `[20000, 9000, 3800, 1200]`.
- `static volume_sag_for_level(level) -> float` — extra dB sag (≤ 0) on
  Music+Ambient as the house quiets: `[0, -1.5, -3.5, -6.0]`.
- `static linear_volume_to_db(linear) -> float` — 0..1 → dB, with `0` → hard
  mute (`-80 dB`) and `1` → `0 dB`.

Volume (0..1 linear, consumed by `SaveManager`):
`set_master_volume`, `set_music_volume` (also tracks Ambient — there is no
separate ambient slider), `set_ambient_volume`, `set_sfx_volume`.

Playback: `play_sfx(name, db=0)`, `play_music(stream|path, fade)`,
`play_ambient(stream|path, fade)`, `stop_music(fade)`, `stop_ambient(fade)`,
plus conveniences `play_menu_music`, `play_room_ambient`. Music/ambient swaps
crossfade via tweens; SFX use a 6-voice round-robin pool so rapid taps never
choke.

Ducking: `duck(amount_db, time)` / `release_duck(time)` — lowers Music+Ambient
briefly under a beat (used at the day boundary). Base volume + fatigue sag +
duck **compose** so none clobbers another.

Fatigue dulling: connects to `GameState.fatigue_level_changed` and tweens the
Music+Ambient low-pass cutoff + sag toward the level's target over ~1.2 s.

### Headless safety

Under `--headless` the audio driver is the Dummy driver, so play calls are
harmless no-ops. On top of that everything is guarded: a missing stream, an
absent `SaveManager`, or an unresolved bus is always a silent no-op — never a
crash and never a block, so AUTOPLAY/CI run cleanly. Autoloads are resolved with
`get_node_or_null` for bare-instance testability.

(The only residual is a cosmetic "resources still in use at exit" line after a
full autoplay run that exits while the menu motif is still playing — exit code
stays 0; it sits alongside the engine's pre-existing leaked-instance warning.)

## Wiring

- **Card**: `card_settle` on present; a distant `notify_buzz` for `work` cards,
  a faint `child_cue` for `child` cards. Response press → `ui_tap` +
  `Haptics.light()`, plus a `confirm` (warm/neutral) or flatter `negative_tick`
  (curt). Defer → `ui_tap` + light haptic.
- **DayShift**: `play_room_ambient()` (room-tone + faint clock) on shift start
  (idempotent across days); at the day boundary `Haptics.medium()` + a brief
  duck; interstitial plays the piano motif (stopped after); ending fades the bed
  out and brings the motif up.
- **MainMenu**: faint room bed + piano motif (slow fade in); fades out + a tap
  on entering the day.
- All gated by the volume settings (they route through the buses); haptics gated
  by `Haptics.enabled` (driven by the haptics setting).

## Placeholder content — FUTURE REAL-AUDIO PASS

**There is no audio designer and no real foley/music.** Every `.wav` under
`audio/` is **synthesized procedurally** by `tools/make_audio.gd` (re-runnable
headless: `godot --headless --path game --script tools/make_audio.gd`) — soft
sines/triangles, low-passed noise, a few additive partials. They are
deliberately subtle: they *evoke*, they don't impress. This mirrors how the art
PR shipped real fonts but kept interstitial illustration as placeholder.

Generated assets (16-bit PCM mono):

| File | Role |
| --- | --- |
| `audio/sfx/ui_tap.wav` | soft UI tap |
| `audio/sfx/card_settle.wav` | gentle card-settle on present |
| `audio/sfx/confirm.wav` | quiet warm/neutral confirm |
| `audio/sfx/negative_tick.wav` | flatter, drier curt tick |
| `audio/sfx/notify_buzz.wav` | distant work "ping" / phone buzz |
| `audio/sfx/child_cue.wav` | faint, non-realistic child cue (a lilt, not a cry) |
| `audio/ambient/room_tone.wav` | low room-tone/drone **loop** |
| `audio/ambient/clock_tick.wav` | faint ticking-clock **loop** |
| `audio/ambient/piano_motif.wav` | sparse pentatonic piano-ish motif |

**A future content pass should replace each `.wav` above with real, recorded /
composed audio** (and may retune `CUTOFF_BY_LEVEL` / `VOLUME_SAG_DB_BY_LEVEL` to
taste). The bus layout and `AudioManager` should not need to change — only the
streams. Keep the loop flags on the two ambient beds.
