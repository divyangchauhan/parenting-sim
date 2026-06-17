extends SceneTree
## Headless unit test for GameState.
## Run with: godot --headless --path game --script tests/test_gamestate.gd
##
## A SceneTree script does not boot project autoloads, so we instantiate the
## GameState script directly and exercise its public API with bare asserts.

const GameStateScript = preload("res://autoload/GameState.gd")


func _init() -> void:
	_test_new_run()
	_test_apply_response()
	_test_gating_and_afford()
	_test_fatigue_transitions()
	_test_end_day_refill_and_carryover()
	_test_serialization_round_trip()
	print("GameState tests passed")
	quit(0)


func _make() -> Node:
	var gs := GameStateScript.new()
	gs.new_run()
	return gs


func _test_new_run() -> void:
	var gs := _make()
	assert(gs.day == 1, "new_run should start on day 1")
	assert(gs.time == gs.DAY_START_TIME, "new_run sets day-start time")
	assert(gs.energy == gs.DAY_START_ENERGY, "new_run sets day-start energy")
	assert(gs.patience == gs.DAY_START_PATIENCE, "new_run sets day-start patience")
	for key in gs.HIDDEN_STATES:
		assert(gs.states[key] == 0, "new_run zeroes hidden state %s" % key)
	assert(gs.flags.is_empty(), "new_run clears flags")
	gs.free()


func _test_apply_response() -> void:
	var gs := _make()
	var t0: int = gs.time
	var e0: int = gs.energy
	var p0: int = gs.patience
	gs.apply_response({
		"cost": {"time": 2, "energy": 2, "patience": 1},
		"effects": {"connection": 2, "wellbeing": -1, "unknown_state": 99},
		"sets_flags": ["child_asleep"],
	})
	assert(gs.time == t0 - 2, "apply_response spends time")
	assert(gs.energy == e0 - 2, "apply_response spends energy")
	assert(gs.patience == p0 - 1, "apply_response spends patience")
	assert(gs.states["connection"] == 2, "apply_response applies positive effect")
	assert(gs.states["wellbeing"] == -1, "apply_response applies negative effect")
	assert(not gs.states.has("unknown_state"), "apply_response ignores unknown state keys")
	assert(gs.has_flag("child_asleep"), "apply_response records sets_flags")

	# Costs clamp at zero, never negative.
	gs.apply_response({"cost": {"time": 999, "energy": 999, "patience": 999}})
	assert(gs.time == 0 and gs.energy == 0 and gs.patience == 0, "costs clamp at zero")
	gs.free()


func _test_gating_and_afford() -> void:
	var gs := _make()
	# Fresh reserves: a warm option is affordable and ungated.
	assert(gs.can_afford({"time": 2, "energy": 2}), "fresh reserves afford a normal cost")
	assert(not gs.is_response_gated({"energy_min": 2, "patience_min": 1}), "fresh reserves ungate warm option")

	# Drain energy below the gate.
	gs.energy = 1
	assert(gs.is_response_gated({"energy_min": 2}), "low energy locks energy-gated option")
	assert(not gs.can_afford({"energy": 5}), "cannot afford more energy than held")
	assert(gs.can_afford({"energy": 1}), "can afford exactly what is held")

	# Missing cost keys count as zero.
	gs.time = 0
	assert(gs.can_afford({}), "empty cost is always affordable")
	assert(gs.can_afford({"patience": 3}), "patience-only cost ignores empty time/energy")
	gs.free()


