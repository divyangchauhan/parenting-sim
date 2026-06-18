extends Node
## AudioManager — music / ambient / SFX playback over a fatigue-aware bus layout.
##
## RESTRAINED BY DESIGN (see docs/GAME_DESIGN.md "Feel / juice"). Sound serves
## tiredness and tenderness, never spectacle: a domestic bed (room-tone + a faint
## clock), a sparse piano motif, and a few diegetic cues (a soft tap, a distant
## work buzz, a faint child cue). As the player tires, the world DULLS — a
## low-pass filter closes on the Music + Ambient buses and their volume sags.
##
## PLACEHOLDER CONTENT. The .wav assets under audio/ are SYNTHESIZED placeholders
## (see tools/make_audio.gd + docs/AUDIO.md). The *system* here is real; a future
## real-audio pass should swap the streams and retune the cutoff curve only.
##
## ROUTING (audio/default_bus_layout.tres):
##   Master (compressor for glue)
##     ├─ Music    (low-pass: fatigue dulling)
##     ├─ Ambient  (low-pass: fatigue dulling)
##     └─ SFX      (stays crisp so diegetic cues read through the dulling)
##
## SAFE HEADLESS. Under --headless the audio driver is "Dummy": play calls are
## harmless no-ops and never block, but we additionally guard so a missing stream,
## absent SaveManager, or unresolved bus never crashes or hangs autoplay.

# ---------------------------------------------------------------------------
# Bus names (resolved to indices on _ready; robust if the layout is reordered)
# ---------------------------------------------------------------------------

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_AMBIENT := "Ambient"
const BUS_SFX := "SFX"

# ---------------------------------------------------------------------------
# Fatigue dulling tunables (the level -> feel curve lives here)
# ---------------------------------------------------------------------------

## Low-pass cutoff (Hz) on the Music + Ambient buses per fatigue level 0..3.
## Level 0 (fresh) is wide open; level 3 (burnt out) is heavily muffled. Mirrors
## FatigueFX's visual ramp: the world literally sounds duller as you tire.
const CUTOFF_BY_LEVEL := [20000.0, 9000.0, 3800.0, 1200.0]

## Extra volume sag (dB, <= 0) applied to Music + Ambient per fatigue level. The
## tired house gets a touch quieter as well as duller.
const VOLUME_SAG_DB_BY_LEVEL := [0.0, -1.5, -3.5, -6.0]

## Seconds to tween the cutoff / sag when the fatigue level changes — unhurried,
## so tiredness creeps in rather than snapping.
const DULL_TWEEN_TIME := 1.2

# ---------------------------------------------------------------------------
# Volume / mixing tunables
# ---------------------------------------------------------------------------

## Below this linear volume we treat the channel as fully muted (-> -80 dB) rather
## than feeding linear_to_db a near-zero (which trends to -inf).
const MUTE_THRESHOLD := 0.001
const MUTE_DB := -80.0

## Default crossfade time (seconds) for music/ambient swaps.
const DEFAULT_FADE := 1.0

## How many pooled SFX players — enough overlap that rapid taps never choke.
const SFX_VOICES := 6

# ---------------------------------------------------------------------------
# Placeholder asset table (name -> res path). Guarded: a missing file is a no-op.
# ---------------------------------------------------------------------------

const SFX_PATHS := {
	"ui_tap": "res://audio/sfx/ui_tap.wav",
	"card_settle": "res://audio/sfx/card_settle.wav",
	"confirm": "res://audio/sfx/confirm.wav",
	"negative_tick": "res://audio/sfx/negative_tick.wav",
	"notify_buzz": "res://audio/sfx/notify_buzz.wav",
	"child_cue": "res://audio/sfx/child_cue.wav",
}

const AMBIENT_ROOM_TONE := "res://audio/ambient/room_tone.wav"
const AMBIENT_CLOCK_TICK := "res://audio/ambient/clock_tick.wav"
const MUSIC_PIANO_MOTIF := "res://audio/ambient/piano_motif.wav"

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _bus_master := -1
var _bus_music := -1
var _bus_ambient := -1
var _bus_sfx := -1

## Cached low-pass effect handles (per bus) so we can sweep cutoff cheaply.
var _lp_music: AudioEffectLowPassFilter = null
var _lp_ambient: AudioEffectLowPassFilter = null

## Base (user-set) volume in dB for music/ambient, before any fatigue sag / duck.
var _music_base_db := 0.0
var _ambient_base_db := 0.0

## Current fatigue contribution, kept separate so duck + sag + base compose.
var _music_sag_db := 0.0
var _ambient_sag_db := 0.0
var _duck_db := 0.0

