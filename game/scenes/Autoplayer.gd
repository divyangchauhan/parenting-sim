extends Node
## Autoplayer — headless end-to-end harness driver (test scaffolding only).
##
## Gated behind the AUTOPLAY=1 env var and never added on the normal play path.
## It drives the REAL DayShift + Card + autoloads: on each presented card it
## picks the first enabled response (cheapest fallback / defer if none), chains
## across all days, and quits 0 once GameState.run_ended() fires. This is the
## stand-in for a human while there is no display.

## Safety cap: total cards answered across the whole run before we bail (guards
## against an unexpected non-terminating loop turning into a hung CI job).
const MAX_TOTAL_ACTIONS := 2000

var _dayshift: Node = null
var _days_completed := 0
var _actions := 0
var _run_ended := false


## Connect to `dayshift` BEFORE it enters the tree, so we catch the very first
## card it presents in its _ready(). `dayshift` need not be in the tree yet —
## signal connections are valid pre-_ready.
func start_pending(dayshift: Node) -> void:
	_dayshift = dayshift
	_dayshift.card_presented.connect(_on_card_presented)
	_dayshift.day_finished.connect(_on_day_finished)
	GameState.run_ended.connect(_on_run_ended)


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

	var button := _first_enabled_button(card_node)
	if button != null:
		button.pressed.emit()
	else:
		# Nothing affordable/ungated: defer the card so the day can still drain.
		card_node.deferred.emit()


## Find the first non-disabled response Button under the card, or null.
func _first_enabled_button(card_node) -> Button:
	for response_box in _find_response_buttons(card_node):
		if response_box is Button and not response_box.disabled:
			return response_box
	return null


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


func _on_day_finished(day: int) -> void:
	_days_completed += 1
	if _run_ended:
		_finish()
		return
	# Chain straight into the next day's shift on the same DayShift node.
	_dayshift.call_deferred("start_shift")


func _on_run_ended() -> void:
	_run_ended = true


func _finish() -> void:
	print("AUTOPLAY: completed %d days, run ended" % _days_completed)
	get_tree().quit(0)