func _test_fatigue_transitions() -> void:
	var gs := _make()
	# Fresh: 10 + 8 = 18 -> level 0.
	assert(gs.fatigue_level() == 0, "fresh reserves are fatigue level 0")

	var seen: Array = []
	gs.fatigue_level_changed.connect(func(level): seen.append(level))

	# Drive through each band via apply_response cost spends.
	gs.apply_response({"cost": {"energy": 5, "patience": 3}})  # 5+5=10 -> level 1
	assert(gs.fatigue_level() == 1, "combined 10 is fatigue level 1")
	gs.apply_response({"cost": {"energy": 2, "patience": 2}})  # 3+3=6 -> level 2
	assert(gs.fatigue_level() == 2, "combined 6 is fatigue level 2")
	gs.apply_response({"cost": {"energy": 3, "patience": 3}})  # 0+0=0 -> level 3
	assert(gs.fatigue_level() == 3, "combined 0 is fatigue level 3 (burnt out)")
	assert(seen == [1, 2, 3], "fatigue_level_changed fired once per band crossing, got %s" % str(seen))
	gs.free()


func _test_end_day_refill_and_carryover() -> void:
	var gs := _make()
	# Spend down, then advance the day.
	gs.apply_response({"cost": {"time": 8, "energy": 7, "patience": 6}})
	var e_before: int = gs.energy  # 10 - 7 = 3
	var p_before: int = gs.patience  # 8 - 6 = 2
	gs.end_day()
	assert(gs.day == 2, "end_day advances the day index")
	assert(gs.energy == mini(e_before + gs.OVERNIGHT_ENERGY_REFILL, gs.MAX_ENERGY), "energy gets capped overnight refill")
	assert(gs.patience == mini(p_before + gs.OVERNIGHT_PATIENCE_REFILL, gs.MAX_PATIENCE), "patience gets capped overnight refill")
	# Carryover: reserves are only partially refilled, not back to full.
	assert(gs.energy < gs.DAY_START_ENERGY, "energy carries over (not fully refilled)")

	# start_day only resets the clock, leaving reserves alone.
	gs.start_day()
	assert(gs.time == gs.DAY_START_TIME, "start_day resets the clock")

	# Overnight refill is capped at the maxima.
	gs.energy = gs.MAX_ENERGY
	gs.patience = gs.MAX_PATIENCE
	gs.end_day()
	assert(gs.energy == gs.MAX_ENERGY, "energy refill never exceeds MAX_ENERGY")
	assert(gs.patience == gs.MAX_PATIENCE, "patience refill never exceeds MAX_PATIENCE")

	# Running past the final day ends the run.
	var ended: Array = [false]
	gs.run_ended.connect(func(): ended[0] = true)
	gs.day = gs.WEEK_LENGTH
	gs.end_day()
	assert(ended[0], "end_day past WEEK_LENGTH emits run_ended")
	gs.free()


func _test_serialization_round_trip() -> void:
	var gs := _make()
	gs.apply_response({
		"cost": {"time": 3, "energy": 4, "patience": 2},
		"effects": {"connection": 3, "standing": -2},
		"sets_flags": ["read_story", "skipped_call"],
	})
	gs.day = 4
	var snapshot: Dictionary = gs.to_dict()
	assert(snapshot["save_version"] == gs.SAVE_VERSION, "to_dict includes save_version")

	# Mutating the snapshot must not affect live state.
	snapshot["states"]["connection"] = -999
	assert(gs.states["connection"] == 3, "to_dict returns a defensive copy of states")
	snapshot["states"]["connection"] = 3  # restore for the round-trip check

	var gs2 := GameStateScript.new()
	gs2.from_dict(snapshot)
	assert(gs2.time == gs.time, "round-trip preserves time")
	assert(gs2.energy == gs.energy, "round-trip preserves energy")
	assert(gs2.patience == gs.patience, "round-trip preserves patience")
	assert(gs2.day == gs.day, "round-trip preserves day")
	for key in gs.HIDDEN_STATES:
		assert(gs2.states[key] == gs.states[key], "round-trip preserves hidden state %s" % key)
	assert(gs2.has_flag("read_story") and gs2.has_flag("skipped_call"), "round-trip preserves flags")
	assert(gs2.fatigue_level() == gs.fatigue_level(), "round-trip restores fatigue level")
	gs.free()
	gs2.free()
