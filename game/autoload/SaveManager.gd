extends Node
## SaveManager — JSON save/load of run + settings in user:// (PR-08).
##
## Two responsibilities, kept separate on disk:
##   - The active run:   user://save.json   (one save slot; serialized GameState)
##   - Player settings:  user://settings.json (volumes, haptics, accessibility)
##
## Both files are versioned with save_version so a future shape change can migrate
## rather than break. All file IO is defensive: a missing or corrupt file never
## crashes — we fall back to defaults and (for settings) rewrite a clean file.
##
## On _ready it loads settings and applies them to the live systems it can reach
## (AudioManager volumes, Haptics enabled flag, and the global accessibility knobs
## text_scale + reduce_motion). AudioManager is a stub until PR-10, so volume
## forwarding is guarded with has_method() — the values are always *stored* and
## forwarded the moment a setter exists. text_scale is applied to the fallback
## theme font size (see _apply_text_scale); reduce_motion is exposed as a plain
## setting that motion-bearing scenes read via get_setting() and skip/shorten
## their tweens when true. PR-09's Theme should honor the same text_scale base
## (see _apply_text_scale for the exact contract).

# ---------------------------------------------------------------------------
# Paths & versioning
# ---------------------------------------------------------------------------

const SAVE_PATH := "user://save.json"
const SETTINGS_PATH := "user://settings.json"

## Bumped when the on-disk shape of either file changes (mirrors GameState.SAVE_VERSION).
const SAVE_VERSION := 1

# ---------------------------------------------------------------------------
# Settings keys & defaults
# ---------------------------------------------------------------------------

const KEY_MASTER_VOLUME := "master_volume"
const KEY_MUSIC_VOLUME := "music_volume"
const KEY_SFX_VOLUME := "sfx_volume"
const KEY_HAPTICS := "haptics"
const KEY_TEXT_SCALE := "text_scale"
const KEY_REDUCE_MOTION := "reduce_motion"

## Canonical default settings. all_settings() / get_setting() fall back to these,
## and a fresh / corrupt settings file is seeded from them.
const DEFAULT_SETTINGS := {
	KEY_MASTER_VOLUME: 1.0,
	KEY_MUSIC_VOLUME: 0.8,
	KEY_SFX_VOLUME: 0.9,
	KEY_HAPTICS: true,
	KEY_TEXT_SCALE: 1.0,
	KEY_REDUCE_MOTION: false,
}

## Base fallback-font size used as the multiplicand for text_scale. PR-09's Theme
## should treat its own base default font size the same way (multiply by
## get_setting("text_scale", 1.0)) so the accessibility knob keeps working.
const BASE_FONT_SIZE := 16

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Live, in-memory settings (always a full dictionary: defaults + any persisted).
var _settings: Dictionary = {}

## Captured-once authored font sizes of the project theme (text_scale 1.0
## baseline), so scaling never compounds. Filled lazily on first text-scale apply.
var _theme_size_baseline: Array[Dictionary] = []
var _theme_default_size_baseline: int = BASE_FONT_SIZE

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_load_settings()
	_apply_all_settings()


# ---------------------------------------------------------------------------
# Run save / load
# ---------------------------------------------------------------------------

## True if a run save file exists on disk.
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Serialize the current GameState run to disk. Silent no-op if GameState is
## somehow unavailable (e.g. bare-instance tests without the autoload).
func save_run() -> void:
	var gs := _game_state()
	if gs == null:
		push_warning("SaveManager.save_run: GameState unavailable; skipping.")
		return
	var data: Dictionary = gs.to_dict()
	data["save_version"] = SAVE_VERSION
	_write_json(SAVE_PATH, data)