## Players. One each for music + ambient (looped beds), a small pool for SFX.
var _music_player: AudioStreamPlayer = null
var _ambient_player: AudioStreamPlayer = null
var _clock_player: AudioStreamPlayer = null
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_next := 0

## Loaded SFX streams cache (name -> AudioStream), lazily filled, guarded.
var _sfx_cache: Dictionary = {}

var _dull_tween: Tween = null
var _duck_tween: Tween = null

# ---------------------------------------------------------------------------
# Pure mappings (no scene-tree / AudioServer access — unit-testable)
# ---------------------------------------------------------------------------

## Map a fatigue level (clamped 0..3) to a low-pass cutoff in Hz. PURE — touches
## nothing — so tests can assert its shape (monotone non-increasing, positive,
## open at level 0) without an audio device. Mirrors FatigueFX.params_for_level.
static func cutoff_for_level(level: int) -> float:
	var i := clampi(level, 0, CUTOFF_BY_LEVEL.size() - 1)
	return float(CUTOFF_BY_LEVEL[i])


## Map a fatigue level (clamped 0..3) to the music/ambient volume sag in dB
## (<= 0). PURE. Level 0 = 0 dB (no sag).
static func volume_sag_for_level(level: int) -> float:
	var i := clampi(level, 0, VOLUME_SAG_DB_BY_LEVEL.size() - 1)
	return float(VOLUME_SAG_DB_BY_LEVEL[i])


## Convert a 0..1 linear volume to dB, treating ~0 as a hard mute (-80 dB) rather
## than letting linear_to_db run to -inf. PURE — the volume API leans on this and
## the test asserts its endpoints.
static func linear_volume_to_db(linear: float) -> float:
	var v := clampf(linear, 0.0, 1.0)
	if v <= MUTE_THRESHOLD:
		return MUTE_DB
	return linear_to_db(v)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_resolve_buses()
	_build_players()

	# React to fatigue if GameState is present (resolved dynamically so a bare
	# instance / SceneTree test that lacks the autoload simply doesn't connect).
	var gs := _game_state()
	if gs != null:
		gs.fatigue_level_changed.connect(_on_fatigue_level_changed)
		_apply_dulling(int(gs.fatigue_level()), false)


## Release stream references on teardown so nothing is "still in use at exit".
## Players are stopped and their streams (and the cache) cleared; the cached
## low-pass effects belong to the bus layout and are left alone.
func _exit_tree() -> void:
	for p in _sfx_pool:
		if p != null:
			p.stop()
			p.stream = null
	for p in [_music_player, _ambient_player, _clock_player]:
		if p != null:
			p.stop()
			p.stream = null
	_sfx_cache.clear()


## Resolve bus indices by NAME so a reordered layout still works. Caches the
## low-pass effects so the fatigue sweep is a cheap property write.
func _resolve_buses() -> void:
	_bus_master = AudioServer.get_bus_index(BUS_MASTER)
	_bus_music = AudioServer.get_bus_index(BUS_MUSIC)
	_bus_ambient = AudioServer.get_bus_index(BUS_AMBIENT)
	_bus_sfx = AudioServer.get_bus_index(BUS_SFX)

	# Master always exists; if the child buses are missing (e.g. layout not set),
	# fall back to Master so playback still routes somewhere valid.
	if _bus_master < 0:
		_bus_master = 0
	if _bus_music < 0:
		_bus_music = _bus_master
	if _bus_ambient < 0:
		_bus_ambient = _bus_master
	if _bus_sfx < 0:
		_bus_sfx = _bus_master

	_lp_music = _find_lowpass(_bus_music)
	_lp_ambient = _find_lowpass(_bus_ambient)


## First AudioEffectLowPassFilter on a bus, or null if there is none.
func _find_lowpass(bus: int) -> AudioEffectLowPassFilter:
	if bus < 0:
		return null
	for i in AudioServer.get_bus_effect_count(bus):
		var fx := AudioServer.get_bus_effect(bus, i)
		if fx is AudioEffectLowPassFilter:
			return fx as AudioEffectLowPassFilter
	return null


## Create the long-lived players. Looped beds get their own player; SFX share a
## small round-robin pool so overlapping taps never cut each other off.
func _build_players() -> void:
	_music_player = _make_player(BUS_MUSIC)
	_ambient_player = _make_player(BUS_AMBIENT)
	_clock_player = _make_player(BUS_AMBIENT)

	for i in SFX_VOICES:
		var p := _make_player(BUS_SFX)
		_sfx_pool.append(p)


