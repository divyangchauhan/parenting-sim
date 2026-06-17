extends SceneTree
## Headless unit test for FatigueFX's pure level->params mapping.
## Run with: godot --headless --path game --script tests/test_fatigue.gd
##
## A SceneTree script does not boot project autoloads, so we instantiate the
## FatigueFX script directly and exercise its static, scene-tree-free mapping
## (params_for_level) with bare asserts. The scene-touching parts of FatigueFX
## are deliberately not under test here.

const FatigueFXScript = preload("res://scenes/FatigueFX.gd")

## Fatigue levels span 0..3 (4 bands).
const LEVELS := 4


func _init() -> void:
	_test_level_zero_is_neutral()
	_test_monotonicity()
	_test_bounded_and_sane()
	print("Fatigue tests passed")
	quit(0)


## Level 0 (fresh) must be perfectly neutral: full colour, no dim, normal speed.
func _test_level_zero_is_neutral() -> void:
	var p: Dictionary = FatigueFXScript.params_for_level(0)
	assert(p["desaturation"] == 0.0, "level 0 desaturation must be 0")
	assert(p["dim"] == 0.0, "level 0 dim must be 0")
	assert(p["anim_speed"] == 1.0, "level 0 anim_speed must be 1.0")


## desaturation & dim non-decreasing with level; anim_speed non-increasing.
func _test_monotonicity() -> void:
	for level in range(1, LEVELS):
		var prev: Dictionary = FatigueFXScript.params_for_level(level - 1)
		var cur: Dictionary = FatigueFXScript.params_for_level(level)
		assert(cur["desaturation"] >= prev["desaturation"],
			"desaturation must not decrease: L%d=%s < L%d=%s" % [
				level, str(cur["desaturation"]), level - 1, str(prev["desaturation"])])
		assert(cur["dim"] >= prev["dim"],
			"dim must not decrease: L%d=%s < L%d=%s" % [
				level, str(cur["dim"]), level - 1, str(prev["dim"])])
		assert(cur["anim_speed"] <= prev["anim_speed"],
			"anim_speed must not increase: L%d=%s > L%d=%s" % [
				level, str(cur["anim_speed"]), level - 1, str(prev["anim_speed"])])


## All four levels return bounded, sane values.
func _test_bounded_and_sane() -> void:
	for level in range(LEVELS):
		var p: Dictionary = FatigueFXScript.params_for_level(level)
		assert(p.has("desaturation") and p.has("dim") and p.has("anim_speed"),
			"params_for_level(%d) missing a key" % level)
		assert(p["desaturation"] >= 0.0 and p["desaturation"] <= 1.0,
			"L%d desaturation out of 0..1: %s" % [level, str(p["desaturation"])])
		assert(p["dim"] >= 0.0 and p["dim"] <= 1.0,
			"L%d dim out of 0..1: %s" % [level, str(p["dim"])])
		# anim_speed: slowed but never stopped or sped up past normal.
		assert(p["anim_speed"] > 0.0 and p["anim_speed"] <= 1.0,
			"L%d anim_speed out of (0..1]: %s" % [level, str(p["anim_speed"])])

	# The burnt-out level should actually be tired: real desaturation/dim and a
	# meaningfully slowed animation.
	var worst: Dictionary = FatigueFXScript.params_for_level(LEVELS - 1)
	assert(worst["desaturation"] > 0.5, "burnt-out level should be heavily desaturated")
	assert(worst["dim"] > 0.0, "burnt-out level should be dimmed")
	assert(worst["anim_speed"] < 1.0, "burnt-out level should be slowed")

	# Out-of-range levels clamp rather than crash.
	assert(FatigueFXScript.params_for_level(-5) == FatigueFXScript.params_for_level(0),
		"negative level clamps to 0")
	assert(FatigueFXScript.params_for_level(99) == FatigueFXScript.params_for_level(LEVELS - 1),
		"too-high level clamps to the worst band")