## Load the saved run and apply it to GameState. Returns true on success.
## Returns false (and leaves GameState untouched) if there is no save, the file
## is corrupt, or GameState is unavailable.
func load_run() -> bool:
	if not has_save():
		return false
	var data: Variant = _read_json(SAVE_PATH)
	if not (data is Dictionary):
		push_warning("SaveManager.load_run: save file unreadable/corrupt.")
		return false
	var gs := _game_state()
	if gs == null:
		push_warning("SaveManager.load_run: GameState unavailable.")
		return false
	gs.from_dict(data)
	return true


## Delete the run save (settings are left untouched). Safe if no save exists.
func erase_save() -> void:
	if not has_save():
		return
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK:
		# globalize_path may not resolve user:// on every platform; fall back.
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.remove(SAVE_PATH.get_file())


## Day-boundary autosave. Thin alias over save_run() so callers read clearly.
func autosave() -> void:
	save_run()


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

## Read a setting, falling back to the per-key default (and then `default`).
func get_setting(key: String, default: Variant = null) -> Variant:
	if _settings.has(key):
		return _settings[key]
	if DEFAULT_SETTINGS.has(key):
		return DEFAULT_SETTINGS[key]
	return default


## Set a setting, persist immediately, and apply it live.
func set_setting(key: String, value: Variant) -> void:
	_settings[key] = value
	_save_settings()
	_apply_setting(key, value)


## A defensive copy of the full live settings dictionary.
func all_settings() -> Dictionary:
	return _settings.duplicate(true)


# ---------------------------------------------------------------------------
# Applying settings to live systems
# ---------------------------------------------------------------------------

## Apply every setting to the systems it drives. Called once on _ready.
func _apply_all_settings() -> void:
	for key in _settings:
		_apply_setting(key, _settings[key])


## Route one setting to its live system. Unknown keys are simply stored.
func _apply_setting(key: String, value: Variant) -> void:
	match key:
		KEY_MASTER_VOLUME:
			_forward_volume("set_master_volume", value)
		KEY_MUSIC_VOLUME:
			_forward_volume("set_music_volume", value)
		KEY_SFX_VOLUME:
			_forward_volume("set_sfx_volume", value)
		KEY_HAPTICS:
			_apply_haptics(bool(value))
		KEY_TEXT_SCALE:
			_apply_text_scale(float(value))
		KEY_REDUCE_MOTION:
			pass  # Pull-based: scenes read get_setting(KEY_REDUCE_MOTION) directly.


## Forward a volume to AudioManager if it exposes the matching setter. The stub
## (pre-PR-10) has none, so this is a no-op until PR-10 adds the setters.
func _forward_volume(setter: String, value: Variant) -> void:
	var am := _autoload("AudioManager")
	if am != null and am.has_method(setter):
		am.call(setter, float(value))


## Set the Haptics enabled flag if Haptics exposes one; otherwise store an
## `enabled` property dynamically so its wrapper can honor it.
func _apply_haptics(enabled: bool) -> void:
	var haptics := _autoload("Haptics")
	if haptics == null:
		return
	if haptics.has_method("set_enabled"):
		haptics.call("set_enabled", enabled)
	elif "enabled" in haptics:
		haptics.set("enabled", enabled)


## Apply text scaling globally. Two channels, kept in lockstep:
##   1. ThemeDB.fallback_font_size — covers any Control that inherits sizing.
##   2. The project default Theme (ui/theme.tres, PR-09) — its explicit font
##      sizes are authored at text_scale 1.0, so we scale them from their stored
##      baseline each time. Both multiply BASE_FONT_SIZE-relative values, so the
##      accessibility knob moves titles, prompts, HUD and body together.
## Robust against ThemeDB / theme absence (bare tests skip the theme channel).
func _apply_text_scale(scale: float) -> void:
	var clamped := maxf(scale, 0.5)
	var size := int(round(BASE_FONT_SIZE * clamped))
	if ThemeDB != null and ThemeDB.fallback_font != null:
		ThemeDB.fallback_font_size = size
	_scale_project_theme(clamped)


