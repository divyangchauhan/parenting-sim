extends Node
## balance_report — dev-QA playtest harness (not shipped).
##
## Plays the full week under several player "strategies" and prints the resulting
## hidden states + which ending fires for each. Mirrors DayShift's day loop
## (build_day_queue -> pick a response per card under time pressure -> end_day) but
## headless and deterministic, so we can sanity-check the emotional arithmetic and
## confirm the endings actually differentiate. Run:
##   godot --path game tools/balance_report.tscn   (or --headless)

const STRATEGIES := ["warm", "curt", "balanced", "defer_heavy"]


func _ready() -> void:
	print("\n=== BALANCE REPORT — %d-day week ===" % GameState.WEEK_LENGTH)
	for strat in STRATEGIES:
		_run_strategy(strat)
	print("=== end report ===\n")
	get_tree().quit(0)


## Play one full run under `strategy`, then print final states + ending.
func _run_strategy(strategy: String) -> void:
	GameState.new_run()
	var cards_seen := 0
	var cards_done := 0
	var deferred := 0

	for day in range(1, GameState.WEEK_LENGTH + 1):
		GameState.start_day()
		var queue: Array = EventDeck.build_day_queue(day)
		var seen_this_day := {}
		for card in queue:
			if GameState.time <= 0:
				break
			cards_seen += 1
			var id := String(card.get("id", ""))
			if seen_this_day.has(id):
				continue
			seen_this_day[id] = true
			var response: Dictionary = _pick(card, strategy)
			if response.is_empty():
				deferred += 1
				continue
			GameState.apply_response(response)
			cards_done += 1
		GameState.end_day()

	var ending: Dictionary = EventDeck.select_ending()
	print("\n-- strategy: %s --" % strategy)
	print("  cards: %d seen / %d resolved / %d deferred" % [cards_seen, cards_done, deferred])
	print("  reserves left: energy %d, patience %d" % [GameState.energy, GameState.patience])
	print("  states: %s" % _fmt_states())
	print("  ENDING: \"%s\"  (%s)" % [ending.get("title", "?"), ending.get("id", "?")])


## Choose a response under the strategy from the affordable, non-gated options.
## Returns {} to mean "defer / do nothing" (only the defer_heavy strategy does so,
## and only sometimes). Falls back to the cheapest reachable option otherwise.
func _pick(card: Dictionary, strategy: String) -> Dictionary:
	var responses: Array = card.get("responses", [])
	var reachable: Array = []
	for r in responses:
		var gated_by: Dictionary = r.get("gated_by", {})
		var cost: Dictionary = r.get("cost", {})
		if not GameState.is_response_gated(gated_by) and GameState.can_afford(cost):
			reachable.append(r)
	if reachable.is_empty():
		return {}

	match strategy:
		"warm":
			return _first_with_tone(reachable, "warm")
		"curt":
			return _first_with_tone(reachable, "curt")
		"defer_heavy":
			# Defer roughly half the time; otherwise take the first reachable.
			if (GameState.time + GameState.energy) % 2 == 0:
				return {}
			return reachable[0]
		_:  # "balanced"
			return reachable[0]


## First reachable response matching `tone`, else the first reachable.
func _first_with_tone(reachable: Array, tone: String) -> Dictionary:
	for r in reachable:
		if String(r.get("tone", "")) == tone:
			return r
	return reachable[0]


func _fmt_states() -> String:
	var parts: Array = []
	for key in GameState.HIDDEN_STATES:
		parts.append("%s %+d" % [key, int(GameState.states.get(key, 0))])
	return ", ".join(parts)
