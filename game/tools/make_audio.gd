extends SceneTree
## make_audio.gd — dev tool. SYNTHESIZES the game's PLACEHOLDER audio from code.
## Run headless (re-runnable; overwrites in place):
##   godot --headless --path game --script tools/make_audio.gd
##
## WHY THIS EXISTS
## There is no audio designer and no real foley/music on the project. So, exactly
## like the interstitial illustration, the AUDIO SYSTEM is built for real but its
## *content* is placeholder: every sound below is generated procedurally — soft
## sines/triangles, filtered noise, a few additive partials — kept deliberately
## SUBTLE and tasteful so the restrained tone of "Enough" survives. They evoke,
## they don't impress. A future real-audio pass should replace every .wav here
## (see docs/AUDIO.md) without touching AudioManager or the bus layout.
##
## OUTPUT (16-bit PCM mono .wav, written via AudioStreamWAV.save_to_wav):
##   audio/sfx/      ui_tap, card_settle, confirm, negative_tick,
##                   notify_buzz, child_cue
##   audio/ambient/  room_tone (loop), clock_tick (loop), piano_motif
##
## The loop files set the WAV loop flags so AudioManager can play them seamlessly.

# ---------------------------------------------------------------------------
# Synthesis constants
# ---------------------------------------------------------------------------

## Output sample rate. 22.05 kHz is plenty for these soft, low-content sounds and
## keeps the committed placeholder files small.
const RATE := 22050

const SFX_DIR := "res://audio/sfx"
const AMBIENT_DIR := "res://audio/ambient"

const TAU_F := TAU  # alias for readability in the maths below.


func _init() -> void:
	_ensure_dirs()

	# --- SFX (short, one-shot) ---
	_save(SFX_DIR + "/ui_tap.wav", _make_ui_tap(), false)
	_save(SFX_DIR + "/card_settle.wav", _make_card_settle(), false)
	_save(SFX_DIR + "/confirm.wav", _make_confirm(), false)
	_save(SFX_DIR + "/negative_tick.wav", _make_negative_tick(), false)
	_save(SFX_DIR + "/notify_buzz.wav", _make_notify_buzz(), false)
	_save(SFX_DIR + "/child_cue.wav", _make_child_cue(), false)

	# --- Ambient (loops) + the motif ---
	_save(AMBIENT_DIR + "/room_tone.wav", _make_room_tone(), true)
	_save(AMBIENT_DIR + "/clock_tick.wav", _make_clock_tick(), true)
	_save(AMBIENT_DIR + "/piano_motif.wav", _make_piano_motif(), false)

	print("make_audio: done.")
	quit(0)


# ---------------------------------------------------------------------------
# File helpers
# ---------------------------------------------------------------------------

func _ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SFX_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AMBIENT_DIR))


## Build an AudioStreamWAV from float samples (-1..1) and save it as 16-bit PCM.
## `loop` sets a full-buffer forward loop for the ambient beds.
func _save(path: String, samples: PackedFloat32Array, loop: bool) -> void:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = _to_pcm16(samples)
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()

	var abs_path := ProjectSettings.globalize_path(path)
	var err := stream.save_to_wav(abs_path)
	if err != OK:
		push_error("make_audio: save failed (%d) for %s" % [err, path])
		quit(1)
		return
	print("make_audio: wrote %s (%d samples, loop=%s)" % [path, samples.size(), str(loop)])


