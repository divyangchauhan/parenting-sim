extends SceneTree
## Headless unit test for SaveManager.
## Run with: godot --headless --path game --script tests/test_save.gd
##
## A SceneTree script does not boot project autoloads, so we instantiate the
## SaveManager script directly. SaveManager references the GameState /
## AudioManager / Haptics autoloads only through get_node_or_null guards, so
## those lookups simply return null here and the settings + file paths still
## work. The run save/load round-trip is exercised by injecting a freshly built
## GameState script instance as a child named "GameState" under the manager's
## parent, so SaveManager._game_state()/get_node_or_null("/root/GameState")
## resolves to it.
##
## Coverage:
##   - settings defaults on a missing file
##   - settings round-trip (set -> persist -> reload -> equals)
##   - has_save / erase_save lifecycle
##   - run save/load round-trip (via an injected GameState instance)
##
## Not covered here: live application to AudioManager (stub until PR-10) and the
## ThemeDB font sizing side effect (display-side; the call is guarded but not
## asserted). Those are exercised by hand / PR-10.

const SaveManagerScript = preload("res://autoload/SaveManager.gd")
const GameStateScript = preload("res://autoload/GameState.gd")


func _init() -> void:
	_clean_files()

	_test_defaults_on_missing_file()
	_test_settings_round_trip()
	_test_corrupt_settings_falls_back()
	_test_has_save_and_erase()
	_test_run_round_trip()

	_clean_files()
	print("Save tests passed")
	quit(0)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a SaveManager and load its settings (mirrors what _ready does, minus the
## live-apply which needs autoloads / a display). Not parented to the tree so
## _ready does not auto-fire.
func _make() -> Object:
	var sm: Object = SaveManagerScript.new()
	sm._load_settings()
	return sm


func _clean_files() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for f in ["save.json", "settings.json"]:
		if dir.file_exists(f):
			dir.remove(f)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func _test_defaults_on_missing_file() -> void:
	_clean_files()
	var sm := _make()
	# Every default is present and correct on a fresh install.
	for key in sm.DEFAULT_SETTINGS:
		assert(sm.get_setting(key) == sm.DEFAULT_SETTINGS[key],
			"default for %s should be %s" % [key, str(sm.DEFAULT_SETTINGS[key])])
	# Loading with no file should have written a clean settings file.
	assert(FileAccess.file_exists(sm.SETTINGS_PATH), "_load_settings seeds a settings file")
	# Unknown key falls back to the passed default.
	assert(sm.get_setting("nope", 42) == 42, "unknown key returns passed default")
	sm.free()


func _test_settings_round_trip() -> void:
	_clean_files()
	var sm := _make()
	sm.set_setting(sm.KEY_MASTER_VOLUME, 0.5)
	sm.set_setting(sm.KEY_HAPTICS, false)
	sm.set_setting(sm.KEY_TEXT_SCALE, 1.25)
	sm.set_setting(sm.KEY_REDUCE_MOTION, true)

	# A fresh manager reading the same file must see the persisted values.
	var sm2 := _make()
	assert(is_equal_approx(float(sm2.get_setting(sm2.KEY_MASTER_VOLUME)), 0.5),
		"master_volume persists across reload")
	assert(sm2.get_setting(sm2.KEY_HAPTICS) == false, "haptics persists across reload")
	assert(is_equal_approx(float(sm2.get_setting(sm2.KEY_TEXT_SCALE)), 1.25),
		"text_scale persists across reload")
	assert(sm2.get_setting(sm2.KEY_REDUCE_MOTION) == true, "reduce_motion persists across reload")

	# Untouched keys keep their defaults.
	assert(is_equal_approx(float(sm2.get_setting(sm2.KEY_MUSIC_VOLUME)),
		float(sm2.DEFAULT_SETTINGS[sm2.KEY_MUSIC_VOLUME])), "untouched key keeps default")

	# all_settings returns a defensive copy.
	var snap: Dictionary = sm2.all_settings()
	snap[sm2.KEY_MASTER_VOLUME] = -999.0
	assert(is_equal_approx(float(sm2.get_setting(sm2.KEY_MASTER_VOLUME)), 0.5),
		"all_settings returns a copy that can't mutate live state")

	sm.free()
	sm2.free()


func _test_corrupt_settings_falls_back() -> void:
	_clean_files()
	# Write garbage into the settings file.
	var sm0 := _make()
	var path: String = sm0.SETTINGS_PATH
	sm0.free()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ this is not valid json ::::")
	f.close()

	# A manager loading the corrupt file must fall back to defaults, not crash.
	var sm := _make()
	for key in sm.DEFAULT_SETTINGS:
		assert(sm.get_setting(key) == sm.DEFAULT_SETTINGS[key],
			"corrupt file falls back to default for %s" % key)
	sm.free()


func _test_has_save_and_erase() -> void:
	_clean_files()
	var sm := _make()
	assert(not sm.has_save(), "no save initially")

	# save_run with no GameState reachable is a guarded no-op (no file, no crash).
	sm.save_run()
	assert(not sm.has_save(), "save_run without GameState writes nothing")

	# Write a save file directly, then erase it.
	sm._write_json(sm.SAVE_PATH, {"save_version": 1, "day": 3})
	assert(sm.has_save(), "has_save true after a file is written")
	sm.erase_save()
	assert(not sm.has_save(), "erase_save removes the save file")
	# Erasing again is safe.
	sm.erase_save()
	sm.free()


## Full run save/load round-trip by injecting a GameState instance the manager
## can resolve through get_node_or_null("/root/GameState").
func _test_run_round_trip() -> void:
	_clean_files()

	# Parent the manager + a GameState named exactly "GameState" under the root so
	# get_node_or_null("/root/GameState") inside SaveManager resolves to it.
	var sm := SaveManagerScript.new()
	var gs := GameStateScript.new()
	gs.name = "GameState"
	root.add_child(gs)
	root.add_child(sm)
	# (sm._ready ran on add; it loads settings and tries to apply them harmlessly.)

	gs.new_run()
	gs.apply_response({
		"cost": {"time": 3, "energy": 4, "patience": 2},
		"effects": {"connection": 3, "standing": -1},
		"sets_flags": ["read_story"],
	})
	gs.day = 4

	sm.save_run()
	assert(sm.has_save(), "save_run writes a save file with GameState present")

	# Mutate live state, then load it back and confirm restoration.
	var saved_day: int = gs.day
	var saved_energy: int = gs.energy
	gs.day = 99
	gs.energy = 0

	assert(sm.load_run(), "load_run succeeds with a valid save")
	assert(gs.day == saved_day, "load_run restores day")
	assert(gs.energy == saved_energy, "load_run restores energy")
	assert(gs.has_flag("read_story"), "load_run restores flags")
	assert(gs.states["connection"] == 3, "load_run restores hidden states")

	sm.erase_save()
	assert(not sm.load_run(), "load_run returns false when no save exists")

	sm.free()
	gs.free()
