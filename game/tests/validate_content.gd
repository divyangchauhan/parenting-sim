extends SceneTree
## Headless content validator for "Enough".
##
## Asserts every rule in content/schema.md against the JSON under content/,
## WITHOUT relying on the EventDeck autoload — it re-reads and parses the files
## directly so a bug in the autoload can't mask a bug in the content (and vice
## versa). Run with:
##
##   godot --headless --path game --script tests/validate_content.gd
##
## On the first violation it prints a clear message naming the file/id and
## quits with code 1. On success it prints a summary and quits with code 0.

const EVENTS_DIR := "res://content/events"
const INTERSTITIALS_DIR := "res://content/interstitials"
const ENDINGS_FILE := "res://content/endings.json"

# Mirrors of the schema's allowed sets / bounds. Kept here (not pulled from
# GameState) so the validator stays independent of runtime code.
const WEEK_LENGTH := 7
const VALID_SOURCES := ["child", "partner", "work", "self"]
const VALID_TONES := ["warm", "neutral", "curt"]
const HIDDEN_STATES := ["connection", "security", "partnership", "wellbeing", "standing"]
const COST_KEYS := ["time", "energy", "patience"]
const GATE_KEYS := ["energy_min", "patience_min"]


## Set true by _fail() so the synchronous _init body unwinds immediately —
## quit() is deferred in Godot, so we must stop running validation ourselves
## after the first violation rather than letting later checks (and the success
## print) execute.
var _failed := false


func _init() -> void:
	var cards := _load_dir(EVENTS_DIR)
	if _failed: return
	var interstitials := _load_dir(INTERSTITIALS_DIR)
	if _failed: return
	var endings := _load_endings()
	if _failed: return

	_validate_cards(cards)
	if _failed: return
	_validate_interstitials(interstitials)
	if _failed: return
	_validate_endings(endings)
	if _failed: return

	print("Content valid: %d cards, %d interstitials, %d endings" % [
		cards.size(), interstitials.size(), endings.size()
	])
	quit(0)


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

