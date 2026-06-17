extends Node
## EventDeck — content service for events, interstitials, and endings.
##
## Loads all writer-authored JSON under `res://content/` into in-memory
## dictionaries and serves it on request. It is a *read-only content service*:
## it does NOT own the live day queue (DayShift will, in PR-03). It only knows
## how to parse content and decide what is *eligible* given the current
## GameState. Eligibility/condition logic lives in small reusable private
## helpers so cards, interstitials, and endings all share one evaluator.
##
## Autoloaded (see project.godot). Call sites depend on the public API below.

# ---------------------------------------------------------------------------
# Content locations
# ---------------------------------------------------------------------------

const EVENTS_DIR := "res://content/events"
const INTERSTITIALS_DIR := "res://content/interstitials"
const ENDINGS_FILE := "res://content/endings.json"

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted once all content has been (re)loaded into memory.
signal deck_loaded()

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## id -> card Dictionary.
var _cards: Dictionary = {}

## id -> interstitial Dictionary.
var _interstitials: Dictionary = {}

## Array of ending Dictionaries (ordered as authored; queried by priority).
var _endings: Array = []

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	load_content()

## (Re)load every content file from disk. Bad files are reported and skipped so
## one malformed card never takes down the whole deck. Emits deck_loaded().
func load_content() -> void:
	_cards.clear()
	_interstitials.clear()
	_endings.clear()

	_load_card_dir(EVENTS_DIR, _cards)
	_load_card_dir(INTERSTITIALS_DIR, _interstitials)
	_load_endings(ENDINGS_FILE)

	deck_loaded.emit()

# ---------------------------------------------------------------------------
# File loading helpers
# ---------------------------------------------------------------------------