func _make_player(bus_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus_name
	add_child(p)
	return p


# ---------------------------------------------------------------------------
# Volume API (consumed by SaveManager — values are 0..1 linear)
# ---------------------------------------------------------------------------

## Set the Master bus volume from a 0..1 linear value (0 -> mute).
func set_master_volume(linear: float) -> void:
	_set_bus_db(_bus_master, linear_volume_to_db(linear))


## Set the Music bus volume. Stored as the base; fatigue sag + ducking compose on
## top so a later level change / duck doesn't lose the user's setting.
##
## There is no separate "ambient" slider in settings (the bed is part of the
## music feel), so the Ambient bus tracks the music volume too — the player's
## music control governs both the motif and the domestic bed.
func set_music_volume(linear: float) -> void:
	_music_base_db = linear_volume_to_db(linear)
	_refresh_music_volume()
	set_ambient_volume(linear)


## Set the Ambient bus volume (base; sag + ducking compose on top).
func set_ambient_volume(linear: float) -> void:
	_ambient_base_db = linear_volume_to_db(linear)
	_refresh_ambient_volume()


## SFX volume maps straight to the SFX bus (no sag/duck — cues stay legible).
func set_sfx_volume(linear: float) -> void:
	_set_bus_db(_bus_sfx, linear_volume_to_db(linear))


func _set_bus_db(bus: int, db: float) -> void:
	if bus < 0:
		return
	AudioServer.set_bus_volume_db(bus, db)


## Recompute and apply the Music bus dB = base + fatigue sag + duck.
func _refresh_music_volume() -> void:
	_set_bus_db(_bus_music, _music_base_db + _music_sag_db + _duck_db)


## Recompute and apply the Ambient bus dB = base + fatigue sag + duck.
func _refresh_ambient_volume() -> void:
	_set_bus_db(_bus_ambient, _ambient_base_db + _ambient_sag_db + _duck_db)


# ---------------------------------------------------------------------------
# SFX playback
# ---------------------------------------------------------------------------

## Play a named SFX (see SFX_PATHS) on the next free pooled voice. Unknown names
## and missing/failed loads are silent no-ops — never a crash.
func play_sfx(sfx_name: String, volume_db: float = 0.0) -> void:
	var stream := _sfx_stream(sfx_name)
	if stream == null:
		return
	var player := _next_sfx_player()
	if player == null:
		return
	player.stream = stream
	player.volume_db = volume_db
	player.play()


## Lazily load & cache an SFX stream by name; null if absent/unknown.
func _sfx_stream(sfx_name: String) -> AudioStream:
	if _sfx_cache.has(sfx_name):
		return _sfx_cache[sfx_name]
	if not SFX_PATHS.has(sfx_name):
		return null
	var path: String = SFX_PATHS[sfx_name]
	var stream := _load_stream(path)
	_sfx_cache[sfx_name] = stream  # cache null too, so we don't retry every press
	return stream


func _next_sfx_player() -> AudioStreamPlayer:
	if _sfx_pool.is_empty():
		return null
	var p := _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	return p


# ---------------------------------------------------------------------------
# Music / ambient playback (crossfaded)
# ---------------------------------------------------------------------------

## Play a music stream (a path String or an AudioStream), crossfading from any
## current track over `fade` seconds. Null/missing stream stops music instead.
func play_music(stream: Variant, fade: float = DEFAULT_FADE) -> void:
	var s := _as_stream(stream)
	_crossfade(_music_player, s, fade)


## Convenience: play the placeholder piano motif as the menu/interstitial music.
func play_menu_music(fade: float = DEFAULT_FADE) -> void:
	play_music(MUSIC_PIANO_MOTIF, fade)


## Play an ambient bed (path or stream), crossfading over `fade`. The bed loops
## if its stream is set to loop (the placeholder room-tone is).
func play_ambient(stream: Variant, fade: float = DEFAULT_FADE) -> void:
	var s := _as_stream(stream)
	_crossfade(_ambient_player, s, fade)


## Convenience: start the domestic bed — room-tone plus the faint ticking clock.
func play_room_ambient(fade: float = DEFAULT_FADE) -> void:
	play_ambient(AMBIENT_ROOM_TONE, fade)
	_start_clock(fade)


## Stop the music bed, fading out over `fade`.
func stop_music(fade: float = DEFAULT_FADE) -> void:
	_crossfade(_music_player, null, fade)


## Stop the ambient bed (and the clock) over `fade`.
func stop_ambient(fade: float = DEFAULT_FADE) -> void:
	_crossfade(_ambient_player, null, fade)
	_crossfade(_clock_player, null, fade)


func _start_clock(fade: float) -> void:
	var s := _load_stream(AMBIENT_CLOCK_TICK)
	_crossfade(_clock_player, s, fade)


## Crossfade one player to a new stream (or to silence if null). Tween-based so it
## works while the tree runs; guards keep it safe when the player is absent.
func _crossfade(player: AudioStreamPlayer, stream: AudioStream, fade: float) -> void:
	if player == null:
		return

	# No new stream -> fade the player out and stop it.
	if stream == null:
		if not player.playing:
			return
		if fade <= 0.0 or not is_inside_tree():
			player.stop()
			return
		var t := create_tween()
		t.tween_property(player, "volume_db", MUTE_DB, fade)
		t.tween_callback(player.stop)
		return

	# Same stream already playing — leave it be (idempotent calls don't restart).
	if player.stream == stream and player.playing:
		return

	player.stream = stream
	if fade <= 0.0 or not is_inside_tree():
		player.volume_db = 0.0
		player.play()
		return

	player.volume_db = MUTE_DB
	player.play()
	var tw := create_tween()
	tw.tween_property(player, "volume_db", 0.0, fade)


# ---------------------------------------------------------------------------
# Ducking (lower music + ambient briefly under a diegetic interrupt / a beat)
# ---------------------------------------------------------------------------

## Duck music + ambient by `amount` dB (positive number = how much to drop) over
## `time` seconds. Composes with the user volume + fatigue sag.
func duck(amount: float = 8.0, time: float = 0.25) -> void:
	_tween_duck(-absf(amount), time)


## Release a previous duck back to no attenuation over `time` seconds.
func release_duck(time: float = 0.6) -> void:
	_tween_duck(0.0, time)


func _tween_duck(target_db: float, time: float) -> void:
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	if not is_inside_tree() or time <= 0.0:
		_duck_db = target_db
		_refresh_music_volume()
		_refresh_ambient_volume()
		return
	_duck_tween = create_tween()
	_duck_tween.tween_method(_set_duck_db, _duck_db, target_db, time)


func _set_duck_db(db: float) -> void:
	_duck_db = db
	_refresh_music_volume()
	_refresh_ambient_volume()


# ---------------------------------------------------------------------------
# Fatigue dulling (low-pass sweep + volume sag), driven by GameState
# ---------------------------------------------------------------------------

func _on_fatigue_level_changed(level: int) -> void:
	_apply_dulling(level, true)


## Sweep the Music + Ambient low-pass cutoff and volume sag toward the level's
## targets. When `animated`, tween over DULL_TWEEN_TIME; otherwise snap (initial
## apply). Always safe if a filter/bus is missing.
func _apply_dulling(level: int, animated: bool) -> void:
	var target_cutoff := cutoff_for_level(level)
	var target_sag := volume_sag_for_level(level)

	if _dull_tween != null and _dull_tween.is_valid():
		_dull_tween.kill()

	if not animated or not is_inside_tree():
		_set_cutoff(target_cutoff)
		_set_sag(target_sag)
		return

	var from_cutoff := _current_cutoff()
	_dull_tween = create_tween().set_parallel(true)
	_dull_tween.tween_method(_set_cutoff, from_cutoff, target_cutoff, DULL_TWEEN_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_dull_tween.tween_method(_set_sag, _music_sag_db, target_sag, DULL_TWEEN_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _current_cutoff() -> float:
	if _lp_music != null:
		return _lp_music.cutoff_hz
	if _lp_ambient != null:
		return _lp_ambient.cutoff_hz
	return CUTOFF_BY_LEVEL[0]


func _set_cutoff(hz: float) -> void:
	if _lp_music != null:
		_lp_music.cutoff_hz = hz
	if _lp_ambient != null:
		_lp_ambient.cutoff_hz = hz


func _set_sag(db: float) -> void:
	_music_sag_db = db
	_ambient_sag_db = db
	_refresh_music_volume()
	_refresh_ambient_volume()


# ---------------------------------------------------------------------------
# Stream loading helpers (never crash on a missing/bad asset)
# ---------------------------------------------------------------------------

## Coerce a path String or an AudioStream into an AudioStream (or null).
func _as_stream(stream: Variant) -> AudioStream:
	if stream is AudioStream:
		return stream as AudioStream
	if stream is String:
		return _load_stream(stream as String)
	return null


## Load an AudioStream from a res path, guarded — returns null if the file is
## absent or isn't a stream (so placeholder gaps never crash playback).
func _load_stream(path: String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var res := ResourceLoader.load(path)
	if res is AudioStream:
		return res as AudioStream
	return null


# ---------------------------------------------------------------------------
# Autoload lookup (guarded so bare-instance / SceneTree tests don't need the tree)
# ---------------------------------------------------------------------------

## Resolve the GameState autoload, or null if not registered (tests / bare use).
func _game_state() -> Object:
	if is_inside_tree():
		var tree := get_tree()
		if tree != null and tree.root != null:
			var found := tree.root.get_node_or_null(NodePath("GameState"))
			if found != null:
				return found
	var parent := get_parent()
	if parent != null:
		return parent.get_node_or_null(NodePath("GameState"))
	return null