## Convert float samples (-1..1) to little-endian 16-bit PCM bytes, clamped.
func _to_pcm16(samples: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := clampf(samples[i], -1.0, 1.0)
		var s := int(round(v * 32767.0))
		bytes.encode_s16(i * 2, s)
	return bytes


# ---------------------------------------------------------------------------
# Synthesis helpers
# ---------------------------------------------------------------------------

func _samples(seconds: float) -> int:
	return int(round(seconds * RATE))


## A soft attack/decay envelope (no sustain): quick rise, exponential-ish fall.
func _env_pluck(i: int, n: int, attack: float, decay_pow: float) -> float:
	var t := float(i) / float(maxi(n - 1, 1))
	var a := minf(t / maxf(attack, 0.0001), 1.0)
	var rel := pow(1.0 - t, decay_pow)
	return a * rel


## A smooth fade-in/out window for loop beds so the buffer wraps clickless.
func _env_loop_edges(i: int, n: int, edge: float) -> float:
	var e := int(maxf(edge, 0.0001) * n)
	if e <= 0:
		return 1.0
	if i < e:
		return float(i) / float(e)
	if i > n - e:
		return float(n - i) / float(e)
	return 1.0


func _sine(phase: float) -> float:
	return sin(phase * TAU_F)


# ---------------------------------------------------------------------------
# SFX
# ---------------------------------------------------------------------------

## Soft UI tap — a short, gentle blip (triangle-ish) with a fast decay. Quiet.
func _make_ui_tap() -> PackedFloat32Array:
	var n := _samples(0.09)
	var out := PackedFloat32Array()
	out.resize(n)
	var freq := 660.0
	for i in n:
		var ph := freq * float(i) / RATE
		# Triangle from the sine's first two partials — softer than a raw square.
		var tri := _sine(ph) * 0.85 + _sine(ph * 3.0) * 0.12
		out[i] = tri * _env_pluck(i, n, 0.06, 2.6) * 0.22
	return out


## Gentle card-settle — a soft, slightly lower double-tone that "lands".
func _make_card_settle() -> PackedFloat32Array:
	var n := _samples(0.16)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		# A small downward glide (a settle), two soft partials.
		var f := 420.0 - 60.0 * (float(i) / n)
		var ph := f * t
		var s := _sine(ph) * 0.8 + _sine(ph * 2.0) * 0.15
		out[i] = s * _env_pluck(i, n, 0.12, 2.0) * 0.18
	return out


## Quiet page/confirm — a soft, warm two-note lift (a small, kind "yes").
func _make_confirm() -> PackedFloat32Array:
	var n := _samples(0.22)
	var out := PackedFloat32Array()
	out.resize(n)
	var half := n / 2
	for i in n:
		# Two gentle notes: a low one, then a slightly higher one.
		var f := 392.0 if i < half else 523.0  # G4 -> C5
		var ph := f * float(i) / RATE
		var s := _sine(ph) * 0.8 + _sine(ph * 2.0) * 0.1
		out[i] = s * _env_pluck(i, n, 0.1, 1.8) * 0.16
	return out


## Soft negative / curt tick — a flatter, drier, lower click. Never harsh.
func _make_negative_tick() -> PackedFloat32Array:
	var n := _samples(0.07)
	var out := PackedFloat32Array()
	out.resize(n)
	var freq := 220.0
	for i in n:
		var ph := freq * float(i) / RATE
		out[i] = _sine(ph) * _env_pluck(i, n, 0.04, 3.4) * 0.17
	return out


## Distant notification buzz — the work "ping": a faint, muffled phone-buzz
## (a low tone amplitude-modulated like a vibrate, kept distant/quiet).
func _make_notify_buzz() -> PackedFloat32Array:
	var n := _samples(0.30)
	var out := PackedFloat32Array()
	out.resize(n)
	var carrier := 180.0
	var buzz_rate := 38.0  # the vibration flutter
	for i in n:
		var t := float(i) / RATE
		var car := _sine(carrier * t)
		# Square-ish gate -> the "bzzt"; softened so it's distant, not buzzy-harsh.
		var gate := 0.5 + 0.5 * signf(_sine(buzz_rate * t))
		gate = lerpf(0.45, 1.0, gate)
		out[i] = car * gate * _env_pluck(i, n, 0.08, 1.4) * 0.13
	return out


## Faint child cue — NOT a realistic cry. A very brief pair of soft filtered
## tones that rise then fall a little, like a small "uh-oh" in the next room.
## Restrained on purpose: it pulls at you without startling.
func _make_child_cue() -> PackedFloat32Array:
	var n := _samples(0.42)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var prog := float(i) / n
		# A gentle pitch arc up then down (an interrogative little lilt).
		var f := 520.0 + 120.0 * sin(prog * PI)
		var ph := f * t
		# Mostly fundamental + a touch of vibrato; soft, vocal-ish, not shrill.
		var vib := 1.0 + 0.015 * _sine(6.0 * t)
		var s := _sine(ph * vib) * 0.85 + _sine(ph * 2.0) * 0.08
		out[i] = s * _env_pluck(i, n, 0.18, 1.6) * 0.14
	return out


# ---------------------------------------------------------------------------
# Ambient beds (loops)
# ---------------------------------------------------------------------------

## Low room-tone / drone loop — filtered (low-passed) noise plus a low sine, very
## quiet. The bed of a tired house. Loop edges are windowed so it wraps cleanly.
func _make_room_tone() -> PackedFloat32Array:
	var seconds := 4.0
	var n := _samples(seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xE10  # deterministic so re-runs are byte-stable
	var lp := 0.0  # one-pole low-pass state
	var alpha := 0.02  # heavy filtering -> a soft, dark hiss
	var low_phase := 0.0
	var low_freq := 56.0
	for i in n:
		var white := rng.randf_range(-1.0, 1.0)
		lp = lp + alpha * (white - lp)
		low_phase += low_freq / RATE
		var low := _sine(low_phase) * 0.5
		var s := lp * 0.6 + low * 0.4
		out[i] = s * _env_loop_edges(i, n, 0.04) * 0.10
	return out


## Faint ticking-clock loop — a soft tick every ~1s over near-silence. Two ticks
## so it loops without an obvious seam.
func _make_clock_tick() -> PackedFloat32Array:
	var seconds := 2.0
	var n := _samples(seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	# A tick is a tiny high-ish pluck.
	var tick_n := _samples(0.018)
	for tick_at in [0.0, 1.0]:
		var start := _samples(float(tick_at))
		for j in tick_n:
			var idx: int = start + j
			if idx >= n:
				break
			var ph := 1500.0 * float(j) / RATE
			out[idx] += _sine(ph) * _env_pluck(j, tick_n, 0.02, 4.0) * 0.10
	return out


# ---------------------------------------------------------------------------
# Sparse piano-ish motif (menu / interstitial)
# ---------------------------------------------------------------------------

## A few slow, gentle pentatonic notes built from additive sine partials with a
## soft piano-like envelope. It only needs to evoke a quiet, wistful motif.
func _make_piano_motif() -> PackedFloat32Array:
	# A minor-pentatonic-ish phrase (Hz): A3 C4 E4 D4 — slow, unhurried.
	var notes := [220.0, 261.63, 329.63, 293.66, 220.0]
	var note_dur := 0.9        # seconds per note (slow)
	var note_n := _samples(note_dur)
	var total := note_n * notes.size()
	var out := PackedFloat32Array()
	out.resize(total)

	for ni in notes.size():
		var f: float = notes[ni]
		var base: int = ni * note_n
		for j in note_n:
			var idx: int = base + j
			var t := float(j) / RATE
			# Additive partials with falling amplitude -> a soft, bell/piano-ish tone.
			var s := 0.0
			s += _sine(f * t) * 1.0
			s += _sine(f * 2.0 * t) * 0.35
			s += _sine(f * 3.0 * t) * 0.12
			s += _sine(f * 4.0 * t) * 0.05
			# Piano-like: quick soft attack, long gentle decay.
			var env := _env_pluck(j, note_n, 0.02, 2.4)
			out[idx] = s * env * 0.10
	return out