## Enumerate every *.json in `dir_path`, parse each into `target` keyed by its
## "id" field. Malformed or id-less files are reported via push_error and
## skipped.
func _load_card_dir(dir_path: String, target: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("EventDeck: cannot open content dir: %s" % dir_path)
		return

	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var full_path := "%s/%s" % [dir_path, file_name]
		var parsed = _read_json(full_path)
		if parsed == null:
			continue
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("EventDeck: %s is not a JSON object; skipped." % full_path)
			continue
		var id := String(parsed.get("id", ""))
		if id.is_empty():
			push_error("EventDeck: %s has no 'id'; skipped." % full_path)
			continue
		if target.has(id):
			push_error("EventDeck: duplicate id '%s' in %s; skipped." % [id, full_path])
			continue
		target[id] = parsed

## Read and parse the endings array file. Reports and tolerates a missing or
## malformed file (leaves _endings empty).
func _load_endings(path: String) -> void:
	var parsed = _read_json(path)
	if parsed == null:
		return
	if typeof(parsed) != TYPE_ARRAY:
		push_error("EventDeck: %s must be a JSON array; ignored." % path)
		return
	_endings = parsed

## Read a JSON file and return the decoded value, or null on any failure
## (reporting a clear error). Never crashes the caller.
func _read_json(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("EventDeck: cannot read file: %s" % path)
		return null
	var text := file.get_as_text()
	file.close()
	var result = JSON.parse_string(text)
	if result == null:
		push_error("EventDeck: failed to parse JSON: %s" % path)
		return null
	return result

# ---------------------------------------------------------------------------
# Card queries
# ---------------------------------------------------------------------------

## Build the list of cards eligible for `day`, ordered by descending priority
## with a deterministic id tie-break. Eligibility = day within the card's
## [day_min, day_max] range AND its conditions currently pass. This returns
## *content*; the live runtime queue (consumption, dedup, weighting) is owned
## by DayShift in PR-03.
func build_day_queue(day: int) -> Array:
	var eligible: Array = []
	for id in _cards:
		var card: Dictionary = _cards[id]
		if not _card_in_day_range(card, day):
			continue
		if not _passes_conditions(card):
			continue
		eligible.append(card)

	eligible.sort_custom(_compare_cards_for_queue)
	return eligible

## Sort comparator: higher priority first; equal priority breaks by id ascending
## so ordering is fully deterministic.
func _compare_cards_for_queue(a: Dictionary, b: Dictionary) -> bool:
	var pa := int(a.get("priority", 0))
	var pb := int(b.get("priority", 0))
	if pa != pb:
		return pa > pb
	return String(a.get("id", "")) < String(b.get("id", ""))

## True if `day` falls within the card's eligible range. Missing bounds default
## to "always eligible".
func _card_in_day_range(card: Dictionary, day: int) -> bool:
	var day_min := int(card.get("day_min", 1))
	var day_max := int(card.get("day_max", GameState.WEEK_LENGTH))
	return day >= day_min and day <= day_max

## Look up a card by id. Returns {} and reports an error if it is unknown.
func get_card(id: String) -> Dictionary:
	if not _cards.has(id):
		push_error("EventDeck: no card with id '%s'." % id)
		return {}
	return _cards[id]

## True if a card with `id` exists.
func has_card(id: String) -> bool:
	return _cards.has(id)

## All loaded cards (id -> card). Used by the content validator.
func all_cards() -> Dictionary:
	return _cards

# ---------------------------------------------------------------------------
# Condition evaluation (shared by cards / interstitials / endings)
# ---------------------------------------------------------------------------

## Evaluate a card's `conditions` block against the live GameState. A missing
## conditions block always passes. Rules:
##   flags_any  — pass if the run has ANY listed flag (empty list passes).
##   flags_none — fail if the run has ANY listed flag.
##   state_min  — each key: GameState.states[key] must be >= the value.
##   state_max  — each key: GameState.states[key] must be <= the value.
func _passes_conditions(card: Dictionary) -> bool:
	var conditions: Dictionary = card.get("conditions", {})
	if conditions.is_empty():
		return true

	if not _passes_flags_any(conditions.get("flags_any", [])):
		return false
	if not _passes_flags_none(conditions.get("flags_none", [])):
		return false
	if not _passes_state_min(conditions.get("state_min", {})):
		return false
	if not _passes_state_max(conditions.get("state_max", {})):
		return false
	return true

## Pass if the list is empty, or the run holds at least one of the flags.
func _passes_flags_any(flags_any: Array) -> bool:
	if flags_any.is_empty():
		return true
	for flag in flags_any:
		if GameState.has_flag(String(flag)):
			return true
	return false

## Fail (return false) if the run holds any of the forbidden flags.
func _passes_flags_none(flags_none: Array) -> bool:
	for flag in flags_none:
		if GameState.has_flag(String(flag)):
			return false
	return true

## Each key in `state_min` requires the matching hidden state to be >= value.
func _passes_state_min(state_min: Dictionary) -> bool:
	for key in state_min:
		if int(GameState.states.get(key, 0)) < int(state_min[key]):
			return false
	return true

## Each key in `state_max` requires the matching hidden state to be <= value.
func _passes_state_max(state_max: Dictionary) -> bool:
	for key in state_max:
		if int(GameState.states.get(key, 0)) > int(state_max[key]):
			return false
	return true

## Convenience evaluator for the {state_min, state_max} blocks used by
## interstitials' `select_when` and endings' `match`. Returns whether they pass
## and how many individual constraints were checked (for specificity ranking).
func _eval_state_block(block: Dictionary) -> Dictionary:
	var state_min: Dictionary = block.get("state_min", {})
	var state_max: Dictionary = block.get("state_max", {})
	var passes := _passes_state_min(state_min) and _passes_state_max(state_max)
	var specificity := state_min.size() + state_max.size()
	return {"passes": passes, "specificity": specificity}

# ---------------------------------------------------------------------------
# Interstitials
# ---------------------------------------------------------------------------

## Pick the interstitial to play after finishing `after_day`. Candidates must
## have after_day_min <= after_day and a passing `select_when` state block. The
## most-specific match wins (most constraints satisfied), with an id tie-break
## for determinism. Returns {} if nothing qualifies.
func select_interstitial(after_day: int) -> Dictionary:
	var best: Dictionary = {}
	var best_specificity := -1
	var best_id := ""

	for id in _interstitials:
		var inter: Dictionary = _interstitials[id]
		if int(inter.get("after_day_min", 1)) > after_day:
			continue
		var eval := _eval_state_block(inter.get("select_when", {}))
		if not eval["passes"]:
			continue
		var specificity := int(eval["specificity"])
		if specificity > best_specificity \
				or (specificity == best_specificity and String(id) < best_id):
			best = inter
			best_specificity = specificity
			best_id = String(id)

	return best

# ---------------------------------------------------------------------------
# Endings
# ---------------------------------------------------------------------------

## Choose the ending for the run's final hidden states. Among entries whose
## `match` block passes, the highest priority wins (id tie-break). If none
## match, fall back to the lowest-priority entry as the default. Never returns
## {} when any endings are loaded.
func select_ending() -> Dictionary:
	if _endings.is_empty():
		push_error("EventDeck: no endings loaded.")
		return {}

	var chosen: Dictionary = {}
	var chosen_priority := -2147483648
	var chosen_id := ""

	for ending in _endings:
		var eval := _eval_state_block(ending.get("match", {}))
		if not eval["passes"]:
			continue
		var priority := int(ending.get("priority", 0))
		var id := String(ending.get("id", ""))
		if priority > chosen_priority \
				or (priority == chosen_priority and id < chosen_id):
			chosen = ending
			chosen_priority = priority
			chosen_id = id

	if chosen.is_empty():
		return _default_ending()
	return chosen

## The fallback ending when nothing matches: the lowest-priority entry (the
## broadest / most default-feeling one), id tie-break.
func _default_ending() -> Dictionary:
	var fallback: Dictionary = {}
	var fallback_priority := 2147483647
	var fallback_id := ""
	for ending in _endings:
		var priority := int(ending.get("priority", 0))
		var id := String(ending.get("id", ""))
		if priority < fallback_priority \
				or (priority == fallback_priority and id < fallback_id):
			fallback = ending
			fallback_priority = priority
			fallback_id = id
	return fallback
