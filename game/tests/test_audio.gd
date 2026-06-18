extends SceneTree
## Headless unit test for AudioManager's PURE, device-free mappings.
## Run with: godot --headless --path game --script tests/test_audio.gd
##
## A SceneTree script does not boot project autoloads, so we instantiate the
## AudioManager script directly and exercise only its static, AudioServer-free
## maps (cutoff_for_level, volume_sag_for_level, linear_volume_to_db). The
## bus-touching playback parts are deliberately not under test here (no audio
## device under --headless), mirroring test_fatigue.gd's approach for FatigueFX.

const AudioManagerScript = preload("res://autoload/AudioManager.gd")

## Fatigue levels span 0..3 (4 bands), matching GameState.FATIGUE_THRESHOLDS.
const LEVELS := 4


func _init() -> void:
	_test_cutoff_monotone_and_bounded()
	_test_level_zero_is_open()
	_test_volume_sag_shape()
	_test_linear_to_db_endpoints()
	_test_instantiable()
	print("Audio tests passed")
	quit(0)


## Cutoff must be positive at every level and never increase as fatigue rises:
## a tireder player hears a duller (more filtered) world.
func _test_cutoff_monotone_and_bounded() -> void:
	for level in range(LEVELS):
		var c: float = AudioManagerScript.cutoff_for_level(level)
		assert(c > 0.0, "cutoff at L%d must be positive: %s" % [level, str(c)])
	for level in range(1, LEVELS):
		var prev: float = AudioManagerScript.cutoff_for_level(level - 1)
		var cur: float = AudioManagerScript.cutoff_for_level(level)
		assert(cur <= prev, "cutoff must not increase: L%d=%s > L%d=%s" % [
			level, str(cur), level - 1, str(prev)])

	# Burnt-out must be meaningfully more filtered than fresh.
	var fresh: float = AudioManagerScript.cutoff_for_level(0)
	var burnt: float = AudioManagerScript.cutoff_for_level(LEVELS - 1)
	assert(burnt < fresh, "burnt-out cutoff must be below fresh")
	assert(burnt < 3000.0, "burnt-out should be heavily filtered (< 3 kHz)")

	# Out-of-range levels clamp rather than crash.
	assert(AudioManagerScript.cutoff_for_level(-5) == AudioManagerScript.cutoff_for_level(0),
		"negative level clamps to 0")
	assert(AudioManagerScript.cutoff_for_level(99) == AudioManagerScript.cutoff_for_level(LEVELS - 1),
		"too-high level clamps to the worst band")


## Level 0 (fresh) should be open / near full bandwidth.
func _test_level_zero_is_open() -> void:
	var c: float = AudioManagerScript.cutoff_for_level(0)
	assert(c >= 16000.0, "level 0 should be open/high cutoff: %s" % str(c))


## Sag is <= 0 at every level (never a boost), 0 at level 0, and non-increasing.
func _test_volume_sag_shape() -> void:
	assert(AudioManagerScript.volume_sag_for_level(0) == 0.0, "no sag when fresh")
	for level in range(LEVELS):
		var s: float = AudioManagerScript.volume_sag_for_level(level)
		assert(s <= 0.0, "sag at L%d must be <= 0: %s" % [level, str(s)])
	for level in range(1, LEVELS):
		var prev: float = AudioManagerScript.volume_sag_for_level(level - 1)
		var cur: float = AudioManagerScript.volume_sag_for_level(level)
		assert(cur <= prev, "sag must not increase: L%d=%s > L%d=%s" % [
			level, str(cur), level - 1, str(prev)])


## Linear 0..1 -> dB: 0 is a hard mute (very low dB), 1 is ~0 dB, midpoints sane.
func _test_linear_to_db_endpoints() -> void:
	var at_zero: float = AudioManagerScript.linear_volume_to_db(0.0)
	assert(at_zero <= -60.0, "linear 0 must map to a deep mute: %s" % str(at_zero))

	var at_one: float = AudioManagerScript.linear_volume_to_db(1.0)
	assert(absf(at_one) < 0.001, "linear 1 must map to ~0 dB: %s" % str(at_one))

	# Half volume is below unity but well above mute, and monotone in between.
	var at_half: float = AudioManagerScript.linear_volume_to_db(0.5)
	assert(at_half < at_one, "0.5 should be quieter than 1.0")
	assert(at_half > at_zero, "0.5 should be louder than mute")

	# Out-of-range clamps.
	assert(AudioManagerScript.linear_volume_to_db(-1.0) <= -60.0, "negative clamps to mute")
	assert(absf(AudioManagerScript.linear_volume_to_db(5.0)) < 0.001, "above 1 clamps to ~0 dB")


## The script instantiates as a bare Node without a tree (no crash); the static
## maps stay usable on the instance too.
func _test_instantiable() -> void:
	var am: Object = AudioManagerScript.new()
	assert(am != null, "AudioManager script instantiates")
	# Volume API exists for SaveManager to call.
	assert(am.has_method("set_master_volume"), "exposes set_master_volume")
	assert(am.has_method("set_music_volume"), "exposes set_music_volume")
	assert(am.has_method("set_sfx_volume"), "exposes set_sfx_volume")
	am.free()