## Parse every *.json in `dir_path` into an Array of {path, data} entries.
func _load_dir(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_fail(dir_path, "cannot open content directory")
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var path := "%s/%s" % [dir_path, file_name]
		var data = _parse(path)
		if typeof(data) != TYPE_DICTIONARY:
			_fail(path, "top-level value must be a JSON object")
		out.append({"path": path, "data": data})
	return out


func _load_endings() -> Array:
	var data = _parse(ENDINGS_FILE)
	if typeof(data) != TYPE_ARRAY:
		_fail(ENDINGS_FILE, "endings.json must be a JSON array")
	return data


func _parse(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail(path, "cannot read file")
	var text := file.get_as_text()
	file.close()
	var result = JSON.parse_string(text)
	if result == null:
		_fail(path, "invalid JSON (parse failed)")
	return result


# ---------------------------------------------------------------------------
# Card validation
# ---------------------------------------------------------------------------

func _validate_cards(cards: Array) -> void:
	var seen_ids: Dictionary = {}
	var all_ids: Dictionary = {}

	# First pass: collect ids so followups can be cross-checked.
	for entry in cards:
		all_ids[String(entry["data"].get("id", ""))] = true

	for entry in cards:
		var path: String = entry["path"]
		var card: Dictionary = entry["data"]
		var id := String(card.get("id", ""))

		if id.is_empty():
			_fail(path, "missing 'id'")
		if not _is_snake_case(id):
			_fail(path, "id '%s' is not snake_case" % id)
		if seen_ids.has(id):
			_fail(path, "duplicate id '%s'" % id)
		seen_ids[id] = true

		var source := String(card.get("source", ""))
		if not VALID_SOURCES.has(source):
			_fail(path, "source '%s' not in %s" % [source, VALID_SOURCES])

		var day_min := int(card.get("day_min", 0))
		var day_max := int(card.get("day_max", 0))
		if day_min < 1 or day_max > WEEK_LENGTH:
			_fail(path, "day range [%d, %d] must sit within [1, %d]" % [day_min, day_max, WEEK_LENGTH])
		if day_min > day_max:
			_fail(path, "day_min (%d) must be <= day_max (%d)" % [day_min, day_max])

		_validate_responses(path, id, card, all_ids)


func _validate_responses(path: String, id: String, card: Dictionary, all_ids: Dictionary) -> void:
	var responses = card.get("responses", [])
	if typeof(responses) != TYPE_ARRAY:
		_fail(path, "'responses' must be an array")
	if responses.size() < 2 or responses.size() > 3:
		_fail(path, "card '%s' has %d responses; must be 2..3" % [id, responses.size()])

	var has_zero_reserve_option := false

	for i in responses.size():
		var r = responses[i]
		if typeof(r) != TYPE_DICTIONARY:
			_fail(path, "response %d is not an object" % i)
		var label := "card '%s' response %d" % [id, i]

		var tone := String(r.get("tone", ""))
		if not VALID_TONES.has(tone):
			_fail(path, "%s tone '%s' not in %s" % [label, tone, VALID_TONES])

		# Costs: every present cost key must be a known key and >= 0.
		var cost: Dictionary = r.get("cost", {})
		for key in cost:
			if not COST_KEYS.has(String(key)):
				_fail(path, "%s unknown cost key '%s'" % [label, key])
			if int(cost[key]) < 0:
				_fail(path, "%s cost '%s' is negative" % [label, key])

		# Effects: every key must be a known hidden state.
		var effects: Dictionary = r.get("effects", {})
		for key in effects:
			if not HIDDEN_STATES.has(String(key)):
				_fail(path, "%s effect key '%s' not a hidden state" % [label, key])

		# Gated_by: keys must be known; values >= 0.
		var gated_by: Dictionary = r.get("gated_by", {})
		for key in gated_by:
			if not GATE_KEYS.has(String(key)):
				_fail(path, "%s unknown gated_by key '%s'" % [label, key])
			if int(gated_by[key]) < 0:
				_fail(path, "%s gated_by '%s' is negative" % [label, key])

		# Followup must reference an existing card id.
		var followup := String(r.get("followup", ""))
		if not followup.is_empty() and not all_ids.has(followup):
			_fail(path, "%s followup '%s' references unknown card" % [label, followup])

		if _is_reachable_at_zero_reserve(gated_by):
			has_zero_reserve_option = true

	if not has_zero_reserve_option:
		_fail(path, "card '%s' soft-locks: no response is reachable at zero reserves" % id)


## A response is reachable at zero reserves when it has no gate, or all gate
## minimums are zero.
func _is_reachable_at_zero_reserve(gated_by: Dictionary) -> bool:
	for key in gated_by:
		if int(gated_by[key]) > 0:
			return false
	return true


# ---------------------------------------------------------------------------
# Interstitial validation
# ---------------------------------------------------------------------------

func _validate_interstitials(interstitials: Array) -> void:
	var seen_ids: Dictionary = {}
	for entry in interstitials:
		var path: String = entry["path"]
		var inter: Dictionary = entry["data"]
		var id := String(inter.get("id", ""))

		if id.is_empty():
			_fail(path, "missing 'id'")
		if not _is_snake_case(id):
			_fail(path, "id '%s' is not snake_case" % id)
		if seen_ids.has(id):
			_fail(path, "duplicate interstitial id '%s'" % id)
		seen_ids[id] = true

		if int(inter.get("after_day_min", 0)) < 1:
			_fail(path, "interstitial '%s' after_day_min must be >= 1" % id)

		var lines = inter.get("lines", [])
		if typeof(lines) != TYPE_ARRAY or lines.is_empty():
			_fail(path, "interstitial '%s' must have a non-empty 'lines' array" % id)

		_validate_state_block(path, "interstitial '%s' select_when" % id, inter.get("select_when", {}))


# ---------------------------------------------------------------------------
# Ending validation
# ---------------------------------------------------------------------------

func _validate_endings(endings: Array) -> void:
	if endings.is_empty():
		_fail(ENDINGS_FILE, "must contain at least one ending")

	var seen_ids: Dictionary = {}
	var has_default := false

	for ending in endings:
		if typeof(ending) != TYPE_DICTIONARY:
			_fail(ENDINGS_FILE, "every ending must be a JSON object")
		var id := String(ending.get("id", ""))

		if id.is_empty():
			_fail(ENDINGS_FILE, "an ending is missing 'id'")
		if not _is_snake_case(id):
			_fail(ENDINGS_FILE, "ending id '%s' is not snake_case" % id)
		if seen_ids.has(id):
			_fail(ENDINGS_FILE, "duplicate ending id '%s'" % id)
		seen_ids[id] = true

		if String(ending.get("title", "")).is_empty():
			_fail(ENDINGS_FILE, "ending '%s' missing 'title'" % id)

		var lines = ending.get("lines", [])
		if typeof(lines) != TYPE_ARRAY or lines.is_empty():
			_fail(ENDINGS_FILE, "ending '%s' must have a non-empty 'lines' array" % id)

		var match_block: Dictionary = ending.get("match", {})
		_validate_state_block(ENDINGS_FILE, "ending '%s' match" % id, match_block)

		# A default ending matches everything (empty match block).
		if match_block.get("state_min", {}).is_empty() and match_block.get("state_max", {}).is_empty():
			has_default = true

	if not has_default:
		_fail(ENDINGS_FILE, "no default ending (one with an empty 'match') — run could end with no result")


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

## Validate a {state_min, state_max} block: each must be a Dictionary whose keys
## are known hidden states.
func _validate_state_block(path: String, label: String, block: Dictionary) -> void:
	for sub_key in ["state_min", "state_max"]:
		if not block.has(sub_key):
			continue
		var sub = block[sub_key]
		if typeof(sub) != TYPE_DICTIONARY:
			_fail(path, "%s '%s' must be an object" % [label, sub_key])
		for key in sub:
			if not HIDDEN_STATES.has(String(key)):
				_fail(path, "%s '%s' key '%s' not a hidden state" % [label, sub_key, key])


## True if `s` is non-empty lower_snake_case (letters, digits, underscores; must
## start with a letter).
func _is_snake_case(s: String) -> bool:
	if s.is_empty():
		return false
	var re := RegEx.new()
	re.compile("^[a-z][a-z0-9_]*$")
	return re.search(s) != null


## Print a failure naming the file and reason, flag the run as failed, and quit
## with code 1. quit() is deferred, so _failed is what actually unwinds _init.
func _fail(path: String, reason: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("Content INVALID — %s: %s" % [path, reason])
	printerr("Content INVALID — %s: %s" % [path, reason])
	quit(1)