## Scale every font size in the project default Theme from its authored (1.0)
## baseline. The baseline is captured once on first call so repeated changes
## never compound. No-op when there is no project theme (e.g. bare tests).
func _scale_project_theme(scale: float) -> void:
	var theme := ThemeDB.get_project_theme() if ThemeDB != null else null
	if theme == null:
		return
	if _theme_size_baseline.is_empty():
		_capture_theme_baseline(theme)
	for entry in _theme_size_baseline:
		var node_type: String = entry["type"]
		var name: String = entry["name"]
		var base_size: int = entry["size"]
		theme.set_font_size(name, node_type, int(round(base_size * scale)))
	if theme.default_font_size > 0:
		theme.default_font_size = int(round(_theme_default_size_baseline * scale))


## Snapshot the theme's authored font sizes once so scaling is always relative
## to the 1.0 baseline rather than the last-applied value.
func _capture_theme_baseline(theme: Theme) -> void:
	_theme_default_size_baseline = theme.default_font_size if theme.default_font_size > 0 else BASE_FONT_SIZE
	for node_type in theme.get_font_size_type_list():
		for name in theme.get_font_size_list(node_type):
			_theme_size_baseline.append({
				"type": node_type,
				"name": name,
				"size": theme.get_font_size(name, node_type),
			})


# ---------------------------------------------------------------------------
# File IO helpers (never crash on bad/missing files)
# ---------------------------------------------------------------------------

## Load settings from disk into _settings, merged over the defaults. A missing or
## corrupt file yields a clean defaults set (and rewrites a fresh file).
func _load_settings() -> void:
	_settings = DEFAULT_SETTINGS.duplicate(true)

	if not FileAccess.file_exists(SETTINGS_PATH):
		_save_settings()
		return

	var data: Variant = _read_json(SETTINGS_PATH)
	if not (data is Dictionary):
		push_warning("SaveManager: settings file corrupt; restoring defaults.")
		_save_settings()
		return

	# Merge only known keys, coercing to the default's type where sensible.
	for key in DEFAULT_SETTINGS:
		if data.has(key):
			_settings[key] = _coerce(key, data[key])


## Coerce a loaded value to the type of its default so a hand-edited / older file
## can't poison a setting with the wrong type.
func _coerce(key: String, value: Variant) -> Variant:
	var default = DEFAULT_SETTINGS[key]
	if typeof(default) == TYPE_BOOL:
		return bool(value)
	if typeof(default) == TYPE_FLOAT:
		return float(value)
	if typeof(default) == TYPE_INT:
		return int(value)
	return value


## Persist the current settings to disk (versioned).
func _save_settings() -> void:
	var out := _settings.duplicate(true)
	out["save_version"] = SAVE_VERSION
	_write_json(SETTINGS_PATH, out)


## Write a Dictionary as pretty JSON. Logs (not crashes) on failure.
func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: cannot open %s for write (err %d)." % [path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


## Read & parse a JSON file. Returns null on any problem (missing, unreadable,
## malformed) — callers treat null as "no usable data".
func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	# Use a JSON instance (returns an error code) rather than JSON.parse_string,
	# which logs an engine-level error on malformed input. We treat any parse
	# failure as "no usable data" and return null.
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


# ---------------------------------------------------------------------------
# Autoload lookups (guarded so bare-instance tests don't require the tree)
# ---------------------------------------------------------------------------

## Resolve the GameState autoload, or null if it isn't registered (tests).
func _game_state() -> Object:
	return _autoload("GameState")


## Resolve a named autoload/sibling without using an absolute path (which errors
## when this node is parented manually in a bare SceneTree test). Looks under the
## tree root first, then falls back to a same-parent sibling of the same name.
func _autoload(node_name: String) -> Object:
	if is_inside_tree():
		var tree := get_tree()
		if tree != null and tree.root != null:
			var found := tree.root.get_node_or_null(NodePath(node_name))
			if found != null:
				return found
	var parent := get_parent()
	if parent != null:
		return parent.get_node_or_null(NodePath(node_name))
	return null
