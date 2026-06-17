extends Node
## Autoplayer — headless end-to-end harness driver (test scaffolding only).
##
## Gated behind the AUTOPLAY=1 env var and never added on the normal play path.
## It drives the REAL DayShift + Card + autoloads through the SAME unified flow a
## human would: on each presented card it picks a response (per mode), and on
## each between-day Interstitial it auto-advances. DayShift owns the day-to-day
## chaining now — the autoplayer no longer calls start_shift() itself; it just
## observes DayShift's signals. When the Ending screen appears (ending_shown) it
## asserts the run completed and quits 0. This is the stand-in for a human while
## there is no display.

## Safety cap: total cards answered across the whole run before we bail (guards
## against an unexpected non-terminating loop turning into a hung CI job).
const MAX_TOTAL_ACTIONS := 2000

## Stress mode must drive fatigue at least this deep to count as a real exercise
## of the burnout path.
const STRESS_MIN_FATIGUE := 2

var _dayshift: Node = null
var _days_completed := 0
var _actions := 0
var _run_ended := false

## Drive mode, from env AUTOPLAY_MODE: "first" (default) picks the first enabled
## response (original behaviour); "stress" picks the highest-cost enabled
## response each card to deplete reserves fast and exercise the fatigue system.
var _mode := "first"

## Highest fatigue level observed across the run (for the stress-mode assertion
## and report line).
var _max_fatigue := 0


func _init() -> void:
	var mode := OS.get_environment("AUTOPLAY_MODE")
	if mode == "stress":
		_mode = "stress"


## Connect to `dayshift` BEFORE it enters the tree, so we catch the very first
## card it presents in its _ready(). `dayshift` need not be in the tree yet —
## signal connections are valid pre-_ready.
func start_pending(dayshift: Node) -> void:
	_dayshift = dayshift
	_dayshift.card_presented.connect(_on_card_presented)
	_dayshift.day_finished.connect(_on_day_finished)
	_dayshift.interstitial_shown.connect(_on_interstitial_shown)
	_dayshift.ending_shown.connect(_on_ending_shown)
	GameState.fatigue_level_changed.connect(_on_fatigue_level_changed)
	GameState.run_ended.connect(_on_run_ended)
	# Seed from the current level in case it never changes during the run.
	_max_fatigue = maxi(_max_fatigue, GameState.fatigue_level())


func _on_fatigue_level_changed(level: int) -> void:
	_max_fatigue = maxi(_max_fatigue, level)


func _on_card_presented(card_node) -> void:
	# Defer to the next idle frame so DayShift has fully settled the card, then
	# act. call_deferred keeps us off the signal's own call stack.
	call_deferred("_act_on_card", card_node)


func _act_on_card(card_node) -> void:
	if not is_instance_valid(card_node):
		return

	_actions += 1
	if _actions > MAX_TOTAL_ACTIONS:
		push_error("AUTOPLAY: exceeded MAX_TOTAL_ACTIONS — aborting.")
		get_tree().quit(1)
		return

	var button := _pick_button(card_node)
	if button != null:
		button.pressed.emit()
	else:
		# Nothing affordable/ungated: defer the card so the day can still drain.
		card_node.deferred.emit()


## Choose which enabled response to press, per mode. "first" returns the first
## enabled button (original behaviour); "stress" returns the highest-cost enabled
## button to deplete reserves as fast as possible. Null if none are enabled.
func _pick_button(card_node) -> Button:
	if _mode == "stress":
		return _highest_cost_enabled_button(card_node)
	return _first_enabled_button(card_node)


## Find the first non-disabled response Button under the card, or null.
func _first_enabled_button(card_node) -> Button:
	for response_box in _find_response_buttons(card_node):
		if response_box is Button and not response_box.disabled:
			return response_box
	return null


## Find the enabled response Button whose total spend (time+energy+patience) is
## greatest, to drain reserves fastest. Null if none are enabled.
func _highest_cost_enabled_button(card_node) -> Button:
	var best: Button = null
	var best_cost := -1
	for child in _find_response_buttons(card_node):
		if not (child is Button) or child.disabled:
			continue
		var response: Dictionary = child.get_meta("response", {})
		var cost: Dictionary = response.get("cost", {})
		var total := int(cost.get("time", 0)) + int(cost.get("energy", 0)) + int(cost.get("patience", 0))
		if total > best_cost:
			best_cost = total
			best = child
	return best


## Collect every response Button the card built (excludes the defer button,
## which lives outside the Responses container).
func _find_response_buttons(card_node) -> Array:
	var found: Array = []
	var box: Node = card_node.get_node_or_null("%Responses")
	if box != null:
		for child in box.get_children():
			if child is Button:
				found.append(child)
	return found


## DayShift owns chaining now: it advances to the interstitial / next day / ending
## by itself. We only tally completed days for the report line; the actual
## traversal is driven by reacting to interstitial_shown / ending_shown.
func _on_day_finished(_day: int) -> void:
	_days_completed += 1


## Auto-advance a between-day Interstitial so the headless run keeps moving. We
## defer the advance so DayShift has finished wiring the overlay before we drive
## it; advance() emits the node's finished() that DayShift is awaiting.
func _on_interstitial_shown(interstitial_node) -> void:
	if is_instance_valid(interstitial_node):
		interstitial_node.call_deferred("advance")


## The run reached its Ending. Assert it actually completed the week, emit the
## report line for this mode, and quit 0. (Dismiss the ending too, for tidiness,
## though we exit right after.)
func _on_ending_shown(ending_node) -> void:
	if not _run_ended:
		push_error("AUTOPLAY: ending shown but run_ended never fired.")
		get_tree().quit(1)
		return
	_finish()


func _on_run_ended() -> void:
	_run_ended = true


func _finish() -> void:
	if _mode == "stress":
		if _max_fatigue < STRESS_MIN_FATIGUE:
			push_error("AUTOPLAY[stress]: fatigue only reached L%d (< L%d) — burnout path not exercised." % [
				_max_fatigue, STRESS_MIN_FATIGUE])
			get_tree().quit(1)
			return
		print("AUTOPLAY[stress]: max fatigue reached L%d, completed %d days" % [
			_max_fatigue, _days_completed])
		get_tree().quit(0)
		return

	print("AUTOPLAY: completed %d days, run ended" % _days_completed)
	get_tree().quit(0)
